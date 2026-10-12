package it.dailyfit.app;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.LocalDate;
import java.util.*;
import java.util.function.Consumer;
import org.json.JSONArray;
import org.json.JSONObject;

/** Platform-independent rules. JSON keys also match the current iPhone backup format. */
public final class Domain {
  public static final int MAX_BYTES = 64_000_000;
  public static final String[] DAYS = {
    "Lunedì", "Martedì", "Mercoledì", "Giovedì", "Venerdì", "Sabato", "Domenica"
  };
  public static final String[] GROUPS = {
    "Petto",
    "Dorso",
    "Spalle",
    "Bicipiti",
    "Tricipiti",
    "Quadricipiti",
    "Femorali",
    "Glutei",
    "Polpacci",
    "Addominali",
    "Full body",
    "Altro"
  };
  public static final String[] MACROS = {"kcal", "protein", "fat", "carbs"};

  private Domain() {}

  public static void require(boolean ok, String text) {
    if (!ok) throw new IllegalArgumentException(text);
  }

  public static String text(String v, String label, int max, boolean required) {
    String s = v.trim();
    require(
        (!required || !s.isEmpty()) && s.length() <= max,
        label + ": massimo " + max + " caratteri.");
    require(s.indexOf('\u0000') < 0, label + ": carattere non valido.");
    return s;
  }

  public static Double number(String v, String label, double min, double max, boolean optional) {
    String s = v.trim();
    if (optional && s.isEmpty()) return null;
    require(
        s.length() <= 12 && s.matches("[0-9]+(?:[.,][0-9]+)?"),
        label + ": inserisci un numero valido.");
    double n = Double.parseDouble(s.replace(',', '.'));
    require(Double.isFinite(n) && n >= min && n <= max, label + ": valore fuori intervallo.");
    return n;
  }

  public static int integer(String s, String label, int min, int max) {
    Double n = number(s, label, min, max, false);
    require(n == Math.rint(n), label + ": usa un intero.");
    return n.intValue();
  }

  public static String web(String value, boolean chat) {
    String s = value.trim();
    if (s.isEmpty()) return chat ? "https://chatgpt.com/" : "";
    try {
      URI u = new URI(s);
      require(
          s.length() <= 2048
              && ("https".equalsIgnoreCase(u.getScheme()) || "http".equalsIgnoreCase(u.getScheme()))
              && u.getHost() != null
              && u.getUserInfo() == null,
          "Usa un indirizzo completo http:// o https://.");
      if (chat)
        require(
            "https".equals(u.getScheme())
                && "chatgpt.com".equals(u.getHost())
                && u.getPort() == -1
                && u.getQuery() == null
                && u.getFragment() == null
                && (u.getPath().isEmpty()
                    || u.getPath().equals("/")
                    || u.getPath().matches("/c/[A-Za-z0-9-]+/?")),
            "Usa https://chatgpt.com/ oppure l’indirizzo privato /c/ della chat.");
      return s;
    } catch (java.net.URISyntaxException e) {
      throw new IllegalArgumentException("Collegamento non valido.");
    }
  }

  public static JSONObject newSet() {
    return J.obj("id", J.id(), "reps", 10, "load", 0);
  }

  public static JSONObject newEntry(String exerciseID) {
    return J.obj(
        "id",
        J.id(),
        "exerciseID",
        exerciseID,
        "rest",
        90,
        "sets",
        new JSONArray().put(newSet()).put(newSet()).put(newSet()));
  }

  public static void setTarget(JSONObject set, String value, String unit) {
    String s = value.trim().replace('–', '-').replace('—', '-');
    require(
        s.length() <= 25 && s.matches("[0-9]+(?:\\s*-\\s*[0-9]+)?"),
        "Usa un intero o un intervallo, per esempio 12–20.");
    String[] p = s.split("-");
    int max = unit.equals("seconds") ? 3600 : 999;
    int lo = integer(p[0].trim(), "Serie", 1, max);
    J.put(set, "reps", lo);
    J.put(set, "unit", unit);
    J.put(set, "upperReps", p.length == 2 ? integer(p[1].trim(), "Massimo", lo, max) : null);
  }

