package it.dailyfit.app;

import android.Manifest;
import android.app.*;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.*;
import android.provider.Settings;
import android.view.*;
import android.widget.*;
import java.io.*;
import java.time.LocalDate;
import java.util.*;
import java.util.function.Consumer;
import org.json.JSONObject;

public final class MainActivity extends Activity implements Store.Listener {
  Store store;
  RestTimer rest;
  Ui ui;
  Photos photos;

  @Override
  public void onTrimMemory(int level) {
    super.onTrimMemory(level);
    if (photos != null && level >= android.content.ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW)
      photos.clearMemory();
  }

  GymScreen gym;
  NutritionScreen nutrition;
  DiaryScreen diary;
  SettingsScreen settings;
  LinearLayout root, content, timerBar, undoBar;
  ScrollView scroll;
  int area = 0, gymTab = 0, nutritionTab = 0;
  String planID = "", dayID = "";
  LocalDate date = LocalDate.now();
  boolean base = false;
  final Set<String> expandedMeals = new HashSet<>();
  final List<Runnable> ticks = new ArrayList<>();
  final List<Dialog> dialogs = new ArrayList<>();
  final Handler handler = new Handler(Looper.getMainLooper());
  Consumer<String> photoResult;
  byte[] exportBytes;
  boolean resumed = false, rendering = false, timerPermissionExplained = false;
  private final Runnable ticker =
      new Runnable() {
        @Override
        public void run() {
          if (!resumed) return;
          safe(() -> rest.reconcile());
          for (Runnable tick : new ArrayList<>(ticks)) tick.run();
          if (rest.running()) handler.postDelayed(this, 1000);
        }
      };

