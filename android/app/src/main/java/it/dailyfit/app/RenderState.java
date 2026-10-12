package it.dailyfit.app;

import java.time.LocalDate;
import java.util.Set;
import java.util.TreeSet;
import org.json.*;

/** Dependencies of the visible content; timer and undo bars have their own updates. */
final class RenderState {
  static JSONObject content(
      JSONObject data,
      int area,
      int tab,
      String planID,
      String dayID,
      LocalDate date,
      boolean base,
      Set<String> expandedMeals) {
    JSONObject result = content(data, area, tab, planID, dayID, date, base);
    if (area == 1 && tab == 0) {
      J.put(result, "expandedMeals", new JSONArray(new TreeSet<>(expandedMeals)));
      J.put(result, "date", date.toString());
      J.put(result, "base", base);
    }
    return result;
  }

  static JSONObject content(
      JSONObject data,
      int area,
      int tab,
      String planID,
      String dayID,
      LocalDate date,
      boolean base) {
    if (area == 0) {
      if (tab == 1) return J.obj("exercises", J.array(data, "exercises"));
      if (tab == 2) return J.obj("notes", J.array(data, "notes"));
      JSONObject plan = J.findOrNull(J.array(data, "plans"), planID);
      if (plan == null) {
        JSONArray plans = new JSONArray();
        for (JSONObject p : J.list(J.array(data, "plans")))
          plans.put(
              J.obj(
                  "id", J.id(p), "name", p.optString("name"), "days", J.array(p, "days").length()));
        return J.obj("plans", plans);
      }
      JSONObject day = J.findOrNull(J.array(plan, "days"), dayID);
      if (day == null) {
        JSONArray days = new JSONArray();
        for (JSONObject d : J.list(J.array(plan, "days")))
          days.put(
              J.obj(
                  "id",
                  J.id(d),
                  "name",
                  d.optString("name"),
                  "entries",
                  J.array(d, "entries").length()));
        return J.obj("name", plan.optString("name"), "days", days);
      }
      JSONObject exercises = new JSONObject();
      for (JSONObject entry : J.list(J.array(day, "entries")))
        J.put(
            exercises,
            entry.optString("exerciseID"),
            Domain.exercise(data, entry.optString("exerciseID")));
      return J.obj("name", plan.optString("name"), "day", day, "exercises", exercises);
    }
    if (tab == 1) return J.obj("foods", J.array(data, "foods"));
    JSONObject day = Domain.diet(data, date, base), foods = new JSONObject();
    for (JSONObject meal : J.list(J.array(day, "meals")))
      for (JSONObject item : J.list(J.array(meal, "items")))
        if (item.isNull("snapshot"))
          J.put(foods, item.optString("foodID"), Domain.food(data, item));
    return J.obj(
        "day",
        day,
        "foods",
        foods,
        "goals",
        Domain.goals(data),
        "weight",
        data.opt("bodyWeight"),
        "custom",
        !base && J.object(data, "dates").has(date.toString()));
  }

  static JSONObject meal(JSONObject data, JSONObject meal) {
    JSONObject foods = new JSONObject();
    for (JSONObject item : J.list(J.array(meal, "items")))
      if (item.isNull("snapshot")) J.put(foods, item.optString("foodID"), Domain.food(data, item));
    return J.obj("meal", meal, "foods", foods);
  }
}