  public static String target(JSONObject s) {
    return s.optInt("reps") + (s.isNull("upperReps") ? "" : "–" + s.optInt("upperReps"));
  }

  public static String displayTarget(JSONObject s) {
    return target(s) + (s.optString("unit").equals("seconds") ? " s" : "");
  }

  public static String entryName(JSONObject data, JSONObject entry) {
    return entry.isNull("nameOverride")
        ? exercise(data, entry.optString("exerciseID")).optString("name")
        : entry.optString("nameOverride");
  }

  public static JSONObject exercise(JSONObject data, String id) {
    return J.find(J.array(data, "exercises"), id);
  }

  public static JSONObject plan(JSONObject data, String id) {
    return J.find(J.array(data, "plans"), id);
  }

  public static JSONObject day(JSONObject data, String p, String id) {
    return J.find(J.array(plan(data, p), "days"), id);
  }

  public static JSONObject food(JSONObject data, JSONObject item) {
    return item.optJSONObject("snapshot") != null
        ? J.object(item, "snapshot")
        : J.find(J.array(data, "foods"), item.optString("foodID"));
  }

  public static JSONObject duplicate(JSONObject source, String childKey) {
    JSONObject c = J.copy(source);
    J.put(c, "id", J.id());
    if (childKey != null) {
      JSONArray children = J.array(c, childKey);
      String next =
          childKey.equals("days") ? "entries" : childKey.equals("entries") ? "sets" : null;
      JSONArray out = new JSONArray();
      for (JSONObject child : J.list(children)) out.put(duplicate(child, next));
      J.put(c, childKey, out);
    }
    return c;
  }

  public static JSONObject diet(JSONObject data, LocalDate date, boolean base) {
    JSONObject special = J.object(data, "dates").optJSONObject(date.toString());
    return !base && special != null
        ? special
        : J.at(J.array(data, "week"), date.getDayOfWeek().getValue() - 1);
  }

  public static void editDiet(
      JSONObject data, LocalDate date, boolean base, Consumer<JSONObject> edit) {
    if (base) {
      edit.accept(diet(data, date, true));
      return;
    }
    JSONObject dates = J.object(data, "dates"), day = dates.optJSONObject(date.toString());
    if (day == null) {
      day = J.copy(diet(data, date, true));
      J.put(day, "weight", data.opt("bodyWeight"));
      for (JSONObject m : J.list(J.array(day, "meals")))
        for (JSONObject i : J.list(J.array(m, "items")))
          J.put(i, "snapshot", J.copy(food(data, i)));
      J.put(dates, date.toString(), day);
    }
    edit.accept(day);
    // Also freeze newly added/replaced portions, not only the initial copy of the base.
    for (JSONObject m : J.list(J.array(day, "meals")))
      for (JSONObject i : J.list(J.array(m, "items")))
        if (i.isNull("snapshot")) J.put(i, "snapshot", J.copy(food(data, i)));
  }

  public static JSONObject goals(JSONObject data) {
    return J.object(J.at(J.array(data, "week"), 0), "goals");
  }

  public static void setGoals(JSONObject data, JSONObject goals, Double weight) {
    targets(goals, weight);
    J.put(data, "bodyWeight", weight);
    for (JSONObject day : J.list(J.array(data, "week"))) J.put(day, "goals", J.copy(goals));
  }

