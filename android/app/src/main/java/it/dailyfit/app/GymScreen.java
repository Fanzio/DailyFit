package it.dailyfit.app;

import android.app.AlertDialog;
import android.graphics.Typeface;
import android.view.Gravity;
import android.view.View;
import android.widget.*;
import java.util.*;
import org.json.JSONArray;
import org.json.JSONObject;

final class GymScreen {
  final MainActivity a;
  final Ui u;
  String catalogQuery = "", catalogGroup = "Tutti";

  GymScreen(MainActivity a) {
    this.a = a;
    u = a.ui;
  }

  void plans() {
    JSONObject plan = J.findOrNull(J.array(a.store.data, "plans"), a.planID);
    if (plan == null) {
      a.planID = "";
      a.dayID = "";
    } else if (!a.dayID.isEmpty()) {
      JSONObject day = J.findOrNull(J.array(plan, "days"), a.dayID);
      if (day != null) {
        training(plan, day);
        return;
      }
      a.dayID = "";
    }
    if (plan != null) {
      days(plan);
      return;
    }
    a.content.addView(u.bold("Le tue schede"));
    u.space(a.content, 12);
    RowList list = a.rowList(a.content);
    a.refreshContent =
        () -> {
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          for (JSONObject p : J.list(J.array(a.store.data, "plans"))) {
            JSONObject state =
                J.obj("name", p.optString("name"), "count", J.array(p, "days").length());
            rows.add(
                list.item(
                    J.id(p),
                    state,
                    parent -> {
                      LinearLayout card = u.card(parent);
                      card.addView(u.bold(p.optString("name")));
                      u.hint(card, J.array(p, "days").length() + " giornate  ›");
                      card.setOnClickListener(
                          v -> {
                            a.planID = J.id(p);
                            a.render(false);
                          });
                      card.setOnLongClickListener(
                          v -> {
                            planMenu(v, p);
                            return true;
                          });
                    }));
          }
          if (rows.isEmpty())
            rows.add(
                list.item(
                    "empty",
                    J.obj(),
                    parent -> u.hint(parent, "Crea una scheda e aggiungi le tue giornate.")));
          list.show(rows);
        };
    a.refreshContent.run();
    u.action(
        a.content,
        "＋ Crea una scheda",
        () ->
            u.rename(
                "Nuova scheda",
                "",
                name ->
                    a.store.change(
                        d ->
                            J.array(d, "plans")
                                .put(J.obj("id", J.id(), "name", name, "days", new JSONArray())),
                        null)));
  }

  void planMenu(View anchor, JSONObject p) {
    String id = J.id(p);
    u.menu(
        anchor,
        new String[] {"Rinomina", "Duplica", "Sposta su", "Sposta giù", "Elimina"},
        new Runnable[] {
          () ->
              u.rename(
                  "Rinomina scheda",
                  p.optString("name"),
                  name -> a.store.change(d -> J.put(Domain.plan(d, id), "name", name), null)),
          () ->
              u.rename(
                  "Duplica scheda",
                  copyName(p.optString("name")),
                  name ->
                      a.store.change(
                          d -> {
                            JSONObject c = Domain.duplicate(Domain.plan(d, id), "days");
                            J.put(c, "name", name);
                            J.array(d, "plans").put(c);
                          },
                          null)),
          () -> a.store.change(d -> J.move(J.array(d, "plans"), id, -1), null),
          () -> a.store.change(d -> J.move(J.array(d, "plans"), id, 1), null),
          () ->
              u.confirm(
                  "Eliminare la scheda?",
                  p.optString("name") + " e tutte le sue giornate verranno eliminate.",
                  () ->
                      a.store.delete(
                          "Scheda eliminata", d -> J.remove(J.array(d, "plans"), id), null))
        });
  }

  static String copyName(String s) {
    return s.substring(0, Math.min(72, s.length())) + " · copia";
  }

