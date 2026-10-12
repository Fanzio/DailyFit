package it.dailyfit.app;

import static org.junit.Assert.*;

import java.time.LocalDate;
import java.util.*;
import java.util.function.Consumer;
import org.json.*;
import org.junit.*;

public class IncrementalValidationTest {
  private JSONObject previous;

  @BeforeClass
  public static void seed() throws Exception {
    DomainTest.loadSeed();
  }

  @Before
  public void prepare() {
    previous = J.parse(DomainTest.seed);
    // Keep this suite focused on references and validation, without repeatedly decoding photos.
    for (JSONObject exercise : J.list(J.array(previous, "exercises"))) {
      exercise.remove("photo");
      exercise.remove("musclePhoto");
    }
    Domain.validate(previous);
  }

  private JSONObject entry(JSONObject data) {
    return J.at(J.array(J.at(J.array(J.at(J.array(data, "plans"), 0), "days"), 0), "entries"), 0);
  }

  private void rejected(JSONObject next) {
    boolean full = false, incremental = false;
    try {
      Domain.validate(next);
    } catch (IllegalArgumentException | java.time.DateTimeException error) {
      full = true;
    }
    try {
      Domain.validateChanges(next, previous);
    } catch (IllegalArgumentException | java.time.DateTimeException error) {
      incremental = true;
    }
    assertTrue("Full validation must reject fixture", full);
    assertTrue("Incremental validation must reject the same invalid change", incremental);
  }

  private void accepted(JSONObject next) {
    Domain.validate(next);
    Domain.validateChanges(next, previous);
  }

  private JSONObject withFoodPortion(boolean snapshot) {
    JSONObject food = J.at(J.array(previous, "foods"), 0);
    JSONObject item = J.obj("id", J.id(), "foodID", J.id(food), "quantity", 100);
    if (snapshot) J.put(item, "snapshot", J.copy(food));
    J.array(J.at(J.array(J.at(J.array(previous, "week"), 0), "meals"), 0), "items").put(item);
    Domain.validate(previous);
    return J.copy(previous);
  }

  @Test
  public void changedFieldsStillHaveSameRejectionsAsFullValidation() {
    List<Consumer<JSONObject>> invalid =
        Arrays.asList(
            d -> J.put(J.at(J.array(d, "exercises"), 0), "video", "javascript:alert(1)"),
            d -> J.put(J.at(J.array(d, "exercises"), 0), "photo", "broken"),
            d -> J.put(J.at(J.array(d, "foods"), 0), "unit", "ml"),
            d -> J.put(J.object(J.at(J.array(d, "foods"), 0), "nutrients"), "kcal", -1),
            d -> J.put(entry(d), "rest", 0),
            d -> J.put(J.at(J.array(entry(d), "sets"), 0), "load", -1),
            d -> J.put(entry(d), "exerciseID", J.id()),
            d -> J.array(d, "foods").put(J.copy(J.at(J.array(d, "foods"), 0))),
            d -> J.array(entry(d), "sets").put(J.copy(J.at(J.array(entry(d), "sets"), 0))),
            d -> J.put(d, "chatLink", "https://untrusted.example/c/chat"),
            d ->
                J.array(d, "notes")
                    .put(
                        J.obj("id", J.id(), "title", "x", "body", "bad\u0000text", "updatedAt", 0)),
            d -> J.put(J.object(d, "dates"), "2026-02-30", J.copy(J.at(J.array(d, "week"), 0))));
    for (Consumer<JSONObject> edit : invalid) {
      JSONObject next = J.copy(previous);
      edit.accept(next);
      rejected(next);
    }
  }

  @Test
  public void deletedExerciseRechecksUnchangedLinkedEntries() {
    JSONObject next = J.copy(previous);
    J.remove(J.array(next, "exercises"), entry(next).optString("exerciseID"));
    rejected(next);
  }

  @Test
  public void deletingExerciseAndAllItsReferencesIsAllowed() {
    JSONObject next = J.copy(previous);
    String id = entry(next).optString("exerciseID");
    J.remove(J.array(next, "exercises"), id);
    for (JSONObject plan : J.list(J.array(next, "plans")))
      for (JSONObject day : J.list(J.array(plan, "days")))
        for (JSONObject e : J.list(J.array(day, "entries")))
          if (id.equals(e.optString("exerciseID"))) J.remove(J.array(day, "entries"), J.id(e));
    accepted(next);
  }

  @Test
  public void deletedFoodRechecksUnchangedBaseMeals() {
    JSONObject next = withFoodPortion(false);
    J.remove(J.array(next, "foods"), J.id(J.at(J.array(next, "foods"), 0)));
    rejected(next);
  }

  @Test
  public void independentSnapshotSurvivesCatalogRemoval() {
    JSONObject next = withFoodPortion(true);
    J.remove(J.array(next, "foods"), J.id(J.at(J.array(next, "foods"), 0)));
    accepted(next);
  }

  @Test
  public void changedSnapshotIsValidatedEvenWhenCatalogIsUnchanged() {
    JSONObject next = withFoodPortion(true);
    JSONObject item =
        J.at(J.array(J.at(J.array(J.at(J.array(next, "week"), 0), "meals"), 0), "items"), 0);
    J.put(J.object(item, "snapshot"), "unit", "ml");
    rejected(next);
  }

  @Test
  public void weightChangeRechecksExistingGoals() {
    J.put(previous, "bodyWeight", 70);
    J.put(Domain.goals(previous), "proteinPerKg", 2);
    Domain.validate(previous);
    JSONObject next = J.copy(previous);
    J.put(next, "bodyWeight", null);
    rejected(next);
  }

  @Test
  public void repeatedValidEditsAndReordersMatchFullValidation() {
    for (int i = 0; i < 40; i++) {
      JSONObject next = J.copy(previous);
      J.put(J.at(J.array(entry(next), "sets"), 0), "load", i * 0.5);
      J.move(J.array(next, "foods"), J.id(J.at(J.array(next, "foods"), 0)), 1);
      accepted(next);
      previous = next;
    }
  }

  @Test
  public void personalizedDateChecksItsOwnChangedPortion() {
    withFoodPortion(false);
    Domain.editDiet(previous, LocalDate.of(2026, 10, 5), false, d -> {});
    Domain.validate(previous);
    JSONObject next = J.copy(previous), day = J.object(J.object(next, "dates"), "2026-10-05");
    J.put(J.at(J.array(J.at(J.array(day, "meals"), 0), "items"), 0), "quantity", -1);
    rejected(next);
  }

  @Test
  public void liveFoodDependencyIsNotHiddenBySnapshotOfSameFood() {
    withFoodPortion(false);
    JSONObject meal = J.at(J.array(J.at(J.array(previous, "week"), 0), "meals"), 0);
    JSONObject item = J.copy(J.at(J.array(meal, "items"), 0));
    J.put(item, "id", J.id());
    J.put(item, "snapshot", J.copy(Domain.food(previous, item)));
    J.array(meal, "items").put(item);
    JSONObject before =
        RenderState.content(previous, 1, 0, "", "", LocalDate.of(2026, 10, 5), true);
    JSONObject next = J.copy(previous);
    J.put(J.object(J.at(J.array(next, "foods"), 0), "nutrients"), "kcal", 1);
    assertFalse(
        J.equal(before, RenderState.content(next, 1, 0, "", "", LocalDate.of(2026, 10, 5), true)));
  }
}