  public static Double[] targets(JSONObject goals, Double weight) {
    Double[] values = {
      optional(goals, "kcal"),
      optional(goals, "proteinPerKg"),
      optional(goals, "fatPerKg"),
      optional(goals, "carbsPerKg")
    };
    if (weight != null)
      require(Double.isFinite(weight) && weight > 0 && weight <= 500, "Peso corporeo non valido.");
    for (int i = 0; i < 4; i++)
      if (values[i] != null) {
        require(
            Double.isFinite(values[i]) && values[i] >= 0,
            "Gli obiettivi devono essere numeri non negativi.");
        if (i > 0) {
          require(weight != null, "Inserisci il peso per i rapporti g/kg.");
          values[i] *= weight;
          require(Double.isFinite(values[i]), "Obiettivi troppo grandi.");
        }
      }
    return values;
  }

  public static Double optional(JSONObject o, String k) {
    if (o.isNull(k)) return null;
    Object v = o.opt(k);
    require(v instanceof Number, "Numero non valido: " + k);
    return ((Number) v).doubleValue();
  }

  public static double[] totals(JSONObject data, JSONObject day) {
    double[] out = new double[4];
    for (JSONObject meal : J.list(J.array(day, "meals")))
      for (JSONObject item : J.list(J.array(meal, "items"))) {
        JSONObject n = J.object(food(data, item), "nutrients");
        double factor = item.optDouble("quantity") / 100;
        for (int i = 0; i < 4; i++) out[i] += n.optDouble(MACROS[i]) * factor;
      }
    return out;
  }

  public static JSONArray copyItems(JSONObject data, JSONArray source, boolean base) {
    JSONArray items = new JSONArray();
    for (JSONObject i : J.list(source)) {
      JSONObject n = J.copy(i);
      J.put(n, "id", J.id());
      if (!base) J.put(n, "snapshot", J.copy(food(data, i)));
      items.put(n);
    }
    return items;
  }

  public static void copyMeals(JSONObject data, JSONObject source, LocalDate date, boolean base) {
    JSONArray meals = new JSONArray();
    for (JSONObject m : J.list(J.array(source, "meals"))) {
      JSONObject n = J.copy(m);
      J.put(n, "id", J.id());
      J.put(n, "items", copyItems(data, J.array(m, "items"), base));
      meals.put(n);
    }
    editDiet(data, date, base, d -> J.put(d, "meals", meals));
  }

  public static void deleteFood(JSONObject data, String id) {
    JSONObject old = J.find(J.array(data, "foods"), id);
    List<JSONObject> diets = J.list(J.array(data, "week"));
    JSONObject dates = J.object(data, "dates");
    for (String key : keys(dates)) diets.add(J.object(dates, key));
    for (JSONObject d : diets)
      for (JSONObject m : J.list(J.array(d, "meals")))
        for (JSONObject i : J.list(J.array(m, "items")))
          if (id.equals(i.optString("foodID")) && i.isNull("snapshot"))
            J.put(i, "snapshot", J.copy(old));
    J.put(old, "archived", true);
  }

  public static List<String> keys(JSONObject o) {
    List<String> r = new ArrayList<>();
    Iterator<String> i = o.keys();
    while (i.hasNext()) r.add(i.next());
    Collections.sort(r);
    return r;
  }

  public static String shoppingGroup(JSONObject meal) {
    return meal.optBoolean("isSnack") ? "Spuntini" : meal.optString("name");
  }

  /** Identity and unit are part of the key: equal names do not merge unrelated foods. */
  public static List<JSONObject> shopping(JSONObject data, boolean grouped) {
    Map<String, JSONObject> sums = new TreeMap<>();
    for (JSONObject day : J.list(J.array(data, "week")))
      for (JSONObject meal : J.list(J.array(day, "meals")))
        for (JSONObject item : J.list(J.array(meal, "items"))) {
          JSONObject food = food(data, item);
          String group = grouped ? shoppingGroup(meal) : "Totale settimana",
              unit = food.optString("unit");
          String key = group + "/" + J.id(food) + "/" + unit;
          JSONObject sum = sums.get(key);
          if (sum == null) {
            sum =
                J.obj(
                    "group",
                    group,
                    "name",
                    food.optString("name"),
                    "unit",
                    unit,
                    "quantity",
                    0,
                    "foodID",
                    J.id(food));
            sums.put(key, sum);
          }
          J.put(sum, "quantity", sum.optDouble("quantity") + item.optDouble("quantity"));
        }
    List<JSONObject> out = new ArrayList<>(sums.values());
    out.sort(
        Comparator.comparing((JSONObject o) -> o.optString("group"))
            .thenComparing(o -> o.optString("name")));
    return out;
  }