  void days(JSONObject p) {
    a.content.addView(
        u.button(
            "‹ Tutte le schede",
            () -> {
              a.planID = "";
              a.render(false);
            }));
    TextView heading = u.title(p.optString("name"));
    a.content.addView(heading);
    u.space(a.content, 12);
    String pid = J.id(p);
    RowList list = a.rowList(a.content);
    a.refreshContent =
        () -> {
          JSONObject current = Domain.plan(a.store.data, pid);
          heading.setText(current.optString("name"));
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          for (JSONObject day : J.list(J.array(current, "days"))) {
            JSONObject state =
                J.obj("name", day.optString("name"), "count", J.array(day, "entries").length());
            rows.add(
                list.item(
                    J.id(day),
                    state,
                    parent -> {
                      LinearLayout c = u.card(parent);
                      c.addView(u.bold(day.optString("name")));
                      u.hint(c, J.array(day, "entries").length() + " esercizi  ›");
                      String id = J.id(day);
                      c.setOnClickListener(
                          v -> {
                            a.dayID = id;
                            a.render(false);
                          });
                      c.setOnLongClickListener(
                          v -> {
                            u.menu(
                                v,
                                new String[] {
                                  "Rinomina", "Duplica", "Sposta su", "Sposta giù", "Elimina"
                                },
                                new Runnable[] {
                                  () ->
                                      u.rename(
                                          "Rinomina giornata",
                                          day.optString("name"),
                                          n ->
                                              a.store.change(
                                                  d -> J.put(Domain.day(d, pid, id), "name", n),
                                                  null)),
                                  () ->
                                      u.rename(
                                          "Duplica giornata",
                                          copyName(day.optString("name")),
                                          n ->
                                              a.store.change(
                                                  d -> {
                                                    JSONObject cp =
                                                        Domain.duplicate(
                                                            Domain.day(d, pid, id), "entries");
                                                    J.put(cp, "name", n);
                                                    J.array(Domain.plan(d, pid), "days").put(cp);
                                                  },
                                                  null)),
                                  () ->
                                      a.store.change(
                                          d -> J.move(J.array(Domain.plan(d, pid), "days"), id, -1),
                                          null),
                                  () ->
                                      a.store.change(
                                          d -> J.move(J.array(Domain.plan(d, pid), "days"), id, 1),
                                          null),
                                  () ->
                                      u.confirm(
                                          "Eliminare la giornata?",
                                          day.optString("name"),
                                          () ->
                                              a.store.delete(
                                                  "Giornata eliminata",
                                                  d ->
                                                      J.remove(
                                                          J.array(Domain.plan(d, pid), "days"), id),
                                                  null))
                                });
                            return true;
                          });
                    }));
          }
          list.show(rows);
        };
    a.refreshContent.run();
    u.action(
        a.content,
        "＋ Aggiungi giornata",
        () ->
            u.rename(
                "Nuova giornata",
                "",
                n ->
                    a.store.change(
                        d ->
                            J.array(Domain.plan(d, pid), "days")
                                .put(J.obj("id", J.id(), "name", n, "entries", new JSONArray())),
                        null)));
  }

  void training(JSONObject p, JSONObject day) {
    String pid = J.id(p), did = J.id(day);
    Button back =
        u.button(
            "‹ " + p.optString("name"),
            () -> {
              a.dayID = "";
              a.render(false);
            });
    TextView heading = u.title(day.optString("name"));
    a.content.addView(back);
    a.content.addView(heading);
    u.space(a.content, 12);
    RowList list = a.rowList(a.content);
    a.refreshContent =
        () -> {
          JSONObject currentPlan = Domain.plan(a.store.data, pid);
          JSONObject currentDay = Domain.day(a.store.data, pid, did);
          back.setText("‹ " + currentPlan.optString("name"));
          heading.setText(currentDay.optString("name"));
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          for (JSONObject entry : J.list(J.array(currentDay, "entries"))) {
            JSONObject state =
                J.obj(
                    "entry",
                    entry,
                    "exercise",
                    Domain.exercise(a.store.data, entry.optString("exerciseID")));
            rows.add(
                list.item(J.id(entry), state, parent -> trainingEntry(parent, pid, did, entry)));
          }
          list.show(rows);
        };
    a.refreshContent.run();
    u.action(
        a.content,
        "＋ Aggiungi esercizio",
        () ->
            pickExercise(
                id ->
                    a.store.change(
                        d -> J.array(Domain.day(d, pid, did), "entries").put(Domain.newEntry(id)),
                        null)));
    u.hint(a.content, "Tieni premuto un esercizio per riordinarlo o rimuoverlo.");
  }

