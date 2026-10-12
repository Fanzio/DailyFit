package it.dailyfit.app;

import static org.junit.Assert.*;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.time.LocalDate;
import java.util.*;
import java.util.zip.*;
import org.json.*;
import org.junit.*;

public class DomainTest {
  static String seed;
  JSONObject data;
  static final LocalDate MON = LocalDate.of(2026, 10, 5);

  @BeforeClass
  public static void loadSeed() throws Exception {
    Path root = Paths.get(System.getProperty("project.root", "."));
    Path path = root.resolve("app/src/main/assets/defaults.json");
    if (!Files.exists(path)) path = Paths.get("src/main/assets/defaults.json");
    seed = new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
  }

  @Before
  public void before() {
    data = J.parse(seed);
  }

  JSONObject firstEntry() {
    return J.at(J.array(J.at(J.array(J.at(J.array(data, "plans"), 0), "days"), 0), "entries"), 0);
  }

  JSONObject meal(JSONObject d) {
    return J.at(J.array(d, "meals"), 0);
  }

  JSONObject addFood(LocalDate date, boolean base, double quantity) {
    JSONObject food = J.at(J.array(data, "foods"), 0),
        item = J.obj("id", J.id(), "foodID", J.id(food), "quantity", quantity);
    Domain.editDiet(data, date, base, d -> J.array(meal(d), "items").put(item));
    return item;
  }

  void rejected(Runnable r) {
    try {
      r.run();
      fail("Expected rejection");
    } catch (IllegalArgumentException expected) {
    }
  }

  @Test
  public void defaultsValidate() {
    Domain.validate(data);
  }

  @Test
  public void allDefaultFoodsUseGrams() {
    for (JSONObject food : J.list(J.array(data, "foods")))
      assertEquals("g", food.optString("unit"));
  }

  @Test
  public void foodValidationRejectsVolumeUnits() {
    JSONObject food = J.copy(J.at(J.array(data, "foods"), 0));
    for (String unit : new String[] {"ml", "l", "kg", ""}) {
      J.put(food, "unit", unit);
      rejected(() -> Domain.validateFood(food));
    }
    J.put(food, "unit", "g");
    Domain.validateFood(food);
  }

  @Test
  public void volumeBackupRejectedWithoutReinterpretingSource() {
    JSONObject imported = J.copy(data);
    J.put(J.at(J.array(imported, "foods"), 0), "unit", "ml");
    byte[] bytes = J.obj("format", "DailyFit", "version", 1, "data", imported)
        .toString().getBytes(StandardCharsets.UTF_8);
    rejected(() -> Domain.restore(bytes));
    assertEquals("ml", J.at(J.array(imported, "foods"), 0).optString("unit"));
    assertEquals("g", J.at(J.array(data, "foods"), 0).optString("unit"));
  }

  @Test
  public void datedVolumeSnapshotRejected() {
    addFood(MON, true, 125);
    Domain.editDiet(data, MON, false, day -> {});
    JSONObject snapshot =
        J.object(J.at(J.array(meal(Domain.diet(data, MON, false)), "items"), 0), "snapshot");
    J.put(snapshot, "unit", "ml");
    rejected(() -> Domain.validate(data));
    assertEquals(
        125,
        J.at(J.array(meal(Domain.diet(data, MON, false)), "items"), 0).optDouble("quantity"),
        0);
  }

  @Test
  public void seedCountsMatchApprovedPlan() {
    assertEquals(15, J.array(data, "exercises").length());
    assertEquals(6, J.array(data, "foods").length());
    JSONArray days = J.array(J.at(J.array(data, "plans"), 0), "days");
    assertEquals(4, days.length());
    int count = 0, sets = 0;
    for (JSONObject d : J.list(days))
      for (JSONObject e : J.list(J.array(d, "entries"))) {
        count++;
        sets += J.array(e, "sets").length();
      }
    assertEquals(24, count);
    assertEquals(62, sets);
  }

  @Test
  public void everyExerciseHasBothImages() {
    for (JSONObject e : J.list(J.array(data, "exercises")))
      for (String k : new String[] {"photo", "musclePhoto"}) {
        byte[] b = Base64.getDecoder().decode(e.optString(k));
        assertTrue(b.length > 1000);
        assertTrue(b.length <= 2_000_000);
        assertEquals(255, b[0] & 255);
        assertEquals(216, b[1] & 255);
      }
  }