  public static double swiftNow() {
    return System.currentTimeMillis() / 1000.0 - 978307200;
  }

  private static void requireEmbeddedImages(JSONObject data) {
    for (JSONObject exercise : J.list(J.array(data, "exercises")))
      for (String field : new String[] {"photo", "musclePhoto"})
        require(
            !ImageArchive.isReference(exercise.optString(field, "")),
            "Il backup deve contenere le immagini, non percorsi locali.");
  }

  public static byte[] backup(JSONObject data) {
    requireEmbeddedImages(data);
    validate(data);
    JSONObject copy = J.copy(data);
    copy.remove("timer");
    byte[] bytes =
        J.obj("format", "DailyFit", "version", 1, "exportedAt", swiftNow(), "data", copy)
            .toString()
            .getBytes(StandardCharsets.UTF_8);
    require(bytes.length <= MAX_BYTES, "Backup troppo grande.");
    return bytes;
  }

  public static JSONObject restore(byte[] bytes) {
    require(bytes.length > 0 && bytes.length <= MAX_BYTES, "Dimensione del backup non valida.");
    JSONObject env = J.parse(new String(bytes, StandardCharsets.UTF_8));
    require(
        env.optString("format").equals("DailyFit") && env.optInt("version") == 1,
        "Backup non compatibile.");
    JSONObject data = J.copy(J.object(env, "data"));
    data.remove("timer");
    J.put(data, "defaultContentVersion", 1);
    requireEmbeddedImages(data);
    validate(data);
    return data;
  }

  public static void validate(JSONObject data) {
    validateChanges(data, null);
  }

