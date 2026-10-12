package it.dailyfit.app;

import java.nio.charset.StandardCharsets;
import java.util.*;
import org.json.*;

/** Records are immutable after publication. Only changed records are encoded for SQLite. */
final class RecordArchive {
  static final class Delta {
    final Map<String, byte[]> writes = new LinkedHashMap<>();
    final Set<String> deletes = new HashSet<>();
    final Map<String, JSONObject> next;
    final Map<String, Integer> sizes;
    long payloadBytes;
    long totalBytes;

    Delta(Map<String, JSONObject> next, Map<String, Integer> sizes) {
      this.next = next;
      this.sizes = sizes;
    }

    boolean empty() {
      return writes.isEmpty() && deletes.isEmpty();
    }
  }

  private Map<String, JSONObject> committed = new HashMap<>();
  private Map<String, Integer> sizes = new HashMap<>();

  void adopt(Map<String, byte[]> rows) {
    Map<String, JSONObject> parsed = new HashMap<>();
    Map<String, Integer> lengths = new HashMap<>();
    for (Map.Entry<String, byte[]> row : rows.entrySet()) {
      parsed.put(row.getKey(), J.parse(new String(row.getValue(), StandardCharsets.UTF_8)));
      lengths.put(row.getKey(), row.getValue().length);
    }
    committed = parsed;
    sizes = lengths;
  }

  void adopt(Map<String, byte[]> rows, JSONObject envelope) {
    committed = split(envelope);
    sizes = new HashMap<>();
    for (Map.Entry<String, byte[]> row : rows.entrySet())
      sizes.put(row.getKey(), row.getValue().length);
  }

  Delta stage(JSONObject envelope) {
    Map<String, JSONObject> next = split(envelope);
    Delta delta = new Delta(next, new HashMap<>(sizes));
    for (Map.Entry<String, JSONObject> row : next.entrySet()) {
      if (!J.equal(row.getValue(), committed.get(row.getKey()))) {
        byte[] bytes = row.getValue().toString().getBytes(StandardCharsets.UTF_8);
        delta.writes.put(row.getKey(), bytes);
        delta.sizes.put(row.getKey(), bytes.length);
        delta.payloadBytes += bytes.length;
      }
    }
    for (String key : committed.keySet())
      if (!next.containsKey(key)) {
        delta.deletes.add(key);
        delta.sizes.remove(key);
      }
    long total = 0;
    for (int size : delta.sizes.values()) total += size;
    for (JSONObject exercise : J.list(J.array(J.object(envelope, "data"), "exercises"))) {
      // The image payload is bounded by ImageArchive; metadata has its own bound here.
      Domain.require(
          exercise.isNull("photo") && exercise.isNull("musclePhoto"), "Immagini non separate.");
    }
    Domain.require(total <= Domain.MAX_BYTES, "Archivio troppo grande.");
    delta.totalBytes = total;
    return delta;
  }

  void committed(Delta delta) {
    committed = delta.next;
    sizes = delta.sizes;
  }

  static Map<String, JSONObject> split(JSONObject envelope) {
    JSONObject data = J.object(envelope, "data"), images = J.object(envelope, "images");
    Map<String, JSONObject> rows = new LinkedHashMap<>();
    JSONObject settings = new JSONObject();
    Set<String> collections =
        new HashSet<>(Arrays.asList("exercises", "foods", "notes", "plans", "week", "dates"));
    for (String key : Domain.keys(data))
      if (!collections.contains(key)) J.put(settings, key, data.opt(key));
    rows.put("settings", settings);
    for (String kind : new String[] {"exercises", "foods", "notes", "plans"}) {
      JSONArray order = new JSONArray();
      for (JSONObject value : J.list(J.array(data, kind))) {
        String id = J.id(value);
        order.put(id);
        JSONObject record = value;
        if (kind.equals("exercises"))
          record =
              J.obj(
                  "value",
                  value,
                  "images",
                  images.optJSONObject(id) == null ? new JSONObject() : images.optJSONObject(id));
        if (kind.equals("plans")) {
          record = J.obj("id", id, "name", value.optString("name"));
          JSONArray days = new JSONArray();
          for (JSONObject day : J.list(J.array(value, "days"))) {
            days.put(J.id(day));
            rows.put("day/" + id + "/" + J.id(day), day);
          }
          J.put(record, "days", days);
        }
        rows.put(kind + "/" + id, record);
      }
      rows.put("order/" + kind, J.obj("ids", order));
    }
    JSONArray week = J.array(data, "week");
    for (int i = 0; i < week.length(); i++) rows.put("week/" + i, J.at(week, i));
    JSONObject dates = J.object(data, "dates");
    for (String key : Domain.keys(dates)) rows.put("date/" + key, J.object(dates, key));
    return rows;
  }

  static JSONObject join(Map<String, byte[]> stored) {
    Map<String, JSONObject> rows = new HashMap<>();
    for (Map.Entry<String, byte[]> row : stored.entrySet())
      rows.put(row.getKey(), J.parse(new String(row.getValue(), StandardCharsets.UTF_8)));
    Set<String> used = new HashSet<>();
    JSONObject data = J.copy(take(rows, used, "settings")), images = new JSONObject();
    for (String kind : new String[] {"exercises", "foods", "notes", "plans"}) {
      JSONArray list = new JSONArray(), ids = J.array(take(rows, used, "order/" + kind), "ids");
      for (int i = 0; i < ids.length(); i++) {
        String id = ids.optString(i);
        JSONObject value = take(rows, used, kind + "/" + id);
        if (kind.equals("exercises")) {
          J.put(images, id, J.object(value, "images"));
          value = J.object(value, "value");
        }
        if (kind.equals("plans")) {
          value = J.copy(value);
          JSONArray dayIDs = J.array(value, "days"), days = new JSONArray();
          for (int d = 0; d < dayIDs.length(); d++) {
            String dayID = dayIDs.optString(d);
            JSONObject day = take(rows, used, "day/" + id + "/" + dayID);
            Domain.require(J.id(day).equals(dayID), "Giornata non coerente.");
            days.put(day);
          }
          J.put(value, "days", days);
        }
        Domain.require(J.id(value).equals(id), "Identificativo non coerente.");
        list.put(value);
      }
      J.put(data, kind, list);
    }
    JSONArray week = new JSONArray();
    for (int i = 0; i < 7; i++) week.put(take(rows, used, "week/" + i));
    J.put(data, "week", week);
    JSONObject dates = new JSONObject();
    for (String key : rows.keySet())
      if (key.startsWith("date/")) J.put(dates, key.substring(5), take(rows, used, key));
    J.put(data, "dates", dates);
    Domain.require(used.size() == rows.size(), "Archivio con record non riconosciuti.");
    return J.obj(
        "storageFormat", "DailyFitLocal", "storageVersion", 2, "data", data, "images", images);
  }

  private static JSONObject take(Map<String, JSONObject> rows, Set<String> used, String key) {
    Domain.require(
        rows.containsKey(key) && used.add(key), "Archivio incompleto o riferimenti duplicati.");
    return rows.get(key);
  }
}