  private void trainingEntry(RowList.Row parent, String pid, String did, JSONObject entry) {
    JSONObject ex = Domain.exercise(a.store.data, entry.optString("exerciseID"));
    String eid = J.id(entry), name = Domain.entryName(a.store.data, entry);
    LinearLayout c = u.card(parent), header = u.row();
    u.weighted(header, u.bold(name));
    header.addView(u.button("Modifica", () -> editSets(pid, did, entry)));
    c.addView(header);
    LinearLayout body = u.row(), picture = u.column();
    picture.setGravity(Gravity.CENTER);
    ImageView image = a.photos.view(a, ex, "photo", false);
    picture.addView(image, new LinearLayout.LayoutParams(u.dp(64), u.dp(64)));
    TextView details = u.text("Dettagli ↗", 10, Ui.LIME);
    picture.addView(details);
    picture.setContentDescription("Dettagli di " + ex.optString("name"));
    picture.setOnClickListener(v -> detail(ex));
    body.addView(picture, new LinearLayout.LayoutParams(u.dp(74), -2));
    LinearLayout table = u.column();
    LinearLayout labels = u.row();
    boolean seconds = true;
    for (JSONObject set : J.list(J.array(entry, "sets")))
      if (!set.optString("unit").equals("seconds")) seconds = false;
    for (String label : new String[] {"SERIE", seconds ? "DURATA" : "RIP.", "CARICO"}) {
      TextView t = u.text(label, 10, Ui.MUTED);
      t.setGravity(Gravity.CENTER);
      u.weighted(labels, t);
    }
    table.addView(labels);
    int index = 0;
    for (JSONObject set : J.list(J.array(entry, "sets"))) {
      LinearLayout row = u.row();
      for (String value :
          new String[] {
            "" + (++index), Domain.displayTarget(set), Ui.fmt(set.optDouble("load")) + " kg"
          }) {
        TextView t = u.text(value, 14, Ui.WHITE);
        t.setGravity(Gravity.CENTER);
        u.weighted(row, t);
      }
      table.addView(row);
    }
    u.weighted(body, table);
    c.addView(body);
    u.space(c, 8);
    View line = new View(a);
    line.setBackgroundColor(0xff343d30);
    c.addView(line, new LinearLayout.LayoutParams(-1, u.dp(1)));
    LinearLayout timer = u.row();
    TextView time = u.text("", 14, Ui.WHITE);
    time.setTypeface(null, Typeface.BOLD);
    time.setMinHeight(u.dp(48));
    time.setGravity(Gravity.CENTER_VERTICAL);
    time.setOnClickListener(v -> editRest(pid, did, eid, entry.optInt("rest")));
    u.weighted(timer, time);
    Button toggle =
        u.button(
            "Avvia",
            () -> {
              if (a.rest.entry().equals(eid)) a.timerCommand(a.rest::toggle);
              else a.startRest(entry, name);
            });
    timer.addView(toggle);
    timer.addView(u.button("↻", () -> a.startRest(entry, name)));
    c.addView(timer);
    Runnable tick =
        () -> {
          boolean active = a.rest.entry().equals(eid);
          time.setText(
              "Recupero ✎\n" + Ui.clock(active ? a.rest.remaining() : entry.optInt("rest")));
          toggle.setText(
              active && a.rest.running()
                  ? "Pausa"
                  : active && a.rest.remaining() > 0 ? "Riprendi" : "Avvia");
        };
    tick.run();
    a.ticks.add(tick);
    parent.onDispose(() -> a.ticks.remove(tick));
    View.OnLongClickListener menu =
        v -> {
          u.menu(
              v,
              new String[] {"Modifica serie", "Sposta su", "Sposta giù", "Elimina"},
              new Runnable[] {
                () -> editSets(pid, did, entry),
                () ->
                    a.store.change(
                        d -> J.move(J.array(Domain.day(d, pid, did), "entries"), eid, -1), null),
                () ->
                    a.store.change(
                        d -> J.move(J.array(Domain.day(d, pid, did), "entries"), eid, 1), null),
                () ->
                    u.confirm(
                        "Rimuovere dalla giornata?",
                        name + " resterà nel catalogo.",
                        () ->
                            a.store.delete(
                                "Esercizio rimosso",
                                d -> J.remove(J.array(Domain.day(d, pid, did), "entries"), eid),
                                null))
              });
          return true;
        };
    c.setOnLongClickListener(menu);
    table.setOnLongClickListener(menu);
  }