  /** Previous is a validated, immutable live snapshot, never an untrusted import. */
  static void validateChanges(JSONObject data, JSONObject previous) {
    require(data.optInt("schemaVersion") == 1, "Versione dell’archivio non compatibile.");
    JSONArray ex = J.array(data, "exercises"),
        foods = J.array(data, "foods"),
        plans = J.array(data, "plans"),
        notes = J.array(data, "notes"),
        week = J.array(data, "week");
    bounded(ex, 5000);
    bounded(foods, 10000);
    bounded(plans, 1000);
    bounded(notes, 10000);
    require(week.length() == 7, "Servono sette giorni base.");
    unique(ex);
    unique(foods);
    unique(plans);
    unique(notes);
    Set<String> exerciseIDs = new HashSet<>(), foodIDs = new HashSet<>();
    Map<String, JSONObject> previousExercises = index(previous, "exercises");
    Map<String, JSONObject> previousFoods = index(previous, "foods");
    Map<String, JSONObject> previousPlans = index(previous, "plans");
    Map<String, JSONObject> previousNotes = index(previous, "notes");
    for (JSONObject e : J.list(ex)) {
      JSONObject old = previousExercises.get(J.id(e));
      if (!J.equal(e, old)) validateExercise(e, old);
      exerciseIDs.add(J.id(e));
    }
    for (JSONObject f : J.list(foods)) {
      if (!J.equal(f, previousFoods.get(J.id(f)))) validateFood(f);
      foodIDs.add(J.id(f));
    }
    boolean exerciseReferencesChanged = !exerciseIDs.equals(previousExercises.keySet());
    boolean foodReferencesChanged = !foodIDs.equals(previousFoods.keySet());
    for (JSONObject p : J.list(plans)) {
      JSONObject oldPlan = previousPlans.get(J.id(p));
      if (!exerciseReferencesChanged && J.equal(p, oldPlan)) continue;
      named(p, 80);
      JSONArray days = J.array(p, "days");
      bounded(days, 1000);
      unique(days);
      Map<String, JSONObject> oldDays = index(oldPlan, "days");
      for (JSONObject d : J.list(days)) {
        JSONObject oldDay = oldDays.get(J.id(d));
        if (!exerciseReferencesChanged && J.equal(d, oldDay)) continue;
        named(d, 80);
        JSONArray entries = J.array(d, "entries");
        bounded(entries, 1000);
        unique(entries);
        Map<String, JSONObject> oldEntries = index(oldDay, "entries");
        for (JSONObject e : J.list(entries)) {
          if (!exerciseReferencesChanged && J.equal(e, oldEntries.get(J.id(e)))) continue;
          require(exerciseIDs.contains(e.optString("exerciseID")), "Esercizio collegato mancante.");
          range(e, "rest", 1, 3600, true);
          if (!e.isNull("nameOverride"))
            text(string(e, "nameOverride"), "Nome nella giornata", 80, true);
          JSONArray sets = J.array(e, "sets");
          require(sets.length() > 0 && sets.length() <= 30, "Servono da 1 a 30 serie.");
          unique(sets);
          for (JSONObject s : J.list(sets)) {
            String unit = s.isNull("unit") ? "repetitions" : s.optString("unit");
            require(unit.equals("repetitions") || unit.equals("seconds"), "Unità non valida.");
            int max = unit.equals("seconds") ? 3600 : 999;
            range(s, "reps", 1, max, true);
            range(s, "load", 0, 2000, false);
            if (!s.isNull("upperReps")) range(s, "upperReps", s.optDouble("reps"), max, true);
          }
        }
      }
    }
    for (JSONObject n : J.list(notes)) {
      if (J.equal(n, previousNotes.get(J.id(n)))) continue;
      text(string(n, "title"), "Titolo", 120, false);
      text(string(n, "body"), "Nota", 200000, false);
      require(Double.isFinite(n.optDouble("updatedAt")), "Data della nota non valida.");
    }
    Double weight = optional(data, "bodyWeight");
    if (previous == null
        || !J.equal(goals(data), goals(previous))
        || !Objects.equals(data.opt("bodyWeight"), previous.opt("bodyWeight")))
      targets(goals(data), weight);
    for (int i = 0; i < week.length(); i++) {
      JSONObject day = J.at(week, i);
      if (previous == null
          || foodReferencesChanged
          || !J.equal(day, J.at(J.array(previous, "week"), i))) validateDiet(day, foodIDs);
    }
    JSONObject dates = J.object(data, "dates");
    require(dates.length() <= 50000, "Troppe giornate personalizzate.");
    for (String key : keys(dates)) {
      JSONObject day = J.object(dates, key);
      if (previous != null
          && !foodReferencesChanged
          && J.equal(day, J.object(previous, "dates").optJSONObject(key))) continue;
      require(key.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}"), "Data non valida.");
      LocalDate.parse(key);
      validateDiet(day, foodIDs);
    }
    if (previous == null || !Objects.equals(data.opt("chatLink"), previous.opt("chatLink")))
      web(string(data, "chatLink"), true);
  }

  private static Map<String, JSONObject> index(JSONObject parent, String field) {
    Map<String, JSONObject> result = new HashMap<>();
    if (parent != null)
      for (JSONObject value : J.list(J.array(parent, field))) result.put(J.id(value), value);
    return result;
  }

  public static void validateExercise(JSONObject e) {
    validateExercise(e, null);
  }

