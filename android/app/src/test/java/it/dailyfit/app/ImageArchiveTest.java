package it.dailyfit.app;

import static org.junit.Assert.*;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;
import org.junit.*;

public class ImageArchiveTest {
  static final class MemoryBlobs implements ImageArchive.Blobs {
    final Map<String, byte[]> files = new HashMap<>();
    int writes;

    public long size(String name) throws IOException {
      if (!files.containsKey(name)) throw new IOException("Missing image");
      return files.get(name).length;
    }

    public byte[] read(String name) throws IOException {
      byte[] b = files.get(name);
      if (b == null) throw new IOException("Missing image");
      return b.clone();
    }

    public void writeIfAbsent(String name, byte[] bytes) {
      if (!files.containsKey(name)) {
        files.put(name, bytes.clone());
        writes++;
      }
    }

    public void removeExcept(Set<String> names) {
      files.keySet().retainAll(names);
    }
  }

  JSONObject data;
  MemoryBlobs blobs;
  ImageArchive archive;

  @BeforeClass
  public static void seed() throws Exception {
    DomainTest.loadSeed();
  }

  @Before
  public void prepare() {
    data = J.parse(DomainTest.seed);
    blobs = new MemoryBlobs();
    archive = new ImageArchive(blobs);
  }

  JSONObject stored(ImageArchive.Packed p) {
    return J.parse(new String(p.bytes, StandardCharsets.UTF_8));
  }

  @Test
  public void structuralCopySharesOnlyImmutableStrings() {
    assertTrue(J.equal(42, 42.0));
    assertFalse(J.equal(42, 42.5));
    JSONObject copy = J.copy(data),
        originalExercise = J.at(J.array(data, "exercises"), 0),
        copiedExercise = J.at(J.array(copy, "exercises"), 0);
    assertSame(originalExercise.opt("photo"), copiedExercise.opt("photo"));
    assertNotSame(originalExercise, copiedExercise);
    J.put(copiedExercise, "name", "Changed");
    assertNotEquals(originalExercise.optString("name"), copiedExercise.optString("name"));
    assertFalse(J.equal(data, copy));
    assertTrue(J.equal(data, J.copy(data)));
  }