  @Override
  public void onCreate(Bundle state) {
    super.onCreate(state);
    if (Build.VERSION.SDK_INT >= 30) getWindow().setDecorFitsSystemWindows(false);
    else
      getWindow()
          .getDecorView()
          .setSystemUiVisibility(
              View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                  | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                  | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
    store = ((FitApplication) getApplication()).store;
    rest = new RestTimer(this);
    ui = new Ui(this);
    photos = new Photos();
    gym = new GymScreen(this);
    nutrition = new NutritionScreen(this);
    diary = new DiaryScreen(this);
    settings = new SettingsScreen(this);
    if (state != null) {
      area = state.getInt("area");
      gymTab = state.getInt("gymTab");
      nutritionTab = state.getInt("nutritionTab");
      planID = state.getString("plan", "");
      dayID = state.getString("day", "");
      base = state.getBoolean("base");
      try {
        date = LocalDate.parse(state.getString("date", LocalDate.now().toString()));
      } catch (Exception ignored) {
      }
    }
    store.listener = this;
    render(false);
    store.load();
    if (Build.VERSION.SDK_INT >= 33)
      getOnBackInvokedDispatcher()
          .registerOnBackInvokedCallback(
              android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::navigateBack);
  }

  @Override
  protected void onSaveInstanceState(Bundle b) {
    super.onSaveInstanceState(b);
    b.putInt("area", area);
    b.putInt("gymTab", gymTab);
    b.putInt("nutritionTab", nutritionTab);
    b.putString("plan", planID);
    b.putString("day", dayID);
    b.putString("date", date.toString());
    b.putBoolean("base", base);
  }

  @Override
  protected void onResume() {
    super.onResume();
    resumed = true;
    store.foreground = true;
    store.listener = this;
    safe(
        () -> {
          rest.reconcile();
          rest.schedule();
        });
    render(true);
    startTicks();
  }

  @Override
  protected void onPause() {
    diary.flush();
    resumed = false;
    store.foreground = false;
    handler.removeCallbacks(ticker);
    store.discardUndo();
    awake();
    super.onPause();
  }

  @Override
  protected void onDestroy() {
    if (store.listener == this) store.listener = null;
    handler.removeCallbacksAndMessages(null);
    releaseContent();
    super.onDestroy();
  }

  @Override
  public void onBackPressed() {
    navigateBack();
  }

  void navigateBack() {
    if (area == 0 && gymTab == 0 && !dayID.isEmpty()) dayID = "";
    else if (area == 0 && gymTab == 0 && !planID.isEmpty()) planID = "";
    else {
      moveTaskToBack(true);
      return;
    }
    render(false);
  }

  void startTicks() {
    handler.removeCallbacks(ticker);
    if (resumed && rest.running()) handler.post(ticker);
  }

  void showDialog(Dialog d) {
    dialogs.add(d);
    d.setOnDismissListener(
        v -> {
          dialogs.remove(d);
          awake();
        });
    d.show();
    awake();
  }

  void awake() {
    boolean on =
        resumed
            && store.data != null
            && store.data.optBoolean("keepScreenAwake")
            && area == 0
            && gymTab == 0
            && !dayID.isEmpty()
            && dialogs.isEmpty();
    if (on) getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    else getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
  }

  public void safe(Runnable action) {
    try {
      action.run();
    } catch (Exception e) {
      error(Store.message(e));
    }
  }

  void toast(String message) {
    Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
  }

  @Override
  public void error(String message) {
    if (!isFinishing())
      new AlertDialog.Builder(this)
          .setTitle("DailyFit")
          .setMessage(message)
          .setPositiveButton("OK", null)
          .show();
  }

  @Override
  public void changed() {
    if (store.data != null && rest.exists()) {
      boolean found = false;
      for (JSONObject p : J.list(J.array(store.data, "plans")))
        for (JSONObject d : J.list(J.array(p, "days")))
          for (JSONObject e : J.list(J.array(d, "entries")))
            if (J.id(e).equals(rest.entry())) found = true;
      if (!found) safe(() -> rest.stop());
    }
    if (resumed) render(true);
  }

  private String renderedChrome = "";
  private JSONObject renderedContent;
  private String renderedRoute = "";
  Runnable refreshContent = () -> {};
  private final List<Runnable> contentCleanups = new ArrayList<>();

  RowList rowList(LinearLayout parent) {
    RowList list = new RowList(this);
    parent.addView(list);
    contentCleanups.add(list::dispose);
    return list;
  }

  private void releaseContent() {
    for (Runnable cleanup : contentCleanups) cleanup.run();
    contentCleanups.clear();
    refreshContent = () -> {};
    ticks.clear();
  }

  private String contentRoute() {
    if (area == 0 && gymTab == 0) {
      JSONObject plan = J.findOrNull(J.array(store.data, "plans"), planID);
      if (plan == null) {
        planID = "";
        dayID = "";
      } else if (J.findOrNull(J.array(plan, "days"), dayID) == null) dayID = "";
      return "gym/" + planID + "/" + dayID;
    }
    return area == 1 && nutritionTab == 0 ? "diet/" + date + "/" + base : "catalog";
  }

  private Runnable timerBarTick;

  private JSONObject contentState() {
    return RenderState.content(
        store.data,
        area,
        area == 0 ? gymTab : nutritionTab,
        planID,
        dayID,
        date,
        base,
        expandedMeals);
  }

  void render(boolean preserveScroll) {
    if (rendering || isFinishing()) return;
    String chrome = area + ":" + (area == 0 ? gymTab : nutritionTab);
    if (store.data == null || root == null || !chrome.equals(renderedChrome)) {
      buildScreen(preserveScroll);
      renderedChrome = store.data == null ? "" : chrome;
      renderedContent = store.data == null ? null : contentState();
      renderedRoute = store.data == null ? "" : contentRoute();
      return;
    }
    rendering = true;
    try {
      String route = contentRoute();
      JSONObject next = contentState();
      if (!route.equals(renderedRoute) || !preserveScroll || !J.equal(renderedContent, next)) {
        int y = preserveScroll ? scroll.getScrollY() : 0;
        if (!route.equals(renderedRoute)) {
          releaseContent();
          content.removeAllViews();
          populateContent();
        } else refreshContent.run();
        renderedRoute = route;
        renderedContent = contentState();
        scroll.post(() -> scroll.scrollTo(0, y));
      }
      updateBars();
      for (Runnable tick : new ArrayList<>(ticks)) tick.run();
      awake();
      startTicks();
    } catch (Exception e) {
      error(Store.message(e));
    } finally {
      rendering = false;
    }
  }

  private void populateContent() {
    if (area == 0) {
      if (gymTab == 0) gym.plans();
      else if (gymTab == 1) gym.catalog();
      else diary.show();
    } else {
      if (nutritionTab == 0) nutrition.diet();
      else nutrition.foods();
    }
  }

  private void updateBars() {
    if (undoBar != null) root.removeView(undoBar);
    if (timerBar != null) root.removeView(timerBar);
    if (timerBarTick != null) ticks.remove(timerBarTick);
    timerBarTick = null;
    undoBar = ui.row();
    if (store.canUndo()) {
      ui.weighted(undoBar, ui.text(store.undoLabel, 12, Ui.MUTED));
      undoBar.addView(ui.button("Annulla", () -> store.undo(() -> {})));
      undoBar.setPadding(ui.dp(12), 0, ui.dp(8), 0);
      root.addView(undoBar, root.getChildCount() - 1);
    }
    timerBar = ui.row();
    timerBar.setBackgroundColor(0xff25301f);
    if (rest.exists()) {
      TextView status = ui.text("", 13, Ui.WHITE);
      ui.weighted(timerBar, status);
      Button toggle = ui.button("", () -> timerCommand(rest::toggle));
      timerBar.addView(toggle);
      timerBar.addView(ui.button("↻", () -> timerCommand(rest::restart)));
      timerBar.addView(ui.button("×", () -> timerCommand(rest::stop)));
      timerBarTick =
          () -> {
            int remaining = rest.remaining();
            boolean running = rest.running();
            String text =
                rest.name()
                    + "\n"
                    + Ui.clock(remaining)
                    + " · "
                    + (remaining == 0 ? "Terminato" : running ? "Recupero" : "In pausa");
            if (!text.contentEquals(status.getText())) status.setText(text);
            String action = running ? "Ⅱ" : "▶";
            if (!action.contentEquals(toggle.getText())) {
              toggle.setText(action);
              toggle.setContentDescription(running ? "Pausa recupero" : "Riprendi recupero");
            }
          };
      timerBarTick.run();
      ticks.add(timerBarTick);
      timerBar.setPadding(ui.dp(14), 0, ui.dp(4), 0);
      root.addView(timerBar, root.getChildCount() - 1);
    }
  }

  void buildScreen(boolean preserveScroll) {
    if (rendering || isFinishing()) return;
    rendering = true;
    int y = preserveScroll && scroll != null ? scroll.getScrollY() : 0;
    try {
      releaseContent();
      root = ui.column();
      root.setBackgroundColor(Ui.BG);
      setContentView(root);
      root.setOnApplyWindowInsetsListener(
          (v, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
              android.graphics.Insets i =
                  insets.getInsets(
                      WindowInsets.Type.systemBars()
                          | WindowInsets.Type.displayCutout()
                          | WindowInsets.Type.ime());
              v.setPadding(i.left, i.top, i.right, i.bottom);
            } else
              v.setPadding(
                  insets.getSystemWindowInsetLeft(),
                  insets.getSystemWindowInsetTop(),
                  insets.getSystemWindowInsetRight(),
                  insets.getSystemWindowInsetBottom());
            return insets;
          });
      root.requestApplyInsets();
      if (store.data == null) {
        LinearLayout c = ui.column();
        c.setPadding(ui.dp(24), ui.dp(40), ui.dp(24), 0);
        c.addView(ui.title("DailyFit"));
        ui.hint(c, store.loadError == null ? "Apertura dei tuoi dati…" : store.loadError);
        if (store.loadError != null) ui.action(c, "Riprova", store::load);
        root.addView(c);
        return;
      }
      LinearLayout top = ui.row();
      top.setPadding(ui.dp(18), ui.dp(12), ui.dp(12), ui.dp(8));
      LinearLayout headings = ui.column();
      headings.addView(ui.text("IL TUO SPAZIO", 10, Ui.LIME));
      headings.addView(ui.title(area == 0 ? "Palestra" : "Nutrizione"));
      ui.weighted(top, headings);
      top.addView(ui.button("⚙", settings::show));
      root.addView(top);
      LinearLayout tabs = ui.row();
      tabs.setPadding(ui.dp(14), 0, ui.dp(14), ui.dp(8));
      String[] names =
          area == 0
              ? new String[] {"Schede", "Esercizi", "Diario"}
              : new String[] {"Dieta", "Alimenti"};
      for (int i = 0; i < names.length; i++) {
        final int index = i;
        Button b =
            ui.button(
                names[i],
                () -> {
                  if (area == 0) gymTab = index;
                  else nutritionTab = index;
                  render(false);
                });
        boolean selected = i == (area == 0 ? gymTab : nutritionTab);
        b.setSelected(selected);
        b.setTextColor(selected ? Ui.BG : Ui.MUTED);
        b.setBackgroundTintList(
            android.content.res.ColorStateList.valueOf(selected ? Ui.LIME : Ui.CARD));
        ui.weighted(tabs, b);
      }
      root.addView(tabs);
      scroll = new ScrollView(this);
      scroll.setFillViewport(true);
      content = ui.column();
      content.setPadding(ui.dp(18), ui.dp(12), ui.dp(18), ui.dp(16));
      scroll.addView(content);
      root.addView(scroll, new LinearLayout.LayoutParams(-1, 0, 1));
      populateContent();
      LinearLayout nav = ui.row();
      nav.setBackgroundColor(Ui.CARD);
      Button
          left =
              ui.button(
                  "Palestra",
                  () -> {
                    area = 0;
                    render(false);
                  }),
          center = ui.button("ChatGPT ↗", this::openChat),
          right =
              ui.button(
                  "Nutrizione",
                  () -> {
                    area = 1;
                    render(false);
                  });
      center.setOnLongClickListener(
          v -> {
            settings.chat();
            return true;
          });
      center.setContentDescription("Apri ChatGPT. Tieni premuto per impostare una chat.");
      left.setTextColor(area == 0 ? Ui.LIME : Ui.MUTED);
      right.setTextColor(area == 1 ? Ui.LIME : Ui.MUTED);
      ui.weighted(nav, left);
      ui.weighted(nav, center);
      ui.weighted(nav, right);
      root.addView(nav);
      updateBars();
      scroll.post(() -> scroll.scrollTo(0, y));
      awake();
      startTicks();
    } catch (Exception e) {
      error(Store.message(e));
    } finally {
      rendering = false;
    }
  }

