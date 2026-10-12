package it.dailyfit.app;

import android.util.AtomicFile;
import java.io.*;
import java.util.Set;

/** Access is serialized by Store's writer; all filenames are fixed SHA-256 identifiers. */
final class DiskBlobs implements ImageArchive.Blobs {
  private final File folder;

  DiskBlobs(File folder) {
    this.folder = folder;
  }

  private File file(String name) {
    ImageArchive.checkName(name);
    return new File(folder, name);
  }

  @Override
  public long size(String name) throws IOException {
    File target = file(name);
    if (!target.isFile()) throw new IOException("Immagine locale mancante.");
    return target.length();
  }

  @Override
  public byte[] read(String name) throws IOException {
    try (InputStream input = new AtomicFile(file(name)).openRead()) {
      return Store.read(input, 2_000_000);
    }
  }

  @Override
  public void writeIfAbsent(String name, byte[] bytes) throws IOException {
    File target = file(name);
    if (target.exists()) return;
    if (!folder.isDirectory() && !folder.mkdirs())
      throw new IOException("Cartella immagini non disponibile.");
    AtomicFile atomic = new AtomicFile(target);
    FileOutputStream out = null;
    try {
      out = atomic.startWrite();
      out.write(bytes);
      atomic.finishWrite(out);
    } catch (IOException error) {
      if (out != null) atomic.failWrite(out);
      throw error;
    }
  }

  @Override
  public void removeExcept(Set<String> names) {
    File[] files = folder.listFiles();
    if (files == null) return;
    for (File f : files)
      if (f.isFile() && f.getName().matches("[0-9a-f]{64}\\.bin") && !names.contains(f.getName()))
        new AtomicFile(f).delete();
  }
}
