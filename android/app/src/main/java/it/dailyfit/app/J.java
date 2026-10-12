package it.dailyfit.app;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import org.json.JSONArray;
import org.json.JSONObject;

/** Small checked-JSON boundary. Domain errors stay visible rather than becoming defaults. */
public final class J {
  private J() {}

  public static JSONObject obj(Object... pairs) {
    JSONObject o = new JSONObject();
    for (int i = 0; i < pairs.length; i += 2) put(o, (String) pairs[i], pairs[i + 1]);
    return o;
  }

  public static JSONObject parse(String s) {
    // Bound nesting before the recursive JSON parser sees an imported document.
    int depth = 0;
    boolean quoted = false, escaped = false;
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      if (quoted) {
        if (escaped) escaped = false;
        else if (c == '\\') escaped = true;
        else if (c == '"') quoted = false;
      } else if (c == '\'') throw new IllegalArgumentException("Usa JSON con virgolette doppie.");
      else if (c == '"') quoted = true;
      else if (c == '{' || c == '[') {
        if (++depth > 40) throw new IllegalArgumentException("JSON troppo annidato.");
      } else if (c == '}' || c == ']') depth--;
    }
    try {
      org.json.JSONTokener reader = new org.json.JSONTokener(s);
      Object value = reader.nextValue();
      if (!(value instanceof JSONObject) || reader.nextClean() != 0)
        throw new IllegalArgumentException("JSON non valido");
      return (JSONObject) value;
    } catch (Exception e) {
      throw new IllegalArgumentException("JSON non leggibile", e);
    }
  }

  public static JSONObject copy(JSONObject o) {
    JSONObject result = new JSONObject();
    java.util.Iterator<String> keys = o.keys();
    while (keys.hasNext()) {
      String key = keys.next();
      put(result, key, copyValue(o.opt(key)));
    }
    return result;
  }

  private static Object copyValue(Object value) {
    if (value instanceof JSONObject) return copy((JSONObject) value);
    if (value instanceof JSONArray) {
      JSONArray result = new JSONArray(), source = (JSONArray) value;
      for (int i = 0; i < source.length(); i++) result.put(copyValue(source.opt(i)));
      return result;
    }
    // Strings (including Base64 images), numbers and booleans are immutable.
    return value;
  }

  public static boolean equal(Object first, Object second) {
    if (first == second) return true;
    if (first == null || second == null) return false;
    if (first instanceof Number && second instanceof Number) {
      return new java.math.BigDecimal(first.toString())
              .compareTo(new java.math.BigDecimal(second.toString()))
          == 0;
    }
    if (first instanceof JSONObject && second instanceof JSONObject) {
      JSONObject a = (JSONObject) first, b = (JSONObject) second;
      if (a.length() != b.length()) return false;
      java.util.Iterator<String> keys = a.keys();
      while (keys.hasNext()) {
        String key = keys.next();
        if (!b.has(key) || !equal(a.opt(key), b.opt(key))) return false;
      }
      return true;
    }
    if (first instanceof JSONArray && second instanceof JSONArray) {
      JSONArray a = (JSONArray) first, b = (JSONArray) second;
      if (a.length() != b.length()) return false;
      for (int i = 0; i < a.length(); i++) if (!equal(a.opt(i), b.opt(i))) return false;
      return true;
    }
    return first.equals(second);
  }

  /** Canonicalize a private edited draft before publication. Never mutate published snapshots. */
  static Object reuseUnchanged(Object draft, Object previous) {
    if (draft == previous) return previous;
    if (draft instanceof JSONObject && previous instanceof JSONObject) {
      JSONObject next = (JSONObject) draft, old = (JSONObject) previous;
      boolean same = next.length() == old.length();
      for (String key : Domain.keys(next)) {
        Object shared = reuseUnchanged(next.opt(key), old.opt(key));
        put(next, key, shared);
        same &= old.has(key) && shared == old.opt(key);
      }
      return same ? old : next;
    }
    if (draft instanceof JSONArray && previous instanceof JSONArray) {
      JSONArray next = (JSONArray) draft, old = (JSONArray) previous;
      boolean same = next.length() == old.length();
      for (int i = 0; i < next.length(); i++) {
        Object shared = reuseUnchanged(next.opt(i), old.opt(i));
        try {
          next.put(i, shared);
        } catch (org.json.JSONException e) {
          throw new IllegalArgumentException(e);
        }
        same &= i < old.length() && shared == old.opt(i);
      }
      return same ? old : next;
    }
    return equal(draft, previous) ? previous : draft;
  }

  public static void put(JSONObject o, String k, Object v) {
    try {
      o.put(k, v == null ? JSONObject.NULL : v);
    } catch (Exception e) {
      throw new IllegalArgumentException("Valore non valido: " + k, e);
    }
  }

  public static JSONObject object(JSONObject o, String k) {
    try {
      return o.getJSONObject(k);
    } catch (Exception e) {
      throw new IllegalArgumentException("Campo mancante: " + k, e);
    }
  }

  public static JSONArray array(JSONObject o, String k) {
    try {
      return o.getJSONArray(k);
    } catch (Exception e) {
      throw new IllegalArgumentException("Elenco mancante: " + k, e);
    }
  }

  public static JSONObject at(JSONArray a, int i) {
    try {
      return a.getJSONObject(i);
    } catch (Exception e) {
      throw new IllegalArgumentException("Elemento non valido", e);
    }
  }

  public static List<JSONObject> list(JSONArray a) {
    List<JSONObject> r = new ArrayList<>();
    for (int i = 0; i < a.length(); i++) r.add(at(a, i));
    return r;
  }

  public static String id() {
    return UUID.randomUUID().toString().toUpperCase(java.util.Locale.ROOT);
  }

  public static String id(JSONObject o) {
    return o.optString("id", "");
  }

  public static JSONObject find(JSONArray a, String id) {
    for (JSONObject o : list(a)) if (id(o).equals(id)) return o;
    throw new IllegalArgumentException("Elemento non più disponibile");
  }

  public static JSONObject findOrNull(JSONArray a, String id) {
    for (JSONObject o : list(a)) if (id(o).equals(id)) return o;
    return null;
  }

  public static void remove(JSONArray a, String id) {
    for (int i = 0; i < a.length(); i++)
      if (id(at(a, i)).equals(id)) {
        a.remove(i);
        return;
      }
    throw new IllegalArgumentException("Elemento non più disponibile");
  }

  public static void replace(JSONArray a, JSONObject value) {
    for (int i = 0; i < a.length(); i++)
      if (id(at(a, i)).equals(id(value))) {
        try {
          a.put(i, value);
          return;
        } catch (Exception e) {
          throw new IllegalArgumentException(e);
        }
      }
    a.put(value);
  }

  public static void move(JSONArray a, String id, int offset) {
    if (offset != 1 && offset != -1) throw new IllegalArgumentException("Spostamento non valido");
    for (int i = 0; i < a.length(); i++)
      if (id(at(a, i)).equals(id)) {
        int to = i + offset;
        if (to < 0 || to >= a.length()) return;
        JSONObject first = at(a, i), second = at(a, to);
        try {
          a.put(i, second);
          a.put(to, first);
        } catch (Exception e) {
          throw new IllegalArgumentException(e);
        }
        return;
      }
  }
}