  @Test
  public void seedLoadsAndRestsAreExplicit() {
    for (JSONObject p : J.list(J.array(data, "plans")))
      for (JSONObject d : J.list(J.array(p, "days")))
        for (JSONObject e : J.list(J.array(d, "entries"))) {
          assertEquals(90, e.optInt("rest"));
          for (JSONObject s : J.list(J.array(e, "sets"))) assertEquals(0, s.optDouble("load"), 0);
        }
  }

  @Test
  public void crunchAndPlankKeepRanges() {
    boolean crunch = false, plank = false;
    for (JSONObject p : J.list(J.array(data, "plans")))
      for (JSONObject d : J.list(J.array(p, "days")))
        for (JSONObject e : J.list(J.array(d, "entries"))) {
          String name = Domain.entryName(data, e);
          JSONObject s = J.at(J.array(e, "sets"), 0);
          if (name.equals("Crunch")) {
            crunch = true;
            assertEquals("12–20", Domain.displayTarget(s));
          }
          if (name.equals("Plank")) {
            plank = true;
            assertEquals("20–40 s", Domain.displayTarget(s));
          }
        }
    assertTrue(crunch && plank);
  }

  @Test
  public void italianDecimalAccepted() {
    assertEquals(76.5, Domain.number("76,5", "Kg", 0, 2000, false), 0);
  }

  @Test
  public void invalidNumbersRejected() {
    for (String s : new String[] {"-1", "NaN", "Infinity", "1e3", "1,2.3", "", "10000000000000"})
      rejected(() -> Domain.number(s, "Numero", 0, 2000, false));
  }

  @Test
  public void emptyOptionalNumberIsNull() {
    assertNull(Domain.number(" ", "Obiettivo", 0, Double.MAX_VALUE, true));
  }

  @Test
  public void integerRejectsDecimal() {
    rejected(() -> Domain.integer("2,5", "Serie", 1, 30));
  }

  @Test
  public void targetAcceptsRange() {
    JSONObject s = Domain.newSet();
    Domain.setTarget(s, "12 – 20", "repetitions");
    assertEquals(12, s.optInt("reps"));
    assertEquals(20, s.optInt("upperReps"));
  }

  @Test
  public void rangeOrderAndLimitsEnforced() {
    for (String value : new String[] {"20-12", "0", "1000", "8-", "2-3-4", "8,5"})
      rejected(() -> Domain.setTarget(Domain.newSet(), value, "repetitions"));
  }

  @Test
  public void secondsAndRepetitionsHaveDifferentLimits() {
    JSONObject s = Domain.newSet();
    Domain.setTarget(s, "1200", "seconds");
    assertEquals("1200 s", Domain.displayTarget(s));
    rejected(() -> Domain.setTarget(s, "1200", "repetitions"));
  }

  @Test
  public void duplicationCreatesIndependentIds() {
    JSONObject p = J.at(J.array(data, "plans"), 0), copy = Domain.duplicate(p, "days");
    assertNotEquals(J.id(p), J.id(copy));
    JSONObject originalDay = J.at(J.array(p, "days"), 0), copyDay = J.at(J.array(copy, "days"), 0);
    assertNotEquals(J.id(originalDay), J.id(copyDay));
    JSONObject originalEntry = J.at(J.array(originalDay, "entries"), 0),
        entry = J.at(J.array(copyDay, "entries"), 0);
    assertNotEquals(J.id(originalEntry), J.id(entry));
    JSONObject set = J.at(J.array(entry, "sets"), 0);
    assertNotEquals(J.id(J.at(J.array(originalEntry, "sets"), 0)), J.id(set));
    J.put(set, "load", 99);
    assertEquals(0, J.at(J.array(originalEntry, "sets"), 0).optDouble("load"), 0);
  }

