package it.dailyfit.app;

import java.util.*;
import java.util.function.Consumer;
import java.util.function.Supplier;
import org.json.JSONObject;

/** Reuses unchanged rows by identity. States must be immutable value snapshots. */
final class KeyedRows<T> {
  static final class Item<T> {
    final String key;
    final JSONObject state;
    final Supplier<T> create;

    Item(String key, JSONObject state, Supplier<T> create) {
      this.key = key;
      this.state = state;
      this.create = create;
    }
  }

  private static final class Cached<T> {
    final JSONObject state;
    final T row;

    Cached(JSONObject state, T row) {
      this.state = state;
      this.row = row;
    }
  }

  private Map<String, Cached<T>> rows = new LinkedHashMap<>();
  private final Consumer<T> dispose;

  KeyedRows(Consumer<T> dispose) {
    this.dispose = dispose;
  }

  T get(String key) {
    return rows.containsKey(key) ? rows.get(key).row : null;
  }

  List<T> reconcile(List<Item<T>> items) {
    Set<String> keys = new HashSet<>();
    for (Item<T> item : items)
      if (!keys.add(item.key)) throw new IllegalArgumentException("Duplicate row: " + item.key);
    Map<String, Cached<T>> next = new LinkedHashMap<>();
    List<T> created = new ArrayList<>();
    try {
      for (Item<T> item : items) {
        Cached<T> old = rows.get(item.key);
        if (old != null && J.equal(old.state, item.state)) next.put(item.key, old);
        else {
          T row = item.create.get();
          created.add(row);
          next.put(item.key, new Cached<>(item.state, row));
        }
      }
    } catch (RuntimeException error) {
      for (T row : created) dispose.accept(row);
      throw error;
    }
    for (Map.Entry<String, Cached<T>> old : rows.entrySet())
      if (next.get(old.getKey()) != old.getValue()) dispose.accept(old.getValue().row);
    rows = next;
    List<T> ordered = new ArrayList<>();
    for (Cached<T> value : rows.values()) ordered.add(value.row);
    return ordered;
  }

  void clear() {
    for (Cached<T> value : rows.values()) dispose.accept(value.row);
    rows.clear();
  }
}
