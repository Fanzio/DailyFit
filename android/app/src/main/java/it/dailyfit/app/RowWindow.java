package it.dailyfit.app;

/** Pure range calculation for variable-height rows, with one viewport of overscan. */
final class RowWindow {
  final int first, end, before, after;

  RowWindow(int first, int end, int before, int after) {
    this.first = first;
    this.end = end;
    this.before = before;
    this.after = after;
  }

  static RowWindow calculate(int[] heights, int top, int viewport) {
    int low = Math.max(0, top - viewport), high = Math.max(0, top + viewport * 2);
    int first = 0, end = 0, before = 0, total = 0, through = 0;
    for (int i = 0; i < heights.length; i++) {
      int height = Math.max(1, heights[i]);
      if (total + height <= low) {
        first = i + 1;
        before = total + height;
      }
      if (total < high) {
        end = i + 1;
        through = total + height;
      }
      total += height;
    }
    end = Math.max(first, end);
    if (end == first) through = before;
    return new RowWindow(first, end, before, total - through);
  }
}