  void editRest(String p, String d, String e, int seconds) {
    LinearLayout c = u.column();
    EditText f = u.field(c, "Recupero in secondi", String.valueOf(seconds), true, 1);
    u.editor(
        "Recupero",
        c,
        dialog -> {
          int n = Domain.integer(f.getText().toString(), "Recupero", 1, 3600);
          a.store.change(
              data -> J.put(J.find(J.array(Domain.day(data, p, d), "entries"), e), "rest", n),
              dialog::dismiss);
        });
  }

  static final class SetRow {
    JSONObject original;
    EditText target, load;
    LinearLayout view;
    Runnable updateLabels;
    int number;
    boolean seconds;
  }

  void editSets(String pid, String did, JSONObject entry) {
    LinearLayout c = u.column(), rows = u.column();
    List<SetRow> draft = new ArrayList<>();
    EditText alias =
        u.field(
            c, "Nome nella giornata · facoltativo", entry.optString("nameOverride", ""), false, 1);
    c.addView(rows);
    final Runnable[] redraw = new Runnable[1];
    redraw[0] =
        () -> {
          int index = 0;
          for (SetRow row : draft) {
            row.number = ++index;
            if (row.view == null) {
              LinearLayout block = u.column(), labels = u.row(), line = u.row();
              // Labels share one row and values another: font size or menu height cannot
              // move the repetitions field below the load field.
              labels.setBaselineAligned(false);
              line.setBaselineAligned(false);
              TextView num = u.text("" + row.number, 14, Ui.MUTED);
              num.setGravity(Gravity.CENTER);
              num.setContentDescription("Serie " + row.number);
              line.addView(num, new LinearLayout.LayoutParams(u.dp(24), u.dp(48)));
              labels.addView(new View(a), new LinearLayout.LayoutParams(u.dp(24), 1));
              LinearLayout targetCol = u.column(), loadCol = u.column();
              String
                  target =
                      row.target == null
                          ? Domain.target(row.original)
                          : row.target.getText().toString(),
                  load =
                      row.load == null
                          ? Ui.edit(row.original.opt("load"))
                          : row.load.getText().toString();
              row.target = u.field(targetCol, "", target, false, 1);
              row.load = u.field(loadCol, "", load, true, 1);
              row.target.setSingleLine(true);
              row.load.setSingleLine(true);
              row.target.setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
              row.load.setGravity(Gravity.CENTER_VERTICAL | Gravity.START);
              row.load.setContentDescription("Carico in kg, serie " + row.number);
              Button unit = u.button("", () -> {});
              Runnable refreshUnit =
                  () -> {
                    unit.setText(row.seconds ? "Sec. ▾" : "Rip. ▾");
                    unit.setContentDescription(
                        "Unità serie "
                            + row.number
                            + ": "
                            + (row.seconds ? "Secondi" : "Ripetizioni")
                            + ". Tocca per cambiare.");
                    row.target.setContentDescription(
                        (row.seconds ? "Secondi" : "Ripetizioni")
                            + " o intervallo, serie "
                            + row.number);
                  };
              unit.setOnClickListener(
                  v ->
                      u.menu(
                          unit,
                          new String[] {"Ripetizioni", "Secondi"},
                          new Runnable[] {
                            () -> {
                              row.seconds = false;
                              refreshUnit.run();
                            },
                            () -> {
                              row.seconds = true;
                              refreshUnit.run();
                            }
                          }));
              u.weighted(labels, unit);
              labels.addView(new View(a), new LinearLayout.LayoutParams(u.dp(10), 1));
              TextView loadLabel = u.text("Carico kg", 12, Ui.MUTED);
              u.weighted(labels, loadLabel);
              labels.addView(new View(a), new LinearLayout.LayoutParams(u.dp(48), 1));
              u.weighted(line, targetCol);
              line.addView(new View(a), new LinearLayout.LayoutParams(u.dp(10), 1));
              u.weighted(line, loadCol);
              Button remove =
                  u.button(
                      "−",
                      () -> {
                        if (draft.size() == 1) {
                          a.toast("Mantieni almeno una serie");
                          return;
                        }
                        rows.removeView(row.view);
                        draft.remove(row);
                        redraw[0].run();
                      });
              remove.setContentDescription("Rimuovi serie " + row.number);
              line.addView(remove, new LinearLayout.LayoutParams(u.dp(48), u.dp(48)));
              // All controls line up with the fields, without the usual form's bottom margin.
              ((LinearLayout.LayoutParams) row.target.getLayoutParams()).bottomMargin = 0;
              ((LinearLayout.LayoutParams) row.load.getLayoutParams()).bottomMargin = 0;
              block.addView(labels);
              block.addView(line);
              u.space(block, 10);
              row.view = block;
              row.updateLabels =
                  () -> {
                    num.setText(String.valueOf(row.number));
                    num.setContentDescription("Serie " + row.number);
                    row.load.setContentDescription("Carico in kg, serie " + row.number);
                    remove.setContentDescription("Rimuovi serie " + row.number);
                    refreshUnit.run();
                  };
              rows.addView(block);
            }
            row.updateLabels.run();
          }
        };
    for (JSONObject set : J.list(J.array(entry, "sets"))) {
      SetRow r = new SetRow();
      r.original = J.copy(set);
      r.seconds = set.optString("unit").equals("seconds");
      draft.add(r);
    }
    redraw[0].run();
    c.addView(
        u.button(
            "＋ Serie",
            () -> {
              if (draft.size() >= 30) {
                a.toast("Massimo 30 serie");
                return;
              }
              SetRow r = new SetRow();
              r.original = Domain.newSet();
              draft.add(r);
              redraw[0].run();
            }));
    EditText rest = u.field(c, "Recupero (secondi)", "" + entry.optInt("rest"), true, 1);
    u.editor(
        "Serie e carichi",
        c,
        dialog -> {
          JSONArray sets = new JSONArray();
          for (SetRow r : draft) {
            JSONObject s = J.copy(r.original);
            Domain.setTarget(
                s, r.target.getText().toString(), r.seconds ? "seconds" : "repetitions");
            J.put(s, "load", Domain.number(r.load.getText().toString(), "Carico", 0, 2000, false));
            sets.put(s);
          }
          int seconds = Domain.integer(rest.getText().toString(), "Recupero", 1, 3600);
          String n = Domain.text(alias.getText().toString(), "Nome", 80, false);
          a.store.change(
              data -> {
                JSONObject e = J.find(J.array(Domain.day(data, pid, did), "entries"), J.id(entry));
                J.put(e, "sets", sets);
                J.put(e, "rest", seconds);
                J.put(e, "nameOverride", n.isEmpty() ? null : n);
              },
              dialog::dismiss);
        });
  }

