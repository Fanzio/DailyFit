package it.dailyfit.app;

import static org.junit.Assert.*;

import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.LocalDate;
import java.util.*;
import org.json.*;
import org.junit.*;

public class RecordArchiveTest {
  JSONObject data;
  ImageArchive images;
  RecordArchive records;
  Map<String, byte[]> disk;
  ImageArchiveTest.MemoryBlobs blobs;

  @BeforeClass
  public static void seed() throws Exception {
    DomainTest.loadSeed();
  }

  @Before
  public void prepare() throws Exception {
    data = J.parse(DomainTest.seed);
    blobs = new ImageArchiveTest.MemoryBlobs();
    images = new ImageArchive(blobs);
    records = new RecordArchive();
    disk = new LinkedHashMap<>();
    commit(data);
  }

  RecordArchive.Delta commit(JSONObject next) throws Exception {
    ImageArchive.Packed packed = images.prepare(next);
    RecordArchive.Delta delta = records.stage(packed.envelope);
    for (String key : delta.deletes) disk.remove(key);
    disk.putAll(delta.writes);
    records.committed(delta);
    images.committed(packed);
    return delta;
  }

  JSONObject note(String title) {
    return J.obj("id", J.id(), "title", title, "body", "Appunto", "updatedAt", Domain.swiftNow());
  }

  @Test
  public void recordsRoundTripWithAllPhotosAndPublicBackup() throws Exception {
    JSONObject restored = new ImageArchive(blobs).unpack(RecordArchive.join(disk));
    Domain.validate(restored);
    assertTrue(J.equal(data, restored));
    assertTrue(J.equal(data, Domain.restore(Domain.backup(restored))));
  }

  @Test
  public void addingEditingAndDeletingNoteTouchesOnlyNoteAndOrder() throws Exception {
    JSONObject next = J.copy(data), n = note("Nuovo");
    J.array(next, "notes").put(n);
    String key = "notes/" + J.id(n);
    assertEquals(new HashSet<>(Arrays.asList(key, "order/notes")), commit(next).writes.keySet());
    JSONObject edited = J.copy(next);
    J.put(J.find(J.array(edited, "notes"), J.id(n)), "body", "Modificato");
    RecordArchive.Delta delta = commit(edited);
    assertEquals(Collections.singleton(key), delta.writes.keySet());
    assertTrue(delta.payloadBytes < 1000);
    delta = commit(data);
    assertEquals(Collections.singleton(key), delta.deletes);
    assertEquals(Collections.singleton("order/notes"), delta.writes.keySet());
    assertEquals(30, blobs.writes);
  }

  @Test
  public void loadChangeWritesOnlyOneGymDay() throws Exception {
    JSONObject next = J.copy(data),
        plan = J.at(J.array(next, "plans"), 0),
        day = J.at(J.array(plan, "days"), 0);
    J.put(J.at(J.array(J.at(J.array(day, "entries"), 0), "sets"), 0), "load", 42.5);
    Domain.validateChanges(next, data);
    assertEquals(
        Collections.singleton("day/" + J.id(plan) + "/" + J.id(day)), commit(next).writes.keySet());
  }

  @Test
  public void planDeletionRemovesDaysAndUndoRestoresThem() throws Exception {
    JSONObject next = J.copy(data), plan = J.at(J.array(next, "plans"), 0);
    J.array(next, "plans").remove(0);
    RecordArchive.Delta delta = commit(next);
    assertEquals(J.array(plan, "days").length() + 1, delta.deletes.size());
    assertEquals(Collections.singleton("order/plans"), delta.writes.keySet());
    commit(data);
    assertTrue(J.equal(data, new ImageArchive(blobs).unpack(RecordArchive.join(disk))));
  }

  @Test
  public void datedDietWritesOnlyItsDateAndLeavesBaseUntouched() throws Exception {
    JSONObject next = J.copy(data);
    J.put(J.object(next, "dates"), "2026-10-07", J.copy(J.at(J.array(next, "week"), 2)));
    assertEquals(Collections.singleton("date/2026-10-07"), commit(next).writes.keySet());
  }

  @Test
  public void unchangedSaveAndAdoptedDatabaseProduceNoWrites() throws Exception {
    assertTrue(commit(J.copy(data)).empty());
    RecordArchive reopened = new RecordArchive();
    reopened.adopt(disk);
    assertTrue(reopened.stage(images.prepare(data).envelope).empty());
  }

  @Test
  public void longHistoryStillWritesOnlyOneEditedNote() throws Exception {
    JSONObject history = J.copy(data);
    for (int i = 0; i < 1000; i++) J.array(history, "notes").put(note("Nota " + i));
    for (int i = 0; i < 365; i++)
      J.put(
          J.object(history, "dates"),
          LocalDate.of(2025, 1, 1).plusDays(i).toString(),
          J.copy(J.at(J.array(history, "week"), i % 7)));
    Domain.validateChanges(history, data);
    commit(history);
    JSONObject edited = J.copy(history), n = J.at(J.array(edited, "notes"), 500);
    J.put(n, "body", "Solo questo appunto cambia");
    Domain.validateChanges(edited, history);
    RecordArchive.Delta delta = commit(edited);
    assertEquals(Collections.singleton("notes/" + J.id(n)), delta.writes.keySet());
    assertTrue(delta.payloadBytes < 1000);
    assertTrue(J.equal(edited, new ImageArchive(blobs).unpack(RecordArchive.join(disk))));
  }