  private void openChat() {
    safe(
        () -> {
          if (!ChatGPTLink.open(store.data.optString("chatLink"), new ChatGPTLauncher(this))) {
            error("Impossibile aprire ChatGPT: nessuna app o browser disponibile.");
          }
        });
  }

  void open(String url) {
    if (url.isEmpty()) return;
    try {
      startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(Domain.web(url, false))));
    } catch (ActivityNotFoundException e) {
      error("Nessuna app disponibile per aprire questo collegamento.");
    }
  }

  void timerCommand(Runnable command) {
    safe(command);
    render(true);
  }

  void startRest(JSONObject entry, String name) {
    Runnable go =
        () -> {
          timerCommand(() -> rest.start(J.id(entry), name, entry.optInt("rest")));
          askTimerPermissions();
        };
    if (rest.running() && rest.remaining() > 0 && !rest.entry().equals(J.id(entry)))
      ui.confirm(
          "Sostituire il recupero?",
          "È già attivo il recupero di "
              + rest.name()
              + ". Avviando questo terminerai il precedente.",
          go);
    else go.run();
  }

  private void askTimerPermissions() {
    if (Build.VERSION.SDK_INT >= 33
        && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
            != PackageManager.PERMISSION_GRANTED)
      requestPermissions(new String[] {Manifest.permission.POST_NOTIFICATIONS}, 40);
    else explainExact();
  }

  void explainExact() {
    if (!rest.exactAllowed() && !timerPermissionExplained) {
      timerPermissionExplained = true;
      new AlertDialog.Builder(this)
          .setTitle("Avviso a schermo bloccato")
          .setMessage(
              "Per un avviso puntuale consenti Sveglie e promemoria. Senza questo permesso Android"
                  + " può ritardare la notifica; nell’app il conto alla rovescia resta corretto.")
          .setNegativeButton("Più tardi", null)
          .setPositiveButton(
              "Impostazioni",
              (d, w) ->
                  safe(
                      () ->
                          startActivity(
                              new Intent(
                                  Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                  Uri.parse("package:" + getPackageName())))))
          .show();
    }
  }

  @Override
  public void onRequestPermissionsResult(int code, String[] permissions, int[] grants) {
    super.onRequestPermissionsResult(code, permissions, grants);
    if (code == 40) {
      if (grants.length == 0 || grants[0] != PackageManager.PERMISSION_GRANTED)
        toast("Notifiche disattivate: il timer resta visibile nell’app.");
      explainExact();
    }
  }

  void pickPhoto(Consumer<String> result) {
    photoResult = result;
    Intent i =
        new Intent(Intent.ACTION_OPEN_DOCUMENT)
            .setType("image/*")
            .addCategory(Intent.CATEGORY_OPENABLE);
    startActivityForResult(i, 41);
  }

  void export(byte[] bytes, String mime, String filename) {
    exportBytes = bytes;
    startActivityForResult(
        new Intent(Intent.ACTION_CREATE_DOCUMENT)
            .setType(mime)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .putExtra(Intent.EXTRA_TITLE, filename),
        42);
  }

  void importBackup() {
    startActivityForResult(
        new Intent(Intent.ACTION_OPEN_DOCUMENT)
            .setType("application/json")
            .addCategory(Intent.CATEGORY_OPENABLE),
        43);
  }

  @Override
  protected void onActivityResult(int request, int result, Intent intent) {
    super.onActivityResult(request, result, intent);
    if (result != RESULT_OK || intent == null || intent.getData() == null) {
      if (request == 41) photoResult = null;
      if (request == 42) exportBytes = null;
      return;
    }
    Uri uri = intent.getData();
    if (request == 41) {
      Consumer<String> callback = photoResult;
      photoResult = null;
      store.imageWorker.execute(
          () -> {
            try {
              String image = Photos.importImage(this, uri);
              runOnUiThread(
                  () -> {
                    if (callback != null) callback.accept(image);
                  });
            } catch (Exception e) {
              store.error(Store.message(e));
            }
          });
    }
    if (request == 42) {
      byte[] bytes = exportBytes;
      exportBytes = null;
      if (bytes == null) {
        error("Esportazione interrotta: ripeti l’operazione.");
        return;
      }
      store.transferWorker.execute(
          () -> {
            try (OutputStream out = getContentResolver().openOutputStream(uri, "wt")) {
              if (out == null) throw new IOException("Destinazione non disponibile");
              out.write(bytes);
              runOnUiThread(() -> toast("File esportato"));
            } catch (Exception e) {
              store.error("Esportazione non riuscita: " + Store.message(e));
            }
          });
    }
    if (request == 43)
      store.transferWorker.execute(
          () -> {
            try (InputStream in = getContentResolver().openInputStream(uri)) {
              JSONObject imported = Domain.restore(Store.read(in, Domain.MAX_BYTES));
              runOnUiThread(
                  () ->
                      ui.confirm(
                          "Ripristinare il backup?",
                          "Sostituirà schede, note, dieta, alimenti e immagini attuali. Il timer"
                              + " verrà fermato.",
                          () ->
                              store.restore(
                                  imported,
                                  () -> {
                                    rest.stop();
                                    for (Dialog dialog : new ArrayList<>(dialogs)) dialog.dismiss();
                                    planID = "";
                                    dayID = "";
                                    expandedMeals.clear();
                                    render(false);
                                    toast("Backup ripristinato");
                                  })));
            } catch (Exception e) {
              store.error("Backup non importato: " + Store.message(e));
            }
          });
  }
}