  @Test
  public void duplicationPreservesRangesAndAliases() {
    JSONObject p = J.at(J.array(data, "plans"), 0), c = Domain.duplicate(p, "days");
    for (int i = 0; i < 4; i++) {
      JSONArray one = J.array(J.at(J.array(p, "days"), i), "entries"),
          two = J.array(J.at(J.array(c, "days"), i), "entries");
      for (int j = 0; j < one.length(); j++) {
        JSONObject a = J.at(one, j), b = J.at(two, j);
        assertEquals(a.opt("nameOverride"), b.opt("nameOverride"));
        assertEquals(
            Domain.displayTarget(J.at(J.array(a, "sets"), 0)),
            Domain.displayTarget(J.at(J.array(b, "sets"), 0)));
      }
    }
  }

  @Test
  public void dailyEditDoesNotAffectBaseOrNextWeek() {
    JSONObject item = addFood(MON, true, 100);
    Domain.editDiet(
        data,
        MON,
        false,
        d -> J.put(J.find(J.array(meal(d), "items"), J.id(item)), "quantity", 150));
    assertEquals(
        100,
        J.at(J.array(meal(Domain.diet(data, MON, true)), "items"), 0).optDouble("quantity"),
        0);
    assertEquals(
        150,
        J.at(J.array(meal(Domain.diet(data, MON, false)), "items"), 0).optDouble("quantity"),
        0);
    assertEquals(
        100,
        J.at(J.array(meal(Domain.diet(data, MON.plusWeeks(1), false)), "items"), 0)
            .optDouble("quantity"),
        0);
  }

  @Test
  public void personalizedFoodValuesAreSnapshots() {
    addFood(MON, true, 100);
    Domain.editDiet(data, MON, false, d -> {});
    double kcal = Domain.totals(data, Domain.diet(data, MON, false))[0];
    J.put(J.object(J.at(J.array(data, "foods"), 0), "nutrients"), "kcal", 1);
    assertEquals(kcal, Domain.totals(data, Domain.diet(data, MON, false))[0], 0);
    assertEquals(1, Domain.totals(data, Domain.diet(data, MON, true))[0], 0);
  }

  @Test
  public void replacingBasePortionInDateStillCreatesSnapshot() {
    JSONObject original = addFood(MON, true, 100), edited = J.copy(original);
    J.put(edited, "quantity", 150);
    Domain.editDiet(data, MON, false, d -> J.replace(J.array(meal(d), "items"), edited));
    J.put(J.object(J.at(J.array(data, "foods"), 0), "nutrients"), "kcal", 1);
    assertEquals(550.5, Domain.totals(data, Domain.diet(data, MON, false))[0], 0);
  }

  @Test
  public void deletingFoodKeepsExistingMeals() {
    addFood(MON, true, 100);
    String id = J.id(J.at(J.array(data, "foods"), 0));
    double before = Domain.totals(data, Domain.diet(data, MON, true))[0];
    Domain.deleteFood(data, id);
    Domain.validate(data);
    assertEquals(before, Domain.totals(data, Domain.diet(data, MON, true))[0], 0);
    assertTrue(J.find(J.array(data, "foods"), id).optBoolean("archived"));
  }

  @Test
  public void deletingExerciseArchivesButKeepsPlan() {
    String id = firstEntry().optString("exerciseID");
    J.put(Domain.exercise(data, id), "archived", true);
    Domain.validate(data);
    assertEquals("Panca piana bilanciere", Domain.entryName(data, firstEntry()));
  }

  @Test
  public void foodQuantitiesScaleAllNutrients() {
    addFood(MON, true, 150);
    double[] n = Domain.totals(data, Domain.diet(data, MON, true));
    assertArrayEquals(new double[] {550.5, 12, 11.25, 100.2}, n, 0.00001);
  }

  @Test
  public void goalsAreIndependentOfAtwater() {
    JSONObject g = J.obj("kcal", 100, "proteinPerKg", 2, "fatPerKg", 2, "carbsPerKg", 2);
    Domain.setGoals(data, g, 70.0);
    Domain.validate(data);
    assertArrayEquals(new Double[] {100.0, 140.0, 140.0, 140.0}, Domain.targets(g, 70.0));
  }

  @Test
  public void weightRequiredForRatios() {
    rejected(() -> Domain.targets(J.obj("proteinPerKg", 2), null));
  }

  @Test
  public void goalsCanBeEmptyOrZero() {
    assertNull(Domain.targets(new JSONObject(), null)[0]);
    assertEquals(0, Domain.targets(J.obj("kcal", 0), null)[0], 0);
  }