  void pickExercise(java.util.function.Consumer<String> pick) {
    LinearLayout c = u.column();
    EditText query = u.field(c, "Cerca esercizio", "", false, 1);
    RowList results = new RowList(a);
    c.addView(results);
    ScrollView scroll = new ScrollView(a);
    scroll.addView(c);
    AlertDialog dialog =
        new AlertDialog.Builder(a)
            .setTitle("Catalogo esercizi")
            .setView(scroll)
            .setNegativeButton("Chiudi", null)
            .create();
    Runnable populate =
        () -> {
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          for (JSONObject ex : J.list(J.array(a.store.data, "exercises")))
            if (!ex.optBoolean("archived")
                && ex.optString("name")
                    .toLowerCase(Locale.ITALY)
                    .contains(query.getText().toString().toLowerCase(Locale.ITALY)))
              rows.add(
                  results.item(
                      J.id(ex),
                      ex,
                      parent ->
                          parent.addView(
                              u.button(
                                  ex.optString("name"),
                                  () -> {
                                    pick.accept(J.id(ex));
                                    dialog.dismiss();
                                  }))));
          results.show(rows);
        };
    u.watch(query, s -> populate.run());
    populate.run();
    a.showDialog(dialog);
  }

  void catalog() {
    LinearLayout head = u.row();
    u.weighted(head, u.title("Esercizi"));
    head.addView(u.button("＋ Nuovo", () -> editExercise(null, null)));
    a.content.addView(head);
    EditText search = u.field(a.content, "Cerca esercizio", catalogQuery, false, 1);
    String[] groups = new String[Domain.GROUPS.length + 1];
    groups[0] = "Tutti";
    System.arraycopy(Domain.GROUPS, 0, groups, 1, Domain.GROUPS.length);
    Spinner filter = u.select(a.content, "Gruppo muscolare", groups, catalogGroup);
    RowList list = a.rowList(a.content);
    Runnable populate =
        () -> {
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          for (JSONObject ex : J.list(J.array(a.store.data, "exercises")))
            if (!ex.optBoolean("archived")
                && ex.optString("name")
                    .toLowerCase(Locale.ITALY)
                    .contains(search.getText().toString().toLowerCase(Locale.ITALY))
                && (filter.getSelectedItemPosition() == 0
                    || ex.optString("muscle").equals(filter.getSelectedItem().toString()))) {
              rows.add(
                  list.item(
                      J.id(ex),
                      ex,
                      parent -> {
                        LinearLayout c = u.card(parent), row = u.row();
                        row.addView(
                            a.photos.view(a, ex, "photo", false),
                            new LinearLayout.LayoutParams(u.dp(64), u.dp(64)));
                        LinearLayout text = u.column();
                        text.setPadding(u.dp(12), 0, 0, 0);
                        text.addView(u.bold(ex.optString("name")));
                        u.hint(text, ex.optString("muscle"));
                        u.weighted(row, text);
                        c.addView(row);
                        c.setOnClickListener(v -> detail(ex));
                        c.setOnLongClickListener(
                            v -> {
                              u.menu(
                                  v,
                                  new String[] {"Modifica", "Elimina dal catalogo"},
                                  new Runnable[] {
                                    () -> editExercise(ex, null),
                                    () ->
                                        u.confirm(
                                            "Eliminare dal catalogo?",
                                            "Gli inserimenti nelle schede conserveranno"
                                                + " l’esercizio.",
                                            () ->
                                                a.store.delete(
                                                    "Esercizio eliminato",
                                                    d ->
                                                        J.put(
                                                            Domain.exercise(d, J.id(ex)),
                                                            "archived",
                                                            true),
                                                    null))
                                  });
                              return true;
                            });
                      }));
            }
          if (rows.isEmpty())
            rows.add(
                list.item("empty", J.obj(), parent -> u.hint(parent, "Nessun esercizio trovato.")));
          list.show(rows);
        };
    u.watch(
        search,
        s -> {
          catalogQuery = s;
          populate.run();
        });
    filter.setOnItemSelectedListener(
        new AdapterView.OnItemSelectedListener() {
          public void onItemSelected(AdapterView<?> p, View v, int pos, long id) {
            catalogGroup = filter.getSelectedItem().toString();
            populate.run();
          }

          public void onNothingSelected(AdapterView<?> p) {}
        });
    a.refreshContent = populate;
    populate.run();
  }