  @Test
  public void changedValidationStillRejectsInvalidNewPhoto() {
    Domain.validate(data);
    JSONObject copy = J.copy(data);
    J.put(J.at(J.array(copy, "exercises"), 0), "photo", "bad");
    try {
      Domain.validateChanges(copy, data);
      fail();
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void localMetadataIsSmallAndRoundTripsAllPhotos() throws Exception {
    ImageArchive.Packed p = archive.pack(data);
    archive.committed(p);
    assertTrue(p.bytes.length < 100000);
    assertEquals(30, blobs.files.size());
    JSONObject restored = new ImageArchive(blobs).unpack(stored(p));
    assertTrue(J.equal(data, restored));
    Domain.validate(restored);
  }

  @Test
  public void createAndDeleteDoNotRewriteAnyImages() throws Exception {
    ImageArchive.Packed p = archive.pack(data);
    archive.committed(p);
    int initial = blobs.writes;
    JSONObject created = J.copy(data);
    J.array(created, "notes")
        .put(
            J.obj("id", J.id(), "title", "New", "body", "Example", "updatedAt", Domain.swiftNow()));
    Domain.validateChanges(created, data);
    ImageArchive.Packed q = archive.pack(created);
    archive.committed(q);
    J.array(created, "notes").remove(J.array(created, "notes").length() - 1);
    ImageArchive.Packed r = archive.pack(created);
    archive.committed(r);
    assertEquals(initial, blobs.writes);
    assertTrue(q.bytes.length < 100000);
    assertTrue(r.bytes.length < 100000);
  }

  @Test
  public void changingOneImageWritesOnlyThatImage() throws Exception {
    ImageArchive.Packed p = archive.pack(data);
    archive.committed(p);
    int initial = blobs.writes;
    JSONObject modified = J.copy(data);
    byte[] newImage =
        Base64.getDecoder().decode(J.at(J.array(data, "exercises"), 0).optString("photo"));
    newImage[newImage.length - 1] ^= 1;
    J.put(
        J.at(J.array(modified, "exercises"), 0),
        "photo",
        Base64.getEncoder().encodeToString(newImage));
    ImageArchive.Packed q = archive.pack(modified);
    archive.committed(q);
    assertEquals(initial + 1, blobs.writes);
    archive.cleanup();
    assertEquals(30, blobs.files.size());
    assertTrue(J.equal(modified, new ImageArchive(blobs).unpack(stored(q))));
  }

  @Test
  public void undoRecreatesAnImageRemovedByCleanup() throws Exception {
    ImageArchive.Packed p = archive.pack(data);
    archive.committed(p);
    JSONObject deleted = J.copy(data);
    J.at(J.array(deleted, "exercises"), 0).remove("photo");
    ImageArchive.Packed q = archive.pack(deleted);
    archive.committed(q);
    archive.cleanup();
    assertEquals(29, blobs.files.size());
    ImageArchive.Packed undo = archive.pack(data);
    archive.committed(undo);
    assertEquals(30, blobs.files.size());
    assertTrue(J.equal(data, new ImageArchive(blobs).unpack(stored(undo))));
  }

  @Test
  public void failedMetadataCommitNeverChangesCommittedFiles() throws Exception {
    ImageArchive.Packed initial = archive.pack(data);
    archive.committed(initial);
    JSONObject changed = J.copy(data);
    J.at(J.array(changed, "exercises"), 0).remove("photo");
    archive.pack(changed); // Simulate metadata-write failure: never call committed().
    archive.cleanup();
    assertEquals(30, blobs.files.size());
    assertTrue(J.equal(data, new ImageArchive(blobs).unpack(stored(initial))));
    byte[] added =
        Base64.getDecoder().decode(J.at(J.array(data, "exercises"), 0).optString("photo"));
    added[added.length - 1] ^= 1;
    J.put(
        J.at(J.array(changed, "exercises"), 0), "photo", Base64.getEncoder().encodeToString(added));
    archive.pack(changed);
    archive.cleanup();
    assertEquals(30, blobs.files.size());
    ImageArchive.Packed retried = archive.pack(changed);
    archive.committed(retried);
    archive.cleanup();
    assertTrue(J.equal(changed, new ImageArchive(blobs).unpack(stored(retried))));
  }

  @Test
  public void missingOrTamperedImageIsRejected() throws Exception {
    ImageArchive.Packed p = archive.pack(data);
    archive.committed(p);
    String name = blobs.files.keySet().iterator().next();
    byte[] good = blobs.files.get(name);
    blobs.files.remove(name);
    try {
      new ImageArchive(blobs).unpack(stored(p));
      fail();
    } catch (IOException expected) {
    }
    blobs.files.put(name, new byte[] {1, 2, 3});
    try {
      new ImageArchive(blobs).unpack(stored(p));
      fail();
    } catch (IllegalArgumentException expected) {
    }
    blobs.files.put(name, good);
  }

  @Test
  public void privatePathsCannotEscapeAndLegacyFilesStillLoad() throws Exception {
    assertSame(data, archive.unpack(data));
    try {
      ImageArchive.checkName("../../private");
      fail();
    } catch (IllegalArgumentException expected) {
    }
    ImageArchive.Packed p = archive.pack(data);
    JSONObject envelope = stored(p);
    JSONObject refs =
        J.object(J.object(envelope, "images"), J.id(J.at(J.array(data, "exercises"), 0)));
    J.put(refs, "photo", "../outside.bin");
    try {
      new ImageArchive(blobs).unpack(envelope);
      fail();
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void publicBackupStaysSelfContainedAfterLocalSave() throws Exception {
    ImageArchive.Packed p = archive.pack(data);
    archive.committed(p);
    JSONObject loaded = new ImageArchive(blobs).unpack(stored(p));
    byte[] backup = Domain.backup(loaded);
    blobs.files.clear();
    JSONObject restored = Domain.restore(backup);
    assertTrue(J.equal(data, restored));
    assertFalse(J.parse(new String(backup, StandardCharsets.UTF_8)).has("storageFormat"));
  }
}