  @Test
  public void goalsApplyToAllSevenBaseDays() {
    JSONObject g = J.obj("kcal", 2100, "proteinPerKg", 2, "fatPerKg", 0.8, "carbsPerKg", 3);
    Domain.setGoals(data, g, 70.0);
    for (JSONObject day : J.list(J.array(data, "week")))
      assertEquals(2100, J.object(day, "goals").optDouble("kcal"), 0);
  }

  @Test
  public void invalidWeightsAndRatiosRejected() {
    for (double w : new double[] {0, -1, 501, Double.NaN})
      rejected(() -> Domain.targets(new JSONObject(), w));
    rejected(() -> Domain.targets(J.obj("proteinPerKg", -1), 70.0));
  }

  @Test
  public void copyDietDoesNotCopyGoals() {
    Domain.setGoals(data, J.obj("kcal", 2100, "carbsPerKg", null), null);
    addFood(MON, true, 100);
    JSONObject source = J.copy(Domain.diet(data, MON, true));
    J.put(J.object(source, "goals"), "kcal", 999);
    Domain.copyMeals(data, source, MON.plusDays(1), true);
    assertEquals(
        2100, J.object(Domain.diet(data, MON.plusDays(1), true), "goals").optDouble("kcal"), 0);
  }

  @Test
  public void copiedMealsUseNewIds() {
    addFood(MON, true, 100);
    JSONObject source = Domain.diet(data, MON, true);
    Domain.copyMeals(data, source, MON.plusDays(1), true);
    JSONObject dest = Domain.diet(data, MON.plusDays(1), true);
    assertNotEquals(J.id(meal(source)), J.id(meal(dest)));
    assertNotEquals(
        J.id(J.at(J.array(meal(source), "items"), 0)), J.id(J.at(J.array(meal(dest), "items"), 0)));
  }

  @Test
  public void copyToDateFreezesFood() {
    addFood(MON, true, 100);
    Domain.copyMeals(data, Domain.diet(data, MON, true), MON.plusDays(1), false);
    assertNotNull(
        J.at(J.array(meal(Domain.diet(data, MON.plusDays(1), false)), "items"), 0)
            .optJSONObject("snapshot"));
  }

  @Test
  public void shoppingExcludesDateOverrides() {
    addFood(MON, true, 100);
    Domain.editDiet(
        data, MON, false, d -> J.put(J.at(J.array(meal(d), "items"), 0), "quantity", 500));
    assertEquals(100, Domain.shopping(data, false).get(0).optDouble("quantity"), 0);
  }

  @Test
  public void shoppingSumsSameFoodAcrossDays() {
    addFood(MON, true, 100);
    addFood(MON.plusDays(1), true, 70);
    assertEquals(170, Domain.shopping(data, false).get(0).optDouble("quantity"), 0);
  }

  @Test
  public void shoppingDoesNotMergeDifferentIdsWithSameName() {
    JSONObject old = J.at(J.array(data, "foods"), 0), copy = J.copy(old);
    J.put(copy, "id", J.id());
    J.array(data, "foods").put(copy);
    addFood(MON, true, 100);
    J.array(meal(Domain.diet(data, MON, true)), "items")
        .put(J.obj("id", J.id(), "foodID", J.id(copy), "quantity", 50));
    assertEquals(2, Domain.shopping(data, false).size());
  }

