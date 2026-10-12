package it.dailyfit.app;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.AtomicFile;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;
import org.json.JSONObject;

/** Single writer; a mutation becomes visible only after its atomic disk commit. */
public final class Store {
  public interface Listener {
    void changed();

    void error(String message);
  }

  private final AtomicFile file;
  private final Context context;
  private final ImageArchive images;
  private final SQLiteRecords records;
  private final RecordArchive archive = new RecordArchive();
  final ExecutorService worker = Executors.newSingleThreadExecutor();
  final ExecutorService imageWorker = Executors.newFixedThreadPool(2);
  final ExecutorService transferWorker = Executors.newSingleThreadExecutor();
  final Handler main = new Handler(Looper.getMainLooper());
  public volatile JSONObject data;
  public volatile String loadError;
  public volatile Listener listener;
  private volatile boolean loading;
  private final java.util.concurrent.atomic.AtomicInteger pendingChanges =
      new java.util.concurrent.atomic.AtomicInteger();
  public volatile boolean foreground;
  private JSONObject undo;
  private volatile long undoUntil;
  public volatile String undoLabel;
  private long undoGeneration;

  public Store(Context c) {
    context = c.getApplicationContext();
    file = new AtomicFile(new File(c.getNoBackupFilesDir(), "data-v1.json"));
    images = new ImageArchive(new DiskBlobs(new File(c.getNoBackupFilesDir(), "images-v2")));
    records = new SQLiteRecords(new File(c.getNoBackupFilesDir(), "records-v3.sqlite"));
  }

  public void load() {
    if (isBusy() || data != null) return;
    loading = true;
    worker.execute(
        () -> {
          try {
            JSONObject candidate;
            java.util.Map<String, byte[]> saved = records.read();
            if (!saved.isEmpty()) {
              JSONObject envelope = RecordArchive.join(saved);
              long metadataBytes = 0;
              for (byte[] row : saved.values()) metadataBytes += row.length;
              candidate = images.references(envelope, metadataBytes);
              Domain.validate(candidate);
              archive.adopt(saved, envelope);
            } else if (file.getBaseFile().exists()
                || new File(file.getBaseFile() + ".bak").exists()) {
              try (InputStream in = file.openRead()) {
                JSONObject stored =
                    J.parse(new String(read(in, Domain.MAX_BYTES), StandardCharsets.UTF_8));
                candidate = images.references(stored);
                Domain.validate(candidate);
                candidate = save(candidate);
              }
            } else {
              try (InputStream in = context.getAssets().open("defaults.json")) {
                candidate = J.parse(new String(read(in, Domain.MAX_BYTES), StandardCharsets.UTF_8));
              }
              Domain.validate(candidate);
              candidate = save(candidate);
            }
            // Cleanup only at cold start, before exposing any snapshots to editors or exports.
            // Photos removed this session stay available to Undo until the next cold start.
            try {
              images.cleanup();
            } catch (IOException ignored) {
            }
            data = candidate;
            loadError = null;
          } catch (Exception e) {
            loadError =
                "Archivio non aperto. I dati esistenti sono stati conservati. " + message(e);
          } finally {
            loading = false;
            publish();
          }
        });
  }

  public void change(Consumer<JSONObject> edit, Runnable success) {
    mutate(edit, null, success);
  }

  public boolean isBusy() {
    return loading || pendingChanges.get() != 0;
  }

  public void delete(String label, Consumer<JSONObject> edit, Runnable success) {
    mutate(edit, label, success);
  }

  private void mutate(Consumer<JSONObject> edit, String deletion, Runnable success) {
    if (data == null) {
      error("Archivio non disponibile.");
      return;
    }
    pendingChanges.incrementAndGet();
    worker.execute(
        () -> {
          try {
            JSONObject previous = data, candidate = J.copy(previous);
            edit.accept(candidate);
            candidate = (JSONObject) J.reuseUnchanged(candidate, previous);
            Domain.validateChanges(candidate, previous);
            if (!J.equal(candidate, previous)) {
              data = save(candidate);
              synchronized (this) {
                undoGeneration++;
                undo = null;
                undoUntil = 0;
                undoLabel = null;
                if (deletion != null && foreground) {
                  undo = previous;
                  undoUntil = SystemClock.elapsedRealtime() + 15000;
                  undoLabel = deletion;
                  long generation = undoGeneration;
                  main.postDelayed(
                      () -> {
                        synchronized (this) {
                          if (generation == undoGeneration) discardUndo();
                        }
                        publish();
                      },
                      15000);
                }
              }
            }
            main.post(
                () -> {
                  if (success != null) success.run();
                });
          } catch (Exception e) {
            error(message(e));
          } finally {
            pendingChanges.decrementAndGet();
            publish();
          }
        });
  }

  public void restore(JSONObject imported, Runnable done) {
    change(
        candidate -> {
          for (String key : Domain.keys(candidate)) candidate.remove(key);
          for (String key : Domain.keys(imported)) J.put(candidate, key, imported.opt(key));
        },
        done);
  }

  public boolean canUndo() {
    return undoUntil > SystemClock.elapsedRealtime() && undoLabel != null;
  }

  public synchronized void discardUndo() {
    undo = null;
    undoUntil = 0;
    undoLabel = null;
    undoGeneration++;
  }

  public void undo(Runnable success) {
    pendingChanges.incrementAndGet();
    worker.execute(
        () -> {
          try {
            JSONObject previous;
            long generation;
            synchronized (this) {
              if (!canUndo() || undo == null) return;
              previous = undo;
              generation = undoGeneration;
            }
            // The single writer serializes commits. Lifecycle callbacks must never
            // wait for validation or disk I/O while discarding the undo offer.
            Domain.validateChanges(previous, data);
            data = save(previous);
            synchronized (this) {
              if (generation == undoGeneration) discardUndo();
            }
            main.post(
                () -> {
                  if (success != null) success.run();
                });
          } catch (Exception e) {
            error(message(e));
          } finally {
            pendingChanges.decrementAndGet();
            publish();
          }
        });
  }

  byte[] readImage(String value) throws IOException {
    return images.readImage(value);
  }

  JSONObject withEmbeddedImages(JSONObject snapshot) throws IOException {
    return images.materialize(snapshot);
  }

  private JSONObject save(JSONObject candidate) throws IOException {
    ImageArchive.Packed packed = images.prepare(candidate);
    RecordArchive.Delta delta = archive.stage(packed.envelope);
    Domain.require(
        delta.totalBytes + packed.imageCharacters <= Domain.MAX_BYTES, "Archivio troppo grande.");
    records.apply(delta);
    archive.committed(delta);
    images.committed(packed);
    // Only after the database transaction succeeds can the obsolete archive go away.
    if (file.getBaseFile().exists()) file.delete();
    return images.references(packed.envelope, delta.totalBytes);
  }

  public void publish() {
    main.post(
        () -> {
          Listener l = listener;
          if (l != null) l.changed();
        });
  }

  public void error(String error) {
    main.post(
        () -> {
          Listener l = listener;
          if (l != null) l.error(error);
        });
  }

  static String message(Exception e) {
    return e.getMessage() == null ? e.getClass().getSimpleName() : e.getMessage();
  }

  public static byte[] read(InputStream in, int limit) throws IOException {
    if (in == null) throw new IOException("File non disponibile.");
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    byte[] block = new byte[8192];
    int n;
    while ((n = in.read(block)) != -1) {
      if (out.size() + n > limit) throw new IOException("File troppo grande.");
      out.write(block, 0, n);
    }
    return out.toByteArray();
  }
}
