package it.dailyfit.app;

import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import org.json.*;

/** Measures serialization payload and CPU preparation, not device I/O or battery consumption. */
public final class PerformanceProbe {
  public static void main(String[] args) throws Exception {
    Path root = Paths.get(args[0]), out = root.resolve("build/tests");
    JSONObject original =
        J.parse(
            new String(
                Files.readAllBytes(root.resolve("app/src/main/assets/defaults.json")),
                StandardCharsets.UTF_8));
    J.array(original, "notes")
        .put(J.obj("id", J.id(), "title", "Nota", "body", "Testo 0", "updatedAt", 0));
    Domain.validate(original);
    ImageArchiveTest.MemoryBlobs blobs = new ImageArchiveTest.MemoryBlobs();
    ImageArchive images = new ImageArchive(blobs);
    RecordArchive records = new RecordArchive();
    ImageArchive.Packed first = images.prepare(original);
    records.committed(records.stage(first.envelope));
    images.committed(first);
    original = images.references(first.envelope);
    long elapsed = 0, recordBytes = 0;
    int metadataBytes = 0, count = 100;
    for (int i = 1; i <= count; i++) {
      long start = System.nanoTime();
      JSONObject next = J.copy(original);
      J.put(J.at(J.array(next, "notes"), 0), "body", "Testo " + i);
      next = (JSONObject) J.reuseUnchanged(next, original);
      Domain.validateChanges(next, original);
      ImageArchive.Packed packed = images.prepare(next);
      RecordArchive.Delta delta = records.stage(packed.envelope);
      records.committed(delta);
      images.committed(packed);
      elapsed += System.nanoTime() - start;
      recordBytes = delta.payloadBytes;
      if (delta.writes.size() != 1 || !delta.deletes.isEmpty())
        throw new AssertionError("Unrelated records written");
      // Outside the timed portion: the former storage re-encoded this whole envelope.
      metadataBytes = packed.envelope.toString().getBytes(StandardCharsets.UTF_8).length;
      original = images.references(packed.envelope);
    }
    String report =
        String.format(
            java.util.Locale.ROOT,
            "100 edits of an existing note; 15 exercises, 30 images. Windows JVM.\n"
                + "Previous v2 full metadata payload: %d bytes per edit.\n"
                + "New SQLite record payload: %d bytes, 1 record per edit.\n"
                + "Mean copy/validation/delta CPU preparation: %.3f ms.\n"
                + "Image files written after the initial import: %d.\n"
                + "Payload is NOT physical disk I/O: SQLite also writes pages, WAL and"
                + " checkpoints.\n"
                + "No phone latency or battery consumption was measured.\n",
            metadataBytes,
            recordBytes,
            elapsed / 1000000.0 / count,
            blobs.writes - 30);
    Files.write(out.resolve("performance-results.txt"), report.getBytes(StandardCharsets.UTF_8));
    System.out.print(report);
  }
}