  @Test
  public void baseVolumeSnapshotRejected() {
    JSONObject item = addFood(MON, true, 100), snapshot = J.copy(Domain.food(data, item));
    J.put(snapshot, "unit", "ml");
    J.array(meal(Domain.diet(data, MON, true)), "items")
        .put(J.obj("id", J.id(), "foodID", J.id(snapshot), "quantity", 50, "snapshot", snapshot));
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void shoppingGroupsSnacks() {
    JSONObject f = J.at(J.array(data, "foods"), 0);
    J.array(Domain.diet(data, MON, true), "meals")
        .put(
            J.obj(
                "id",
                J.id(),
                "name",
                "Merenda",
                "isSnack",
                true,
                "items",
                new JSONArray().put(J.obj("id", J.id(), "foodID", J.id(f), "quantity", 20))));
    assertEquals("Spuntini", Domain.shopping(data, true).get(0).optString("group"));
  }

  @Test
  public void reorderingPreservesItemsAndTotals() {
    addFood(MON, true, 100);
    addFood(MON, true, 50);
    JSONObject d = Domain.diet(data, MON, true);
    JSONArray items = J.array(meal(d), "items");
    String id = J.id(J.at(items, 0));
    double[] before = Domain.totals(data, d);
    J.move(items, id, 1);
    assertEquals(id, J.id(J.at(items, 1)));
    assertArrayEquals(before, Domain.totals(data, d), 0);
  }

  @Test
  public void timerUsesMonotonicClockDuringSameBoot() {
    assertEquals(80, Countdown.remaining(true, 100000, 900000, 5, 5, 0, 20000, 99999999));
  }

  @Test
  public void timerPauseKeepsValue() {
    assertEquals(41, Countdown.remaining(false, 0, 0, 1, 1, 41, 999999, 999999));
  }

  @Test
  public void timerAfterRebootUsesWallClock() {
    assertEquals(45, Countdown.remaining(true, 999999, 100000, 1, 2, 0, 0, 55000));
  }

  @Test
  public void timerClampsExpiredAndLargeValues() {
    assertEquals(0, Countdown.remaining(true, 500, 0, 1, 1, 0, 600, 0));
    assertEquals(3600, Countdown.remaining(true, 99999999, 0, 1, 1, 0, 0, 0));
  }

  @Test
  public void timerRoundsUpFractionalSecond() {
    assertEquals(1, Countdown.remaining(true, 1001, 0, 1, 1, 0, 1000, 0));
  }

  @Test
  public void backupRoundTripPreservesPhotosAndSets() {
    JSONObject restored = Domain.restore(Domain.backup(data));
    assertEquals(
        J.at(J.array(data, "exercises"), 0).optString("photo"),
        J.at(J.array(restored, "exercises"), 0).optString("photo"));
    assertEquals(J.array(data, "plans").toString(), J.array(restored, "plans").toString());
  }

  @Test
  public void backupDoesNotRestoreTimer() {
    J.put(data, "timer", J.obj("name", "old"));
    assertFalse(Domain.restore(Domain.backup(data)).has("timer"));
  }

  @Test
  public void backupPreservesDeletedDefaults() {
    J.put(data, "plans", new JSONArray());
    JSONObject restored = Domain.restore(Domain.backup(data));
    assertEquals(0, J.array(restored, "plans").length());
    assertEquals(1, restored.optInt("defaultContentVersion"));
  }

  @Test
  public void wrongBackupFormatRejected() {
    rejected(
        () ->
            Domain.restore(
                "{\"format\":\"Other\",\"version\":1}".getBytes(StandardCharsets.UTF_8)));
  }

  @Test
  public void deeplyNestedJsonRejectedBeforeParsing() {
    StringBuilder s = new StringBuilder();
    for (int i = 0; i < 100; i++) s.append("{\"a\":");
    s.append("0");
    for (int i = 0; i < 100; i++) s.append("}");
    rejected(() -> J.parse(s.toString()));
  }

  @Test
  public void trailingDataRejectedButBracesInsideTextAllowed() {
    rejected(() -> J.parse("{} garbage"));
    assertEquals("{{[[\\", J.parse("{\"text\":\"{{[[\\\\\"}").optString("text"));
  }

  @Test
  public void unsupportedSchemaRejected() {
    J.put(data, "schemaVersion", 50);
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void duplicateIdsRejected() {
    J.array(data, "foods").put(J.copy(J.at(J.array(data, "foods"), 0)));
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void missingExerciseReferenceRejected() {
    J.put(firstEntry(), "exerciseID", J.id());
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void inconsistentFoodSnapshotRejected() {
    JSONObject item = addFood(MON, true, 100), snapshot = J.copy(Domain.food(data, item));
    J.put(snapshot, "id", J.id());
    J.put(item, "snapshot", snapshot);
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void invalidQuantityRejected() {
    J.put(addFood(MON, true, 100), "quantity", -1);
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void invalidDateRejected() {
    J.put(J.object(data, "dates"), "2026-02-30", J.copy(Domain.diet(data, MON, true)));
    try {
      Domain.validate(data);
      fail();
    } catch (RuntimeException expected) {
    }
  }

  @Test
  public void dateAcrossYearKeepsMondayIndex() {
    assertEquals(Domain.diet(data, LocalDate.of(2027, 1, 4), true), J.at(J.array(data, "week"), 0));
  }

  @Test
  public void removingMainMealRejected() {
    J.array(Domain.diet(data, MON, true), "meals").remove(0);
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void chatAllowsOnlyPrivateChatOrHome() {
    assertEquals("https://chatgpt.com/", Domain.web("", true));
    assertEquals(
        "https://chatgpt.com/c/abc-123", Domain.web("https://chatgpt.com/c/abc-123", true));
    for (String s :
        new String[] {
          "https://chatgpt.com.evil.org/",
          "https://chatgpt.com/share/abc",
          "http://chatgpt.com/",
          "https://user@chatgpt.com/",
          "https://chatgpt.com/?x=1",
          "javascript:alert(1)"
        }) rejected(() -> Domain.web(s, true));
  }

  @Test
  public void externalLinksRejectExecutableSchemes() {
    for (String s :
        new String[] {
          "file:///secret", "content://private", "javascript:x", "https://user:pw@example.org"
        }) rejected(() -> Domain.web(s, false));
    assertEquals("https://example.org/video", Domain.web("https://example.org/video", false));
  }

  @Test
  public void noteTooLongRejected() {
    JSONObject note = J.at(J.array(data, "notes"), 0);
    char[] chars = new char[121];
    Arrays.fill(chars, 'a');
    J.put(note, "title", new String(chars));
    rejected(() -> Domain.validate(data));
  }

  @Test
  public void excelContainsElevenValidSheets() throws Exception {
    byte[] bytes = ExcelExport.encode(data);
    int sheets = 0;
    try (ZipInputStream in = new ZipInputStream(new ByteArrayInputStream(bytes))) {
      ZipEntry e;
      while ((e = in.getNextEntry()) != null) {
        if (e.getName().startsWith("xl/worksheets/sheet")) sheets++;
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] block = new byte[8192];
        int n;
        while ((n = in.read(block)) != -1) b.write(block, 0, n);
        javax.xml.parsers.DocumentBuilderFactory.newInstance()
            .newDocumentBuilder()
            .parse(new ByteArrayInputStream(b.toByteArray()));
      }
    }
    assertEquals(11, sheets);
  }

  @Test
  public void excelTreatsFormulaLikeNamesAsText() throws Exception {
    J.put(J.at(J.array(data, "notes"), 0), "title", "=HYPERLINK(\"evil\")");
    String all = new String(ExcelExport.encode(data), StandardCharsets.ISO_8859_1);
    assertTrue(all.length() > 100);
    String xml = ExcelExport.xml("=HYPERLINK(\"evil\")");
    assertEquals("=HYPERLINK(&quot;evil&quot;)", xml);
    for (ExcelExport.Sheet s : ExcelExport.sheets(data))
      for (Object[] row : s.rows) assertEquals(s.rows.get(0).length, row.length);
  }

  @Test
  public void longUnicodeNotesReassembleWithoutLoss() {
    StringBuilder b = new StringBuilder();
    for (int i = 0; i < 5000; i++) b.append("🏋️ àè\n");
    String text = b.toString();
    assertEquals(text, String.join("", ExcelExport.chunks(text)));
    for (String chunk : ExcelExport.chunks(text)) assertTrue(chunk.length() <= 1000);
  }

  @Test
  public void exportSmokeArtifact() throws Exception {
    String output = System.getProperty("export.output");
    if (output == null) return;
    Path dir = Paths.get(output);
    Files.createDirectories(dir);
    addFood(MON, true, 150);
    Domain.setGoals(
        data, J.obj("kcal", 100, "proteinPerKg", 2, "fatPerKg", 0.8, "carbsPerKg", 3), 70.0);
    JSONObject note = J.at(J.array(data, "notes"), 0);
    J.put(note, "title", "=1+1");
    J.put(note, "body", "Test <>& \" e 🏋️");
    Files.write(dir.resolve("export-smoke.xlsx"), ExcelExport.encode(data));
    Files.write(dir.resolve("backup-smoke.json"), Domain.backup(data));
  }
}