  @Test
  public void failureDoesNotAdvanceCommittedSnapshotAndRetryHasSameDelta() throws Exception {
    JSONObject next = J.copy(data);
    J.array(next, "notes").put(note("Da salvare"));
    RecordArchive.Delta failed = records.stage(images.prepare(next).envelope);
    assertFalse(failed.empty());
    assertTrue(records.stage(images.prepare(data).envelope).empty());
    RecordArchive.Delta retry = commit(next);
    assertEquals(failed.writes.keySet(), retry.writes.keySet());
    assertEquals(failed.payloadBytes, retry.payloadBytes);
  }

  @Test
  public void missingAndUnknownRecordsAreRejected() {
    Map<String, byte[]> broken = new HashMap<>(disk);
    broken.remove("week/0");
    assertThrows(IllegalArgumentException.class, () -> RecordArchive.join(broken));
    broken.clear();
    broken.putAll(disk);
    broken.put("unknown", new byte[] {123, 125});
    assertThrows(IllegalArgumentException.class, () -> RecordArchive.join(broken));
  }

  @Test
  public void exerciseEditDoesNotRewritePhotosOrOtherExercises() throws Exception {
    JSONObject next = J.copy(data), e = J.at(J.array(next, "exercises"), 0);
    J.put(e, "execution", "Descrizione aggiornata");
    assertEquals(Collections.singleton("exercises/" + J.id(e)), commit(next).writes.keySet());
    assertEquals(30, blobs.writes);
  }

  JSONObject screen(JSONObject d, int area, int tab, String plan, String day) {
    return RenderState.content(d, area, tab, plan, day, LocalDate.of(2026, 10, 7), false);
  }

  @Test
  public void noteChangesDoNotRebuildGymOrNutritionCatalog() {
    JSONObject next = J.copy(data);
    J.array(next, "notes").put(note("Nuovo"));
    assertTrue(J.equal(screen(data, 0, 1, "", ""), screen(next, 0, 1, "", "")));
    assertTrue(J.equal(screen(data, 1, 1, "", ""), screen(next, 1, 1, "", "")));
    assertFalse(J.equal(screen(data, 0, 2, "", ""), screen(next, 0, 2, "", "")));
  }

  @Test
  public void setChangesRebuildTrainingButNotPlanList() {
    JSONObject next = J.copy(data),
        p = J.at(J.array(next, "plans"), 0),
        d = J.at(J.array(p, "days"), 0);
    J.put(J.at(J.array(J.at(J.array(d, "entries"), 0), "sets"), 0), "load", 77);
    assertTrue(J.equal(screen(data, 0, 0, "", ""), screen(next, 0, 0, "", "")));
    assertFalse(
        J.equal(screen(data, 0, 0, J.id(p), J.id(d)), screen(next, 0, 0, J.id(p), J.id(d))));
  }

  @Test
  public void linkedExerciseChangeRefreshesVisibleTraining() {
    JSONObject next = J.copy(data),
        p = J.at(J.array(next, "plans"), 0),
        d = J.at(J.array(p, "days"), 0);
    String exercise = J.at(J.array(d, "entries"), 0).optString("exerciseID");
    J.put(Domain.exercise(next, exercise), "name", "Nuovo nome");
    assertFalse(
        J.equal(screen(data, 0, 0, J.id(p), J.id(d)), screen(next, 0, 0, J.id(p), J.id(d))));
  }

  @Test
  public void unrelatedSettingsDoNotRebuildVisibleContent() {
    JSONObject next = J.copy(data);
    J.put(next, "keepScreenAwake", !next.optBoolean("keepScreenAwake"));
    assertTrue(J.equal(screen(data, 0, 1, "", ""), screen(next, 0, 1, "", "")));
  }

  @Test
  public void exportsRecordFixtureForActualSQLiteTransactionChecks() throws Exception {
    Path folder = Paths.get(System.getProperty("export.output", "build/test-artifacts"), "records");
    Files.createDirectories(folder);
    JSONObject fixture = new JSONObject();
    for (Map.Entry<String, byte[]> row : disk.entrySet())
      J.put(fixture, row.getKey(), new String(row.getValue(), StandardCharsets.UTF_8));
    Files.write(
        folder.resolve("initial.json"), fixture.toString().getBytes(StandardCharsets.UTF_8));
    JSONObject next = J.copy(data);
    J.array(next, "notes").put(note("Record transaction"));
    RecordArchive.Delta delta = commit(next);
    JSONObject updates = new JSONObject();
    for (Map.Entry<String, byte[]> row : delta.writes.entrySet())
      J.put(updates, row.getKey(), new String(row.getValue(), StandardCharsets.UTF_8));
    Files.write(
        folder.resolve("updates.json"), updates.toString().getBytes(StandardCharsets.UTF_8));
  }

  @Test
  public void openingAndClosingMealUpdatesContentWithoutChangingData() {
    Set<String> expanded = new HashSet<>();
    LocalDate date = LocalDate.of(2026, 10, 7);
    JSONObject before = RenderState.content(data, 1, 0, "", "", date, false, expanded);
    expanded.add("meal-1");
    JSONObject opened = RenderState.content(data, 1, 0, "", "", date, false, expanded);
    assertFalse(J.equal(before, opened));
    expanded.clear();
    assertTrue(J.equal(before, RenderState.content(data, 1, 0, "", "", date, false, expanded)));
    assertFalse(J.equal(opened, RenderState.content(data, 1, 0, "", "", date, false, expanded)));
  }
}