  void detail(JSONObject ex) {
    LinearLayout c = u.column();
    c.setPadding(u.dp(18), u.dp(8), u.dp(18), u.dp(12));
    u.hint(c, ex.optString("muscle"));
    c.addView(a.photos.view(a, ex, "photo", true), new LinearLayout.LayoutParams(-1, u.dp(210)));
    c.addView(u.bold("Come eseguirlo"));
    c.addView(u.text(ex.optString("execution"), 15, Ui.WHITE));
    if (!ex.isNull("musclePhoto")) {
      c.addView(u.bold("Muscoli coinvolti"));
      c.addView(
          a.photos.view(a, ex, "musclePhoto", true), new LinearLayout.LayoutParams(-1, u.dp(210)));
    }
    c.addView(u.bold("Video dimostrativo"));
    if (ex.optString("video").isEmpty()) u.hint(c, "Nessun video inserito.");
    else c.addView(u.button("Apri video ↗", () -> a.open(ex.optString("video"))));
    ScrollView scroll = new ScrollView(a);
    scroll.addView(c);
    AlertDialog d =
        new AlertDialog.Builder(a)
            .setTitle(ex.optString("name"))
            .setView(scroll)
            .setNegativeButton("Chiudi", null)
            .setPositiveButton("Modifica", (x, w) -> editExercise(ex, null))
            .create();
    a.showDialog(d);
  }

