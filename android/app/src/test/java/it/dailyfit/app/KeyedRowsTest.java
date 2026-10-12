package it.dailyfit.app;

import static org.junit.Assert.*;

import java.util.*;
import org.junit.Test;

public class KeyedRowsTest {
  private int created;
  private final List<Object> disposed = new ArrayList<>();
  private final KeyedRows<Object> rows = new KeyedRows<>(disposed::add);

  private KeyedRows.Item<Object> item(String key, int value) {
    return new KeyedRows.Item<>(
        key,
        J.obj("value", value),
        () -> {
          created++;
          return new Object();
        });
  }

  @Test
  public void unchangedRowsKeepIdentityWithoutCallingBuilders() {
    List<Object> before = rows.reconcile(Arrays.asList(item("a", 1), item("b", 2)));
    List<Object> after = rows.reconcile(Arrays.asList(item("a", 1), item("b", 2)));
    assertSame(before.get(0), after.get(0));
    assertSame(before.get(1), after.get(1));
    assertEquals(2, created);
    assertTrue(disposed.isEmpty());
  }

  @Test
  public void editingOneOfThousandRowsOnlyReplacesThatRow() {
    List<KeyedRows.Item<Object>> initial = new ArrayList<>(), changed = new ArrayList<>();
    for (int i = 0; i < 1000; i++) {
      initial.add(item("" + i, i));
      changed.add(item("" + i, i == 500 ? -1 : i));
    }
    List<Object> before = rows.reconcile(initial), after = rows.reconcile(changed);
    for (int i = 0; i < 1000; i++) if (i != 500) assertSame(before.get(i), after.get(i));
    assertNotSame(before.get(500), after.get(500));
    assertEquals(Collections.singletonList(before.get(500)), disposed);
    assertEquals(1001, created);
  }

  @Test
  public void insertionDeletionAndReorderingPreserveSurvivors() {
    List<Object> before = rows.reconcile(Arrays.asList(item("a", 1), item("b", 2), item("c", 3)));
    List<Object> after = rows.reconcile(Arrays.asList(item("c", 3), item("d", 4), item("a", 1)));
    assertSame(before.get(2), after.get(0));
    assertSame(before.get(0), after.get(2));
    assertEquals(Collections.singletonList(before.get(1)), disposed);
    assertEquals(4, created);
  }

  @Test
  public void filteringRemovesOnlyHiddenRowsAndRestoresThemOnDemand() {
    List<Object> before = rows.reconcile(Arrays.asList(item("a", 1), item("b", 2)));
    assertSame(before.get(1), rows.reconcile(Collections.singletonList(item("b", 2))).get(0));
    List<Object> after = rows.reconcile(Arrays.asList(item("a", 1), item("b", 2)));
    assertSame(before.get(1), after.get(1));
    assertNotSame(before.get(0), after.get(0));
  }

  @Test
  public void duplicateIdsAreRejectedBeforeChangingExistingRows() {
    Object original = rows.reconcile(Collections.singletonList(item("a", 1))).get(0);
    try {
      rows.reconcile(Arrays.asList(item("a", 2), item("a", 3)));
      fail();
    } catch (IllegalArgumentException expected) {
    }
    assertSame(original, rows.get("a"));
    assertEquals(1, created);
    assertTrue(disposed.isEmpty());
  }

  @Test
  public void builderFailureDisposesNewRowsButKeepsOldRows() {
    Object original = rows.reconcile(Collections.singletonList(item("a", 1))).get(0);
    KeyedRows.Item<Object> failure =
        new KeyedRows.Item<>(
            "fail",
            J.obj(),
            () -> {
              throw new IllegalStateException();
            });
    try {
      rows.reconcile(Arrays.asList(item("b", 2), failure));
      fail();
    } catch (IllegalStateException expected) {
    }
    assertSame(original, rows.get("a"));
    assertEquals(1, disposed.size());
    assertFalse(disposed.contains(original));
  }

  @Test
  public void leavingScreenReleasesEveryRowOnce() {
    rows.reconcile(Arrays.asList(item("a", 1), item("b", 2)));
    rows.clear();
    rows.clear();
    assertEquals(2, disposed.size());
    assertNull(rows.get("a"));
  }
}
