package it.dailyfit.app;

import static org.junit.Assert.*;

import java.util.*;
import org.json.*;
import org.junit.*;

public class MemoryLoadingTest {
  private static final class Blobs implements ImageArchive.Blobs {
    final Map<String, byte[]> files = new HashMap<>();
    int reads;

    public long size(String name) {
      return files.get(name).length;
    }

    public byte[] read(String name) {
      reads++;
      return files.get(name).clone();
    }

    public void writeIfAbsent(String name, byte[] bytes) {
      files.putIfAbsent(name, bytes.clone());
    }

    public void removeExcept(Set<String> names) {
      files.keySet().retainAll(names);
    }
  }

  private Blobs blobs;
  private ImageArchive images;
  private JSONObject original, lazy;

  @Before
  public void setup() throws Exception {
    DomainTest.loadSeed();
    original = J.parse(DomainTest.seed);
    blobs = new Blobs();
    images = new ImageArchive(blobs);
    ImageArchive.Packed packed = images.prepare(original);
    images.committed(packed);
    lazy = images.references(packed.envelope);
  }

  @Test
  public void startupAndUnrelatedSaveReadZeroPhotos() throws Exception {
    assertEquals(0, blobs.reads);
    assertTrue(lazy.toString().length() < 100000);
    Domain.validate(lazy);
    J.array(lazy, "notes")
        .put(J.obj("id", J.id(), "title", "Nota", "body", "Testo", "updatedAt", Domain.swiftNow()));
    images.prepare(lazy);
    assertEquals(0, blobs.reads);
  }

  @Test
  public void openingOnePhotoReadsOnlyOneFile() throws Exception {
    String ref = J.at(J.array(lazy, "exercises"), 0).optString("photo");
    byte[] actual = images.readImage(ref);
    assertArrayEquals(
        Base64.getDecoder().decode(J.at(J.array(original, "exercises"), 0).optString("photo")),
        actual);
    assertEquals(1, blobs.reads);
  }

  @Test
  public void exportMaterializesSelfContainedPortableBackup() throws Exception {
    byte[] backup = Domain.backup(images.materialize(lazy));
    blobs.files.clear();
    assertTrue(J.equal(original, Domain.restore(backup)));
  }

  @Test
  public void referenceCannotBeImportedOrExportedAsPublicBackup() {
    try {
      Domain.backup(lazy);
      fail();
    } catch (IllegalArgumentException expected) {
    }
    byte[] forged =
        J.obj("format", "DailyFit", "version", 1, "data", lazy)
            .toString()
            .getBytes(java.nio.charset.StandardCharsets.UTF_8);
    try {
      Domain.restore(forged);
      fail();
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void corruptPhotoIsDetectedWhenReadAndNeverExported() throws Exception {
    String ref = J.at(J.array(lazy, "exercises"), 0).optString("photo");
    blobs.files.get(ref.substring(ImageArchive.LOCAL.length()))[0] ^= 1;
    try {
      images.readImage(ref);
      fail();
    } catch (IllegalArgumentException expected) {
    }
    try {
      images.materialize(lazy);
      fail();
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void deletionAndUndoKeepLazyReferencesReadable() throws Exception {
    JSONObject deleted = J.copy(lazy);
    J.at(J.array(deleted, "exercises"), 0).remove("photo");
    images.committed(images.prepare(deleted));
    images.committed(images.prepare(lazy));
    assertTrue(J.equal(original, images.materialize(lazy)));
  }

  @Test
  public void thousandRowsOnlySelectNearbyRows() {
    int[] heights = new int[1000];
    Arrays.fill(heights, 100);
    RowWindow r = RowWindow.calculate(heights, 50000, 600);
    assertEquals(494, r.first);
    assertEquals(512, r.end);
    assertEquals(100000, r.before + r.after + (r.end - r.first) * 100);
  }

  @Test
  public void unchangedHistoryIsSharedWithoutExposingMutableDrafts() {
    JSONObject previous =
        J.obj("dates", J.obj("2026-10-01", J.obj("note", "Testo")), "title", "prima");
    JSONObject draft = J.copy(previous);
    J.put(draft, "title", "dopo");
    JSONObject result = (JSONObject) J.reuseUnchanged(draft, previous);
    assertSame(previous.opt("dates"), result.opt("dates"));
    assertNotSame(previous, result);
    JSONObject next = J.copy(result);
    J.put(J.object(J.object(next, "dates"), "2026-10-01"), "note", "Modificato");
    assertEquals("Testo", J.object(J.object(previous, "dates"), "2026-10-01").optString("note"));
    assertEquals("Testo", J.object(J.object(result, "dates"), "2026-10-01").optString("note"));
  }

  @Test
  public void photoPreparationDoesNotCopyHistory() throws Exception {
    JSONObject metadata = J.object(images.prepare(lazy).envelope, "data");
    assertSame(lazy.opt("dates"), metadata.opt("dates"));
    assertSame(lazy.opt("notes"), metadata.opt("notes"));
  }

  @Test
  public void thousandHistoricDaysDoNotGetCopiedIntoEveryCommittedSnapshot() throws Exception {
    JSONObject dates = J.object(lazy, "dates");
    for (int i = 0; i < 1000; i++)
      J.put(
          dates,
          java.time.LocalDate.of(2020, 1, 1).plusDays(i).toString(),
          J.copy(J.at(J.array(lazy, "week"), 0)));
    Domain.validate(lazy);
    RecordArchive records = new RecordArchive();
    records.committed(records.stage(images.prepare(lazy).envelope));
    JSONObject draft = J.copy(lazy);
    J.array(draft, "notes")
        .put(J.obj("id", J.id(), "title", "Nota", "body", "Testo", "updatedAt", Domain.swiftNow()));
    draft = (JSONObject) J.reuseUnchanged(draft, lazy);
    Domain.validateChanges(draft, lazy);
    RecordArchive.Delta delta = records.stage(images.prepare(draft).envelope);
    assertSame(dates, J.object(draft, "dates"));
    assertEquals(2, delta.writes.size()); // New note and its ordering record.
    assertTrue(delta.writes.keySet().stream().noneMatch(k -> k.startsWith("date/")));
    assertEquals(0, blobs.reads);
  }

  @Test
  public void windowHandlesEmptyOffscreenAndVariableHeights() {
    RowWindow empty = RowWindow.calculate(new int[0], 0, 600);
    assertEquals(0, empty.end);
    RowWindow below = RowWindow.calculate(new int[] {100, 200, 300}, -1500, 600);
    assertEquals(0, below.end);
    assertEquals(600, below.after);
    RowWindow end = RowWindow.calculate(new int[] {100, 200, 300}, 2000, 600);
    assertEquals(3, end.first);
    assertEquals(600, end.before);
    assertEquals(0, end.after);
    RowWindow variable = RowWindow.calculate(new int[] {50, 500, 100, 900}, 700, 200);
    assertEquals(1, variable.first);
    assertEquals(4, variable.end);
  }
}
