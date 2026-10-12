package it.dailyfit.app;

import android.content.Context;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewTreeObserver;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import java.util.*;
import java.util.function.Consumer;
import org.json.JSONObject;

/** A keyed list for the existing native layouts; unchanged views are not rebuilt. */
final class RowList extends LinearLayout {
  static final class Row extends LinearLayout {
    private final List<Runnable> cleanups = new ArrayList<>();

    Row(Context context) {
      super(context);
      setOrientation(VERTICAL);
      setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
    }

    void onDispose(Runnable cleanup) {
      cleanups.add(cleanup);
    }

    void dispose() {
      for (Runnable cleanup : cleanups) cleanup.run();
      cleanups.clear();
    }
  }

  private final KeyedRows<Row> cache =
      new KeyedRows<>(
          row -> {
            row.dispose();
            if (row.getParent() instanceof ViewGroup) ((ViewGroup) row.getParent()).removeView(row);
          });

  private List<KeyedRows.Item<Row>> items = Collections.emptyList();
  private final Map<String, Integer> heights = new HashMap<>();
  private final View before = new View(getContext()), after = new View(getContext());
  private boolean keepAll, queued, disposed;
  private ViewTreeObserver observer;
  private final ViewTreeObserver.OnScrollChangedListener scrollListener = this::schedule;
  private final ViewTreeObserver.OnGlobalLayoutListener layoutListener = this::schedule;

  void keepAllRows() {
    keepAll = true;
  }

  @Override
  protected void onAttachedToWindow() {
    super.onAttachedToWindow();
    observer = getViewTreeObserver();
    observer.addOnScrollChangedListener(scrollListener);
    observer.addOnGlobalLayoutListener(layoutListener);
    schedule();
  }

  @Override
  protected void onDetachedFromWindow() {
    if (observer != null && observer.isAlive()) {
      observer.removeOnScrollChangedListener(scrollListener);
      observer.removeOnGlobalLayoutListener(layoutListener);
    }
    observer = null;
    super.onDetachedFromWindow();
  }

  private void schedule() {
    if (queued || disposed) return;
    queued = true;
    postOnAnimation(
        () -> {
          queued = false;
          if (!disposed) renderWindow();
        });
  }

  RowList(Context context) {
    super(context);
    setOrientation(VERTICAL);
    setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
  }

  KeyedRows.Item<Row> item(String key, JSONObject state, Consumer<Row> build) {
    return new KeyedRows.Item<>(
        key,
        state,
        () -> {
          Row row = new Row(getContext());
          try {
            build.accept(row);
            return row;
          } catch (RuntimeException error) {
            row.dispose();
            throw error;
          }
        });
  }

  void show(List<KeyedRows.Item<Row>> items) {
    this.items = new ArrayList<>(items);
    Set<String> keys = new HashSet<>();
    for (KeyedRows.Item<Row> item : items)
      if (!keys.add(item.key)) throw new IllegalArgumentException("Duplicate row: " + item.key);
    heights.keySet().retainAll(keys);
    renderWindow();
  }

  private void renderWindow() {
    ScrollView scroll = null;
    for (android.view.ViewParent p = getParent(); p != null; p = p.getParent())
      if (p instanceof ScrollView) {
        scroll = (ScrollView) p;
        break;
      }
    int start = 0, end = items.size(), leading = 0, trailing = 0;
    android.view.accessibility.AccessibilityManager accessibility =
        (android.view.accessibility.AccessibilityManager)
            getContext().getSystemService(Context.ACCESSIBILITY_SERVICE);
    boolean windowed =
        !keepAll
            && items.size() > 32
            && scroll != null
            && (accessibility == null || !accessibility.isTouchExplorationEnabled());
    if (windowed) {
      int[] sizes = new int[items.size()];
      int estimate = Math.round(120 * getResources().getDisplayMetrics().density);
      for (int i = 0; i < sizes.length; i++) {
        String key = items.get(i).key;
        Row row = cache.get(key);
        if (row != null && row.getHeight() > 0) heights.put(key, row.getHeight());
        sizes[i] = heights.getOrDefault(key, estimate);
      }
      int[] position = new int[2], viewport = new int[2];
      getLocationOnScreen(position);
      scroll.getLocationOnScreen(viewport);
      RowWindow range =
          RowWindow.calculate(
              sizes,
              viewport[1] - position[1],
              Math.max(
                  1,
                  scroll.getHeight() > 0
                      ? scroll.getHeight()
                      : getResources().getDisplayMetrics().heightPixels));
      start = range.first;
      end = range.end;
      leading = range.before;
      trailing = range.after;
    }
    List<Row> visible = cache.reconcile(items.subList(start, end));
    List<View> ordered = new ArrayList<>();
    if (windowed) {
      spacer(before, leading);
      ordered.add(before);
    }
    ordered.addAll(visible);
    if (windowed) {
      spacer(after, trailing);
      ordered.add(after);
    }
    for (int i = getChildCount() - 1; i >= 0; i--)
      if (!ordered.contains(getChildAt(i))) removeViewAt(i);
    for (int i = 0; i < ordered.size(); i++) {
      View row = ordered.get(i);
      if (getChildAt(i) == row) continue;
      if (row.getParent() == this) removeView(row);
      addView(row, i);
    }
  }

  private void spacer(View view, int height) {
    if (view.getLayoutParams() == null || view.getLayoutParams().height != height)
      view.setLayoutParams(new LinearLayout.LayoutParams(1, height));
    view.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
  }

  void dispose() {
    disposed = true;
    items = Collections.emptyList();
    heights.clear();
    cache.clear();
  }

  Row row(String key) {
    return cache.get(key);
  }
}
