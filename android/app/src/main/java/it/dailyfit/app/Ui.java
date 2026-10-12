package it.dailyfit.app;

import android.app.AlertDialog;
import android.content.res.ColorStateList;
import android.graphics.*;
import android.graphics.drawable.GradientDrawable;
import android.text.Editable;
import android.text.InputType;
import android.text.TextWatcher;
import android.view.*;
import android.widget.*;
import java.text.NumberFormat;
import java.util.Locale;
import java.util.function.Consumer;

/** Shared native widgets, spacing and typography for the dark/lime visual language. */
public final class Ui {
  public static final int BG = Color.rgb(15, 18, 17),
      CARD = Color.rgb(27, 31, 27),
      LIME = Color.rgb(194, 242, 107),
      MUTED = Color.rgb(151, 161, 143),
      WHITE = Color.rgb(245, 247, 243),
      RED = Color.rgb(255, 155, 145);
  public final MainActivity a;

  public Ui(MainActivity activity) {
    a = activity;
  }

  public int dp(float n) {
    return Math.round(n * a.getResources().getDisplayMetrics().density);
  }

  public LinearLayout column() {
    LinearLayout l = new LinearLayout(a);
    l.setOrientation(LinearLayout.VERTICAL);
    l.setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
    return l;
  }

  public LinearLayout row() {
    LinearLayout l = new LinearLayout(a);
    l.setOrientation(LinearLayout.HORIZONTAL);
    l.setGravity(Gravity.CENTER_VERTICAL);
    l.setLayoutParams(new LinearLayout.LayoutParams(-1, -2));
    return l;
  }

  public GradientDrawable background(int color, int radius) {
    GradientDrawable d = new GradientDrawable();
    d.setColor(color);
    d.setCornerRadius(dp(radius));
    d.setStroke(dp(1), Color.rgb(47, 54, 45));
    return d;
  }

  public LinearLayout card(LinearLayout parent) {
    LinearLayout l = column();
    l.setPadding(dp(14), dp(12), dp(14), dp(12));
    l.setBackground(background(CARD, 18));
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.bottomMargin = dp(12);
    l.setLayoutParams(p);
    parent.addView(l);
    return l;
  }

  public TextView text(String value, float size, int color) {
    TextView t = new TextView(a);
    t.setText(value);
    t.setTextSize(size);
    t.setTextColor(color);
    t.setPadding(0, dp(3), 0, dp(3));
    return t;
  }

  public TextView title(String value) {
    TextView t = text(value, 24, WHITE);
    t.setTypeface(null, Typeface.BOLD);
    return t;
  }

  public TextView bold(String value) {
    TextView t = text(value, 16, WHITE);
    t.setTypeface(null, Typeface.BOLD);
    return t;
  }

  public void hint(LinearLayout parent, String value) {
    parent.addView(text(value, 13, MUTED));
  }

  public void space(LinearLayout parent, int size) {
    View v = new View(a);
    parent.addView(v, new LinearLayout.LayoutParams(1, dp(size)));
  }

  public void weighted(LinearLayout row, View view) {
    row.addView(view, new LinearLayout.LayoutParams(0, -2, 1));
  }

  public Button button(String label, Runnable action) {
    Button b = new Button(a);
    b.setText(label);
    b.setTextSize(13);
    b.setAllCaps(false);
    b.setTextColor(LIME);
    b.setMinHeight(dp(48));
    b.setMinimumHeight(dp(48));
    b.setMinWidth(0);
    b.setMinimumWidth(0);
    b.setPadding(dp(10), dp(5), dp(10), dp(5));
    b.setBackgroundTintList(ColorStateList.valueOf(Color.rgb(40, 51, 34)));
    b.setOnClickListener(v -> a.safe(action));
    return b;
  }

  public Button primary(String label, Runnable action) {
    Button b = button(label, action);
    b.setTextColor(BG);
    b.setBackgroundTintList(ColorStateList.valueOf(LIME));
    return b;
  }

  public void action(LinearLayout parent, String label, Runnable action) {
    parent.addView(primary(label, action), new LinearLayout.LayoutParams(-1, dp(54)));
  }

