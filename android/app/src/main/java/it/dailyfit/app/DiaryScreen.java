package it.dailyfit.app;

import android.app.AlertDialog;
import android.text.InputFilter;
import android.view.KeyEvent;
import android.widget.*;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.*;
import org.json.JSONObject;

final class DiaryScreen {
  final MainActivity a;
  final Ui u;
  EditText activeTitle, activeBody;
  JSONObject activeNote;
  String savedText = "";
  String searchText = "";
  final Runnable pending = () -> save(null);

  DiaryScreen(MainActivity activity) {
    a = activity;
    u = a.ui;
  }

  void show() {
    LinearLayout head = u.row();
    u.weighted(head, u.title("Diario"));
    head.addView(u.button("＋ Nota", () -> edit(null)));
    a.content.addView(head);
    u.hint(a.content, "Appunti liberi, indipendenti dalle schede.");
    EditText query = u.field(a.content, "Cerca nelle note", searchText, false, 1);
    RowList results = a.rowList(a.content);
    Runnable populate =
        () -> {
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          List<JSONObject> notes = J.list(J.array(a.store.data, "notes"));
          notes.sort(
              Comparator.comparingDouble((JSONObject n) -> n.optDouble("updatedAt")).reversed());
          String search = query.getText().toString().toLowerCase(Locale.ITALY);
          for (JSONObject n : notes)
            if ((n.optString("title") + " " + n.optString("body"))
                .toLowerCase(Locale.ITALY)
                .contains(search)) {
              rows.add(
                  results.item(
                      J.id(n),
                      n,
                      parent -> {
                        LinearLayout c = u.card(parent);
                        String title = n.optString("title").trim();
                        if (title.isEmpty()) {
                          String body = n.optString("body");
                          title = body.split("\n", 2)[0];
                          if (title.length() > 80) title = title.substring(0, 80);
                          if (title.isEmpty()) title = "Nuova nota";
                        }
                        c.addView(u.bold(title));
                        String body = n.optString("body");
                        u.hint(c, body.substring(0, Math.min(180, body.length())));
                        long millis = (long) ((n.optDouble("updatedAt") + 978307200) * 1000);
                        u.hint(
                            c,
                            Instant.ofEpochMilli(millis)
                                .atZone(ZoneId.systemDefault())
                                .format(
                                    DateTimeFormatter.ofPattern(
                                        "d MMM yyyy · HH:mm", Locale.ITALY)));
                        c.setOnClickListener(v -> edit(n));
                        c.setOnLongClickListener(
                            v -> {
                              u.menu(
                                  v,
                                  new String[] {"Elimina nota"},
                                  new Runnable[] {
                                    () ->
                                        u.confirm(
                                            "Eliminare la nota?",
                                            "Puoi annullare subito dopo l’eliminazione.",
                                            () ->
                                                a.store.delete(
                                                    "Nota eliminata",
                                                    d -> J.remove(J.array(d, "notes"), J.id(n)),
                                                    null))
                                  });
                              return true;
                            });
                      }));
            }
          if (rows.isEmpty())
            rows.add(
                results.item("empty", J.obj(), parent -> u.hint(parent, "Nessuna nota trovata.")));
          results.show(rows);
        };
    u.watch(
        query,
        s -> {
          searchText = s;
          populate.run();
        });
    a.refreshContent = populate;
    populate.run();
  }

  void edit(JSONObject note) {
    activeNote =
        note == null
            ? J.obj("id", J.id(), "title", "", "body", "", "updatedAt", Domain.swiftNow())
            : J.copy(note);
    LinearLayout c = u.column();
    c.setPadding(u.dp(18), u.dp(8), u.dp(18), u.dp(10));
    activeTitle = u.field(c, "Titolo · facoltativo", activeNote.optString("title"), false, 1);
    activeBody = u.field(c, "Appunti", activeNote.optString("body"), false, 12);
    activeTitle.setFilters(new InputFilter[] {new InputFilter.LengthFilter(120)});
    activeBody.setFilters(new InputFilter[] {new InputFilter.LengthFilter(200000)});
    savedText = signature();
    u.hint(c, "Salvataggio automatico sul dispositivo.");
    ScrollView scroll = new ScrollView(a);
    scroll.addView(c);
    AlertDialog dialog =
        new AlertDialog.Builder(a)
            .setTitle("Appunti")
            .setView(scroll)
            .setPositiveButton("Fine", null)
            .create();
    dialog.setCanceledOnTouchOutside(false);
    dialog.setOnShowListener(
        v ->
            dialog
                .getButton(-1)
                .setOnClickListener(
                    x ->
                        save(
                            () -> {
                              activeNote = null;
                              activeTitle = null;
                              activeBody = null;
                              dialog.dismiss();
                            })));
    dialog.setOnKeyListener(
        (d, key, event) -> {
          if (key == KeyEvent.KEYCODE_BACK && event.getAction() == KeyEvent.ACTION_UP) {
            save(
                () -> {
                  activeNote = null;
                  activeTitle = null;
                  activeBody = null;
                  dialog.dismiss();
                });
            return true;
          }
          return key == KeyEvent.KEYCODE_BACK;
        });
    u.watch(activeTitle, s -> queue());
    u.watch(activeBody, s -> queue());
    a.showDialog(dialog);
  }

  String signature() {
    return activeTitle.getText().toString() + "\u0001" + activeBody.getText().toString();
  }

  void queue() {
    a.handler.removeCallbacks(pending);
    a.handler.postDelayed(pending, 800);
  }

  void flush() {
    a.handler.removeCallbacks(pending);
    if (activeNote != null) save(null);
  }

  void save(Runnable after) {
    a.handler.removeCallbacks(pending);
    if (activeNote == null) {
      if (after != null) after.run();
      return;
    }
    String sig = signature();
    if (sig.equals(savedText)) {
      if (after != null) after.run();
      return;
    }
    JSONObject draft = J.copy(activeNote);
    J.put(draft, "title", activeTitle.getText().toString());
    J.put(draft, "body", activeBody.getText().toString());
    J.put(draft, "updatedAt", Domain.swiftNow());
    a.store.change(
        data -> J.replace(J.array(data, "notes"), draft),
        () -> {
          savedText = sig;
          if (after != null) after.run();
        });
  }
}