  void editExercise(JSONObject original, Runnable after) {
    JSONObject draft =
        original == null
            ? J.obj(
                "id",
                J.id(),
                "name",
                "",
                "muscle",
                "Altro",
                "execution",
                "",
                "video",
                "",
                "archived",
                false)
            : J.copy(original);
    LinearLayout c = u.column();
    EditText name = u.field(c, "Nome", draft.optString("name"), false, 1);
    Spinner muscle = u.select(c, "Gruppo muscolare", Domain.GROUPS, draft.optString("muscle"));
    photoEditor(c, draft, "photo", "Immagine esecuzione");
    photoEditor(c, draft, "musclePhoto", "Immagine muscoli");
    EditText
        execution =
            u.field(c, "Descrizione dell’esecuzione", draft.optString("execution"), false, 4),
        video = u.field(c, "Link video · facoltativo", draft.optString("video"), false, 1);
    u.editor(
        original == null ? "Nuovo esercizio" : "Modifica esercizio",
        c,
        dialog -> {
          J.put(draft, "name", Domain.text(name.getText().toString(), "Nome", 80, true));
          J.put(draft, "muscle", muscle.getSelectedItem().toString());
          J.put(
              draft,
              "execution",
              Domain.text(execution.getText().toString(), "Esecuzione", 3000, false));
          J.put(draft, "video", Domain.web(video.getText().toString(), false));
          Domain.validateExercise(draft);
          a.store.change(
              d -> J.replace(J.array(d, "exercises"), J.copy(draft)),
              () -> {
                dialog.dismiss();
                if (after != null) after.run();
              });
        });
  }

  void photoEditor(LinearLayout c, JSONObject draft, String key, String label) {
    LinearLayout preview = u.column();
    c.addView(preview);
    Runnable refresh =
        () -> {
          preview.removeAllViews();
          u.hint(preview, label + " · facoltativa");
          preview.addView(
              a.photos.view(a, draft, key, false),
              new LinearLayout.LayoutParams(u.dp(72), u.dp(72)));
        };
    refresh.run();
    LinearLayout buttons = u.row();
    u.weighted(
        buttons,
        u.button(
            "Scegli immagine",
            () ->
                a.pickPhoto(
                    image -> {
                      J.put(draft, key, image);
                      refresh.run();
                    })));
    u.weighted(
        buttons,
        u.button(
            "Rimuovi",
            () -> {
              draft.remove(key);
              refresh.run();
            }));
    c.addView(buttons);
  }
}