  public EditText field(
      LinearLayout parent, String label, String value, boolean numeric, int lines) {
    if (!label.isEmpty()) parent.addView(text(label, 12, MUTED));
    EditText e = new EditText(a);
    e.setTextColor(WHITE);
    e.setTextSize(16);
    e.setHintTextColor(MUTED);
    e.setText(value);
    e.setSelectAllOnFocus(numeric);
    e.setMinHeight(dp(48));
    e.setPadding(dp(10), dp(7), dp(10), dp(7));
    e.setBackground(background(BG, 10));
    if (numeric) {
      e.setInputType(InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
      e.setKeyListener(android.text.method.DigitsKeyListener.getInstance("0123456789.,"));
    } else
      e.setInputType(
          InputType.TYPE_CLASS_TEXT
              | (lines > 1
                  ? InputType.TYPE_TEXT_FLAG_MULTI_LINE
                  : InputType.TYPE_TEXT_FLAG_CAP_SENTENCES));
    e.setMinLines(lines);
    e.setGravity(Gravity.TOP | Gravity.START);
    LinearLayout.LayoutParams p = new LinearLayout.LayoutParams(-1, -2);
    p.bottomMargin = dp(10);
    parent.addView(e, p);
    return e;
  }

  public Spinner select(LinearLayout parent, String label, String[] choices, String current) {
    parent.addView(text(label, 12, MUTED));
    Spinner s = new Spinner(a);
    ArrayAdapter<String> adapter =
        new ArrayAdapter<>(a, android.R.layout.simple_spinner_dropdown_item, choices);
    s.setAdapter(adapter);
    s.setMinimumHeight(dp(48));
    for (int i = 0; i < choices.length; i++) if (choices[i].equals(current)) s.setSelection(i);
    parent.addView(s, new LinearLayout.LayoutParams(-1, dp(48)));
    return s;
  }

  public void watch(EditText e, Consumer<String> change) {
    e.addTextChangedListener(
        new TextWatcher() {
          public void beforeTextChanged(CharSequence s, int st, int c, int after) {}

          public void onTextChanged(CharSequence s, int st, int before, int count) {
            change.accept(s.toString());
          }

          public void afterTextChanged(Editable v) {}
        });
  }

  public AlertDialog editor(String title, LinearLayout content, Consumer<AlertDialog> save) {
    ScrollView scroll = new ScrollView(a);
    scroll.setFillViewport(false);
    scroll.addView(content);
    content.setPadding(dp(18), dp(8), dp(18), dp(10));
    AlertDialog d =
        new AlertDialog.Builder(a)
            .setTitle(title)
            .setView(scroll)
            .setNegativeButton("Annulla", null)
            .setPositiveButton("Salva", null)
            .create();
    d.setOnShowListener(
        v -> {
          d.getButton(-1)
              .setOnClickListener(
                  x ->
                      a.safe(
                          () -> {
                            if (a.store.isBusy()) {
                              a.toast("Salvataggio in corso…");
                              return;
                            }
                            save.accept(d);
                          }));
          d.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        });
    a.showDialog(d);
    return d;
  }

  public void menu(View anchor, String[] labels, Runnable[] actions) {
    PopupMenu menu = new PopupMenu(a, anchor);
    for (int i = 0; i < labels.length; i++) menu.getMenu().add(0, i, i, labels[i]);
    menu.setOnMenuItemClickListener(
        item -> {
          a.safe(actions[item.getItemId()]);
          return true;
        });
    menu.show();
  }

  public void confirm(String title, String message, Runnable action) {
    new AlertDialog.Builder(a)
        .setTitle(title)
        .setMessage(message)
        .setNegativeButton("Annulla", null)
        .setPositiveButton("Conferma", (d, w) -> a.safe(action))
        .show();
  }

  public void rename(String title, String initial, Consumer<String> save) {
    LinearLayout c = column();
    EditText f = field(c, "Nome", initial, false, 1);
    editor(
        title,
        c,
        d -> {
          String s = Domain.text(f.getText().toString(), "Nome", 80, true);
          save.accept(s);
          d.dismiss();
        });
  }

  public static String fmt(double value) {
    NumberFormat f = NumberFormat.getNumberInstance(Locale.ITALY);
    f.setMaximumFractionDigits(1);
    f.setGroupingUsed(false);
    return f.format(value);
  }

  public static String edit(Object value) {
    return value == null || value == org.json.JSONObject.NULL
        ? ""
        : value.toString().replace('.', ',');
  }

  public static String clock(int seconds) {
    return String.format(Locale.ROOT, "%02d:%02d", seconds / 60, seconds % 60);
  }

  public View ring(String name, double amount, Double goal, int color) {
    LinearLayout c = column();
    c.setGravity(Gravity.CENTER);
    View circle =
        new View(a) {
          final Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);

          @Override
          protected void onDraw(Canvas canvas) {
            float stroke = dp(5),
                size = Math.min(getWidth(), getHeight()) - stroke * 2,
                x = (getWidth() - size) / 2,
                y = (getHeight() - size) / 2;
            p.setStyle(Paint.Style.STROKE);
            p.setStrokeWidth(stroke);
            p.setStrokeCap(Paint.Cap.ROUND);
            p.setColor(Color.rgb(47, 55, 43));
            RectF r = new RectF(x, y, x + size, y + size);
            canvas.drawArc(r, 0, 360, false, p);
            p.setColor(color);
            canvas.drawArc(
                r,
                -90,
                goal != null && goal > 0 ? (float) (Math.min(1, amount / goal) * 360) : 0,
                false,
                p);
          }
        };
    circle.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
    c.addView(circle, new LinearLayout.LayoutParams(dp(54), dp(54)));
    TextView label = text(name, 11, MUTED),
        number = bold(fmt(amount)),
        target = text(goal == null ? "Obiettivo —" : "/ " + fmt(goal), 10, MUTED);
    label.setGravity(Gravity.CENTER);
    number.setGravity(Gravity.CENTER);
    target.setGravity(Gravity.CENTER);
    c.addView(label);
    c.addView(number);
    c.addView(target);
    c.setContentDescription(
        name
            + ": "
            + fmt(amount)
            + (goal == null ? ", obiettivo non impostato" : ", obiettivo " + fmt(goal)));
    return c;
  }
}