  private static void validateExercise(JSONObject e, JSONObject previous) {
    named(e, 80);
    require(Arrays.asList(GROUPS).contains(string(e, "muscle")), "Gruppo muscolare non valido.");
    text(string(e, "execution"), "Esecuzione", 3000, false);
    web(string(e, "video"), false);
    if (previous == null || e.opt("photo") != previous.opt("photo")) image(e, "photo");
    if (previous == null || e.opt("musclePhoto") != previous.opt("musclePhoto"))
      image(e, "musclePhoto");
  }

  public static void validateFood(JSONObject f) {
    named(f, 100);
    require(
        f.optString("unit").equals("g"),
        "Usa solo grammi: i valori nutrizionali devono riferirsi a 100 g. Un archivio in ml"
            + " richiede una conversione esplicita.");
    JSONObject n = J.object(f, "nutrients");
    for (String key : MACROS) range(n, key, 0, 10000, false);
    text(string(f, "source"), "Fonte", 300, false);
    web(string(f, "sourceURL"), false);
  }

  private static void validateDiet(JSONObject d, Set<String> foods) {
    JSONArray meals = J.array(d, "meals");
    require(meals.length() >= 3 && meals.length() <= 100, "Pasti non validi.");
    unique(meals);
    Set<String> main = new HashSet<>();
    for (JSONObject m : J.list(meals)) {
      named(m, 80);
      if (!m.optBoolean("isSnack")) main.add(m.optString("name"));
      JSONArray items = J.array(m, "items");
      bounded(items, 5000);
      unique(items);
      for (JSONObject i : J.list(items)) {
        range(i, "quantity", 0.000001, 100000, false);
        String id = i.optString("foodID");
        JSONObject snapshot = i.optJSONObject("snapshot");
        require(snapshot != null || foods.contains(id), "Alimento collegato mancante.");
        if (snapshot != null) {
          require(J.id(snapshot).equals(id), "Copia dell’alimento non coerente.");
          validateFood(snapshot);
        }
      }
    }
    require(
        main.containsAll(Arrays.asList("Colazione", "Pranzo", "Cena")),
        "Mancano i tre pasti principali.");
  }

  private static void image(JSONObject o, String key) {
    if (o.isNull(key)) return;
    String s = string(o, key);
    if (ImageArchive.isReference(s)) {
      ImageArchive.checkName(s.substring(ImageArchive.LOCAL.length()));
      return;
    }
    require(s.length() <= 2_666_668, "Immagine troppo grande.");
    byte[] bytes;
    try {
      bytes = Base64.getDecoder().decode(s);
    } catch (Exception e) {
      throw new IllegalArgumentException("Immagine non valida.");
    }
    require(bytes.length > 0 && bytes.length <= 2_000_000, "Dimensione immagine non valida.");
    boolean jpeg = bytes.length > 3 && (bytes[0] & 255) == 255 && (bytes[1] & 255) == 216;
    boolean png =
        bytes.length > 8
            && (bytes[0] & 255) == 137
            && bytes[1] == 80
            && bytes[2] == 78
            && bytes[3] == 71;
    require(jpeg || png, "Formato immagine non valido: usa JPEG o PNG.");
  }

  private static String string(JSONObject o, String k) {
    require(o.opt(k) instanceof String, "Testo mancante: " + k);
    return o.optString(k);
  }

  private static void named(JSONObject o, int max) {
    text(string(o, "name"), "Nome", max, true);
  }

  private static void bounded(JSONArray a, int max) {
    require(a.length() <= max, "Archivio troppo grande.");
  }

  private static void unique(JSONArray a) {
    Set<String> ids = new HashSet<>();
    for (JSONObject o : J.list(a)) {
      String id = J.id(o);
      require(
          id.matches("[0-9A-Fa-f]{8}(-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}") && ids.add(id),
          "Identificativi duplicati o non validi.");
    }
  }

  private static void range(JSONObject o, String k, double min, double max, boolean integral) {
    Double n = optional(o, k);
    require(
        n != null && Double.isFinite(n) && n >= min && n <= max && (!integral || n == Math.rint(n)),
        "Valore non valido: " + k);
  }
}
