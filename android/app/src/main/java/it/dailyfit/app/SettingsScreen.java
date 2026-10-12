package it.dailyfit.app;

import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.widget.*;
import java.time.LocalDate;
import org.json.JSONObject;

final class SettingsScreen {
  final MainActivity a;
  final Ui u;

  SettingsScreen(MainActivity activity) {
    a = activity;
    u = a.ui;
  }

  void show() {
    LinearLayout c = u.column();
    c.setPadding(u.dp(18), u.dp(12), u.dp(18), u.dp(12));
    c.addView(u.bold("Dati sul dispositivo"));
    u.hint(
        c,
        "Nessun account, sincronizzazione o invio automatico. Il backup manuale include le"
            + " immagini; scegli tu dove salvare la copia.");
    c.addView(u.button("Esporta backup JSON", () -> prepareExport(false)));
    c.addView(u.button("Ripristina backup JSON", a::importBackup));
    c.addView(u.button("Esporta Excel per Google Fogli", () -> prepareExport(true)));
    u.hint(c, "Excel è una copia per consultazione. Per ripristinare l’app usa il JSON.");
    u.space(c, 12);
    c.addView(u.bold("Allenamento"));
    Switch awake = new Switch(a);
    awake.setText("Tieni acceso lo schermo nella giornata");
    awake.setTextColor(Ui.WHITE);
    awake.setChecked(a.store.data.optBoolean("keepScreenAwake"));
    awake.setOnCheckedChangeListener(
        (v, on) -> a.store.change(d -> J.put(d, "keepScreenAwake", on), a::awake));
    c.addView(awake);
    c.addView(
        u.button(
            "Impostazioni notifiche",
            () ->
                a.startActivity(
                    new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, a.getPackageName()))));
    if (Build.VERSION.SDK_INT >= 31)
      c.addView(
          u.button(
              "Permesso sveglie e promemoria",
              () ->
                  a.startActivity(
                      new Intent(
                          Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                          Uri.parse("package:" + a.getPackageName())))));
    u.hint(
        c,
        "Per l’avviso puntuale con schermo bloccato abilita notifiche e sveglie/promemoria. Nessun"
            + " servizio resta attivo in background. Dopo un riavvio del telefono riapri l’app per"
            + " riallineare un recupero ancora in corso.");
    u.space(c, 12);
    c.addView(u.button("Collegamento ChatGPT", this::chat));
    u.hint(
        c,
        "DailyFit · Android 1.3.0\n"
            + "15 esercizi e immagini forniti dall’utente. Alimenti iniziali: CREA, Tabelle 2019,"
            + " valori per 100 g. Carichi e recuperi della scheda sono da personalizzare.");
    ScrollView scroll = new ScrollView(a);
    scroll.addView(c);
    a.showDialog(
        new AlertDialog.Builder(a)
            .setTitle("Impostazioni")
            .setView(scroll)
            .setPositiveButton("Chiudi", null)
            .create());
  }

  void chat() {
    LinearLayout c = u.column();
    EditText link =
        u.field(c, "Indirizzo privato della chat", a.store.data.optString("chatLink"), false, 1);
    u.hint(
        c,
        "Lascia vuoto per aprire ChatGPT. Per una chat dedicata usa https://chatgpt.com/c/ seguito"
            + " dall’ID. Apriamo prima l’app ChatGPT senza inviarle un link: scegli la chat dalla"
            + " sua cronologia. Se l’app non si apre, usiamo il link nel browser. Schede, dieta e"
            + " note non vengono inviate.");
    u.editor(
        "ChatGPT",
        c,
        dialog -> {
          String url = Domain.web(link.getText().toString(), true);
          a.store.change(d -> J.put(d, "chatLink", url), dialog::dismiss);
        });
  }

  void prepareExport(boolean excel) {
    a.toast("Preparazione del file…");
    JSONObject snapshot = a.store.data;
    a.store.transferWorker.execute(
        () -> {
          try {
            byte[] bytes =
                excel
                    ? ExcelExport.encode(snapshot)
                    : Domain.backup(a.store.withEmbeddedImages(snapshot));
            a.runOnUiThread(
                () ->
                    a.export(
                        bytes,
                        excel
                            ? "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
                            : "application/json",
                        "DailyFit-" + LocalDate.now() + (excel ? ".xlsx" : ".json")));
          } catch (Exception e) {
            a.store.error(Store.message(e));
          }
        });
  }
}
