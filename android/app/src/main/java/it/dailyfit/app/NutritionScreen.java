package it.dailyfit.app;

import android.app.*;
import android.view.View;
import android.widget.*;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.*;
import java.util.function.Consumer;
import org.json.*;

final class NutritionScreen {
  final MainActivity a;
  final Ui u;
  String catalogQuery = "";

  NutritionScreen(MainActivity activity) {
    a = activity;
    u = a.ui;
  }

  void changeDate(LocalDate date) {
    a.date = date;
    a.expandedMeals.clear();
    a.render(false);
  }

  void datePicker(LocalDate initial, Consumer<LocalDate> selected) {
    new DatePickerDialog(
            a,
            (v, y, m, d) -> a.safe(() -> selected.accept(LocalDate.of(y, m + 1, d))),
            initial.getYear(),
            initial.getMonthValue() - 1,
            initial.getDayOfMonth())
        .show();
  }

  void diet() {
    LinearLayout modes = u.row();
    u.weighted(modes, mode("Giorno", false));
    u.weighted(modes, mode("Dieta base", true));
    a.content.addView(modes);
    LinearLayout nav = u.row();
    nav.addView(u.button("‹", () -> changeDate(a.date.minusWeeks(1))));
    String label =
        a.base
            ? "Settimana base"
            : a.date.format(DateTimeFormatter.ofPattern("d MMMM yyyy", Locale.ITALY));
    u.weighted(nav, u.button(label, () -> datePicker(a.date, this::changeDate)));
    nav.addView(u.button("›", () -> changeDate(a.date.plusWeeks(1))));
    a.content.addView(nav);
    HorizontalScrollView weekScroll = new HorizontalScrollView(a);
    weekScroll.setHorizontalScrollBarEnabled(false);
    LinearLayout weekdays = u.row();
    LocalDate monday = a.date.minusDays(a.date.getDayOfWeek().getValue() - 1);
    for (int i = 0; i < 7; i++) {
      final LocalDate day = monday.plusDays(i);
      Button b =
          u.button(
              Domain.DAYS[i].substring(0, 3) + (a.base ? "" : "\n" + day.getDayOfMonth()),
              () -> changeDate(day));
      if (day.equals(a.date)) {
        b.setTextColor(Ui.BG);
        b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(Ui.LIME));
      }
      weekdays.addView(b, new LinearLayout.LayoutParams(u.dp(52), u.dp(54)));
    }
    weekScroll.addView(weekdays);
    a.content.addView(weekScroll);
    TextView origin = u.text("", 13, Ui.MUTED);
    a.content.addView(origin);
    RowList summary = a.rowList(a.content);
    LinearLayout actions = u.row();
    u.weighted(actions, u.button("Obiettivi base", this::goals));
    u.weighted(actions, u.button("Lista spesa", this::shopping));
    a.content.addView(actions);
    u.space(a.content, 8);
    RowList meals = a.rowList(a.content);
    meals.keepAllRows(); // Meal headers own their independently windowed food lists.
    u.action(
        a.content,
        "＋ Aggiungi spuntino",
        () ->
            u.rename(
                "Nuovo spuntino",
                "Spuntino",
                name -> {
                  LocalDate date = a.date;
                  boolean base = a.base;
                  a.store.change(
                      d ->
                          Domain.editDiet(
                              d,
                              date,
                              base,
                              diet ->
                                  J.array(diet, "meals")
                                      .put(
                                          J.obj(
                                              "id",
                                              J.id(),
                                              "name",
                                              name,
                                              "isSnack",
                                              true,
                                              "items",
                                              new JSONArray()))),
                      null);
                }));
    a.content.addView(
        u.button(
            "Copia i pasti in un altro giorno",
            () -> copyDay(Domain.diet(a.store.data, a.date, a.base))));
    Button restore =
        u.button(
            "Ripristina dieta base per questa data",
            () -> {
              LocalDate date = a.date;
              u.confirm(
                  "Ripristinare la base?",
                  "Le modifiche dei pasti del " + date + " saranno eliminate.",
                  () ->
                      a.store.delete(
                          "Giornata ripristinata",
                          d -> J.object(d, "dates").remove(date.toString()),
                          () -> a.expandedMeals.clear()));
            });
    a.content.addView(restore);

    a.refreshContent =
        () -> {
          JSONObject day = Domain.diet(a.store.data, a.date, a.base);
          boolean custom = !a.base && J.object(a.store.data, "dates").has(a.date.toString());
          origin.setText(
              a.base
                  ? "Le modifiche alla base si ripetono ogni settimana."
                  : custom
                      ? "Giornata personalizzata · la dieta base resta invariata."
                      : "Dalla dieta base · le modifiche varranno solo per questa data.");
          restore.setVisibility(custom ? View.VISIBLE : View.GONE);
          double[] values = Domain.totals(a.store.data, day);
          Double[] goals =
              Domain.targets(
                  Domain.goals(a.store.data), Domain.optional(a.store.data, "bodyWeight"));
          JSONObject totals =
              J.obj("values", Arrays.toString(values), "goals", Arrays.toString(goals));
          summary.show(
              Collections.singletonList(
                  summary.item(
                      "totals",
                      totals,
                      parent -> {
                        LinearLayout rings = u.row();
                        String[] labels = {"Kcal", "Proteine", "Grassi", "Carboidrati"};
                        int[] colors = {Ui.LIME, 0xff8acbfa, 0xffedc27b, 0xffc8acf2};
                        for (int i = 0; i < 4; i++)
                          u.weighted(rings, u.ring(labels[i], values[i], goals[i], colors[i]));
                        parent.addView(rings);
                      })));
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          for (JSONObject meal : J.list(J.array(day, "meals"))) {
            rows.add(
                meals.item(
                    J.id(meal), J.obj(), parent -> parent.setTag(new MealCard(parent, meal))));
          }
          meals.show(rows);
          for (JSONObject meal : J.list(J.array(day, "meals")))
            ((MealCard) meals.row(J.id(meal)).getTag()).refresh(meal);
        };
    a.refreshContent.run();
  }

  Button mode(String label, boolean base) {
    Button b =
        u.button(
            label,
            () -> {
              a.base = base;
              a.expandedMeals.clear();
              a.render(false);
            });
    if (a.base == base) {
      b.setTextColor(Ui.BG);
      b.setBackgroundTintList(android.content.res.ColorStateList.valueOf(Ui.LIME));
    }
    return b;
  }

  private final class MealCard {
    final String id;
    final LocalDate date = a.date;
    final boolean base = a.base;
    JSONObject meal, rendered;
    boolean open;
    final LinearLayout header;
    final TextView name, count;
    final RowList portions;

    MealCard(RowList.Row parent, JSONObject initial) {
      meal = initial;
      id = J.id(initial);
      LinearLayout card = u.card(parent);
      header = u.row();
      name = u.bold("");
      count = u.text("", 12, Ui.MUTED);
      name.setMinHeight(u.dp(48));
      name.setGravity(android.view.Gravity.CENTER_VERTICAL);
      u.weighted(header, name);
      header.addView(count);
      card.addView(header);
      portions = new RowList(a);
      card.addView(portions);
      parent.onDispose(portions::dispose);
      header.setOnClickListener(
          v -> {
            if (open) a.expandedMeals.remove(id);
            else a.expandedMeals.add(id);
            a.render(true);
          });
      header.setContentDescription(
          meal.optString("name")
              + (open ? ", espanso" : ", chiuso")
              + ". Tieni premuto per altre azioni.");
      header.setOnLongClickListener(
          v -> {
            List<String> labels = new ArrayList<>();
            List<Runnable> actions = new ArrayList<>();
            labels.add("Copia pasto");
            actions.add(() -> copyMeal(meal));
            if (meal.optBoolean("isSnack")) {
              labels.add("Rinomina spuntino");
              actions.add(
                  () ->
                      u.rename(
                          "Rinomina",
                          meal.optString("name"),
                          n ->
                              a.store.change(
                                  d ->
                                      Domain.editDiet(
                                          d,
                                          date,
                                          base,
                                          day ->
                                              J.put(J.find(J.array(day, "meals"), id), "name", n)),
                                  null)));
              labels.add("Elimina spuntino");
              actions.add(
                  () ->
                      u.confirm(
                          "Eliminare lo spuntino?",
                          "Verranno rimossi anche i cibi al suo interno.",
                          () ->
                              a.store.delete(
                                  "Spuntino eliminato",
                                  d ->
                                      Domain.editDiet(
                                          d,
                                          date,
                                          base,
                                          day -> J.remove(J.array(day, "meals"), id)),
                                  null)));
            }
            u.menu(v, labels.toArray(new String[0]), actions.toArray(new Runnable[0]));
            return true;
          });
    }

    void refresh(JSONObject current) {
      boolean expanded = a.expandedMeals.contains(id);
      JSONObject next = RenderState.meal(a.store.data, current);
      if (expanded == open && J.equal(rendered, next)) return;
      meal = current;
      open = expanded;
      rendered = next;
      name.setText(meal.optString("name") + (open ? "  ▴" : "  ▾"));
      count.setText(J.array(meal, "items").length() + " alimenti");
      header.setContentDescription(
          meal.optString("name")
              + (open ? ", espanso" : ", chiuso")
              + ". Tieni premuto per altre azioni.");
      List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
      if (open) {
        for (JSONObject item : J.list(J.array(meal, "items"))) {
          JSONObject state = J.obj("item", item, "food", Domain.food(a.store.data, item));
          rows.add(
              portions.item(J.id(item), state, parent -> portionRow(parent, id, date, base, item)));
        }
        if (rows.isEmpty())
          rows.add(
              portions.item(
                  "empty", J.obj(), parent -> u.hint(parent, "Nessun alimento inserito.")));
        rows.add(
            portions.item(
                "add",
                J.obj(),
                parent ->
                    parent.addView(u.button("＋ Aggiungi alimento", () -> portion(id, null)))));
      }
      portions.show(rows);
    }
  }

  private void portionRow(
      RowList.Row parent, String id, LocalDate date, boolean base, JSONObject item) {
    JSONObject food = Domain.food(a.store.data, item);
    LinearLayout row = u.row(), text = u.column();
    text.addView(u.bold(food.optString("name")));
    u.hint(
        text,
        Ui.fmt(item.optDouble("quantity"))
            + " "
            + food.optString("unit")
            + " · "
            + Ui.fmt(
                J.object(food, "nutrients").optDouble("kcal") * item.optDouble("quantity") / 100)
            + " kcal");
    u.weighted(row, text);
    row.addView(u.text("✎", 16, Ui.LIME));
    row.setPadding(0, u.dp(6), 0, u.dp(6));
    parent.addView(row);
    row.setOnClickListener(v -> portion(id, item));
    String itemID = J.id(item);
    row.setOnLongClickListener(
        v -> {
          u.menu(
              v,
              new String[] {"Modifica quantità", "Sposta su", "Sposta giù", "Elimina"},
              new Runnable[] {
                () -> portion(id, item),
                () ->
                    a.store.change(
                        d ->
                            Domain.editDiet(
                                d,
                                date,
                                base,
                                day ->
                                    J.move(
                                        J.array(J.find(J.array(day, "meals"), id), "items"),
                                        itemID,
                                        -1)),
                        null),
                () ->
                    a.store.change(
                        d ->
                            Domain.editDiet(
                                d,
                                date,
                                base,
                                day ->
                                    J.move(
                                        J.array(J.find(J.array(day, "meals"), id), "items"),
                                        itemID,
                                        1)),
                        null),
                () ->
                    u.confirm(
                        "Rimuovere l’alimento?",
                        food.optString("name"),
                        () ->
                            a.store.delete(
                                "Alimento rimosso",
                                d ->
                                    Domain.editDiet(
                                        d,
                                        date,
                                        base,
                                        day ->
                                            J.remove(
                                                J.array(J.find(J.array(day, "meals"), id), "items"),
                                                itemID)),
                                null))
              });
          return true;
        });
  }

  void portion(String mealID, JSONObject original) {
    LocalDate date = a.date;
    boolean base = a.base;
    LinearLayout c = u.column();
    final JSONObject[] selected = {original == null ? null : Domain.food(a.store.data, original)};
    TextView selectedLabel =
        u.bold(selected[0] == null ? "Scegli un alimento" : selected[0].optString("name"));
    c.addView(selectedLabel);
    if (original == null) {
      EditText search = u.field(c, "Cerca nel catalogo", "", false, 1);
      Spinner foods = new Spinner(a);
      ArrayAdapter<String> foodAdapter =
          new ArrayAdapter<>(a, android.R.layout.simple_spinner_dropdown_item, new ArrayList<>());
      foods.setAdapter(foodAdapter);
      List<JSONObject> choices = new ArrayList<>();
      c.addView(foods, new LinearLayout.LayoutParams(-1, u.dp(52)));
      Runnable filter =
          () -> {
            choices.clear();
            List<String> names = new ArrayList<>();
            for (JSONObject f : J.list(J.array(a.store.data, "foods")))
              if (!f.optBoolean("archived")
                  && f.optString("name")
                      .toLowerCase(Locale.ITALY)
                      .contains(search.getText().toString().toLowerCase(Locale.ITALY))) {
                choices.add(f);
                names.add(f.optString("name") + " (" + f.optString("unit") + ")");
              }
            foodAdapter.setNotifyOnChange(false);
            foodAdapter.clear();
            foodAdapter.addAll(names);
            foodAdapter.notifyDataSetChanged();
            if (!choices.isEmpty()) foods.setSelection(0);
            selected[0] = choices.isEmpty() ? null : choices.get(0);
            selectedLabel.setText(
                selected[0] == null ? "Nessun alimento trovato" : selected[0].optString("name"));
          };
      foods.setOnItemSelectedListener(
          new AdapterView.OnItemSelectedListener() {
            public void onItemSelected(AdapterView<?> p, View v, int pos, long id) {
              if (pos < choices.size()) {
                selected[0] = choices.get(pos);
                selectedLabel.setText(
                    selected[0].optString("name")
                        + " · quantità in "
                        + selected[0].optString("unit"));
              }
            }

            public void onNothingSelected(AdapterView<?> p) {
              selected[0] = null;
            }
          });
      u.watch(search, s -> filter.run());
      filter.run();
    }
    EditText qty =
        u.field(
            c,
            original == null ? "Quantità in g" : "Quantità in " + selected[0].optString("unit"),
            original == null ? "100" : Ui.edit(original.opt("quantity")),
            true,
            1);
    u.editor(
        original == null ? "Aggiungi alimento" : "Modifica quantità",
        c,
        dialog -> {
          Domain.require(selected[0] != null, "Seleziona un alimento dal catalogo.");
          double amount =
              Domain.number(qty.getText().toString(), "Quantità", 0.000001, 100000, false);
          JSONObject item =
              original == null
                  ? J.obj("id", J.id(), "foodID", J.id(selected[0]), "quantity", amount)
                  : J.copy(original);
          J.put(item, "quantity", amount);
          if (!base && original == null) J.put(item, "snapshot", J.copy(selected[0]));
          a.store.change(
              d ->
                  Domain.editDiet(
                      d,
                      date,
                      base,
                      day ->
                          J.replace(J.array(J.find(J.array(day, "meals"), mealID), "items"), item)),
              dialog::dismiss);
        });
  }

  void goals() {
    JSONObject current = Domain.goals(a.store.data);
    LinearLayout c = u.column();
    u.hint(
        c,
        "Un unico obiettivo della dieta base vale per tutti i giorni. Kcal e macro sono"
            + " indipendenti.");
    EditText
        weight = u.field(c, "Peso corporeo (kg)", Ui.edit(a.store.data.opt("bodyWeight")), true, 1),
        kcal = u.field(c, "Kcal al giorno", Ui.edit(current.opt("kcal")), true, 1),
        protein = u.field(c, "Proteine (g/kg)", Ui.edit(current.opt("proteinPerKg")), true, 1),
        fat = u.field(c, "Grassi (g/kg)", Ui.edit(current.opt("fatPerKg")), true, 1),
        carbs = u.field(c, "Carboidrati (g/kg)", Ui.edit(current.opt("carbsPerKg")), true, 1);
    TextView preview = u.text("", 13, Ui.LIME);
    c.addView(preview);
    Runnable update =
        () -> {
          try {
            Double w = Domain.number(weight.getText().toString(), "Peso", 0.01, 500, true);
            JSONObject g = parseGoals(kcal, protein, fat, carbs);
            Double[] t = Domain.targets(g, w);
            preview.setText(
                "Proteine: "
                    + (t[1] == null ? "—" : Ui.fmt(t[1]) + " g")
                    + "\nGrassi: "
                    + (t[2] == null ? "—" : Ui.fmt(t[2]) + " g")
                    + "\nCarboidrati: "
                    + (t[3] == null ? "—" : Ui.fmt(t[3]) + " g"));
          } catch (Exception e) {
            preview.setText(e.getMessage());
          }
        };
    for (EditText f : new EditText[] {weight, kcal, protein, fat, carbs})
      u.watch(f, s -> update.run());
    update.run();
    u.editor(
        "Obiettivi della dieta base",
        c,
        dialog -> {
          Double w = Domain.number(weight.getText().toString(), "Peso", 0.01, 500, true);
          JSONObject g = parseGoals(kcal, protein, fat, carbs);
          Domain.targets(g, w);
          a.store.change(d -> Domain.setGoals(d, g, w), dialog::dismiss);
        });
  }

  JSONObject parseGoals(EditText k, EditText p, EditText f, EditText c) {
    return J.obj(
        "kcal",
        Domain.number(k.getText().toString(), "Kcal", 0, Double.MAX_VALUE, true),
        "proteinPerKg",
        Domain.number(p.getText().toString(), "Proteine", 0, Double.MAX_VALUE, true),
        "fatPerKg",
        Domain.number(f.getText().toString(), "Grassi", 0, Double.MAX_VALUE, true),
        "carbsPerKg",
        Domain.number(c.getText().toString(), "Carboidrati", 0, Double.MAX_VALUE, true));
  }

  void chooseDestination(Consumer<LocalDate> action) {
    if (a.base)
      new AlertDialog.Builder(a)
          .setTitle("Giorno base di destinazione")
          .setItems(
              Domain.DAYS,
              (d, w) ->
                  action.accept(a.date.minusDays(a.date.getDayOfWeek().getValue() - 1).plusDays(w)))
          .show();
    else datePicker(a.date.plusDays(1), action);
  }

  void copyDay(JSONObject source) {
    JSONObject snapshot = J.copy(source);
    boolean base = a.base;
    chooseDestination(
        date ->
            u.confirm(
                "Copiare i pasti?",
                "I pasti di "
                    + (base ? Domain.DAYS[date.getDayOfWeek().getValue() - 1] : date.toString())
                    + " saranno sostituiti. Gli obiettivi restano quelli della dieta base.",
                () ->
                    a.store.change(
                        d -> Domain.copyMeals(d, snapshot, date, base),
                        () -> a.toast("Pasti copiati"))));
  }

  void copyMeal(JSONObject source) {
    JSONObject snapshot = J.copy(source);
    boolean base = a.base;
    chooseDestination(
        date -> {
          List<JSONObject> meals = J.list(J.array(Domain.diet(a.store.data, date, base), "meals"));
          String[] labels = meals.stream().map(m -> m.optString("name")).toArray(String[]::new);
          new AlertDialog.Builder(a)
              .setTitle("Pasto di destinazione")
              .setItems(
                  labels,
                  (dialog, which) -> {
                    String id = J.id(meals.get(which));
                    u.confirm(
                        "Copiare il pasto?",
                        "I cibi di " + labels[which] + " saranno sostituiti.",
                        () ->
                            a.store.change(
                                d -> {
                                  JSONArray items =
                                      Domain.copyItems(d, J.array(snapshot, "items"), base);
                                  Domain.editDiet(
                                      d,
                                      date,
                                      base,
                                      day ->
                                          J.put(J.find(J.array(day, "meals"), id), "items", items));
                                },
                                () -> a.toast("Pasto copiato")));
                  })
              .show();
        });
  }

  void foods() {
    LinearLayout head = u.row();
    u.weighted(head, u.title("Alimenti"));
    head.addView(u.button("＋ Nuovo", () -> editFood(null)));
    a.content.addView(head);
    a.content.addView(u.button("Peso e obiettivi base", this::goals));
    u.hint(a.content, "Valori per 100 g. Le quantità nei pasti vengono calcolate automaticamente.");
    EditText query = u.field(a.content, "Cerca alimento", catalogQuery, false, 1);
    RowList list = a.rowList(a.content);
    Runnable populate =
        () -> {
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          for (JSONObject f : J.list(J.array(a.store.data, "foods")))
            if (!f.optBoolean("archived")
                && f.optString("name")
                    .toLowerCase(Locale.ITALY)
                    .contains(query.getText().toString().toLowerCase(Locale.ITALY))) {
              rows.add(
                  list.item(
                      J.id(f),
                      f,
                      parent -> {
                        LinearLayout c = u.card(parent);
                        c.addView(u.bold(f.optString("name")));
                        JSONObject n = J.object(f, "nutrients");
                        u.hint(
                            c,
                            Ui.fmt(n.optDouble("kcal"))
                                + " kcal / 100 "
                                + f.optString("unit")
                                + "\nP "
                                + Ui.fmt(n.optDouble("protein"))
                                + " · G "
                                + Ui.fmt(n.optDouble("fat"))
                                + " · C "
                                + Ui.fmt(n.optDouble("carbs")));
                        c.setOnClickListener(v -> editFood(f));
                        c.setOnLongClickListener(
                            v -> {
                              u.menu(
                                  v,
                                  new String[] {"Modifica", "Elimina dal catalogo"},
                                  new Runnable[] {
                                    () -> editFood(f),
                                    () ->
                                        u.confirm(
                                            "Eliminare l’alimento?",
                                            "I pasti già compilati conserveranno i suoi valori.",
                                            () ->
                                                a.store.delete(
                                                    "Alimento eliminato",
                                                    d -> Domain.deleteFood(d, J.id(f)),
                                                    null))
                                  });
                              return true;
                            });
                      }));
            }
          if (rows.isEmpty())
            rows.add(
                list.item("empty", J.obj(), parent -> u.hint(parent, "Nessun alimento trovato.")));
          list.show(rows);
        };
    u.watch(
        query,
        s -> {
          catalogQuery = s;
          populate.run();
        });
    a.refreshContent = populate;
    populate.run();
  }

  void editFood(JSONObject original) {
    JSONObject draft =
        original == null
            ? J.obj(
                "id",
                J.id(),
                "name",
                "",
                "unit",
                "g",
                "nutrients",
                J.obj("kcal", 0, "protein", 0, "fat", 0, "carbs", 0),
                "source",
                "Inserito dall’utente",
                "sourceURL",
                "",
                "archived",
                false)
            : J.copy(original);
    LinearLayout c = u.column();
    EditText name = u.field(c, "Nome alimento", draft.optString("name"), false, 1);
    u.hint(c, "Valori nutrizionali riferiti a 100 g, anche per gli alimenti liquidi.");
    JSONObject n = J.object(draft, "nutrients");
    EditText[] fields = new EditText[4];
    String[] labels = {"Kcal", "Proteine (g)", "Grassi (g)", "Carboidrati (g)"};
    for (int i = 0; i < 4; i++)
      fields[i] = u.field(c, labels[i], Ui.edit(n.opt(Domain.MACROS[i])), true, 1);
    u.hint(c, draft.optString("source"));
    if (!draft.optString("sourceURL").isEmpty())
      c.addView(u.button("Fonte dei valori ↗", () -> a.open(draft.optString("sourceURL"))));
    u.editor(
        original == null ? "Nuovo alimento" : "Modifica alimento",
        c,
        dialog -> {
          J.put(draft, "name", Domain.text(name.getText().toString(), "Nome", 100, true));
          J.put(draft, "unit", "g");
          JSONObject nutrients = new JSONObject();
          for (int i = 0; i < 4; i++)
            J.put(
                nutrients,
                Domain.MACROS[i],
                Domain.number(fields[i].getText().toString(), labels[i], 0, 10000, false));
          if (original != null
              && (!nutrients.toString().equals(J.object(original, "nutrients").toString())
                  || !draft.optString("unit").equals(original.optString("unit")))) {
            J.put(draft, "source", "Valori modificati dall’utente");
            J.put(draft, "sourceURL", "");
          }
          J.put(draft, "nutrients", nutrients);
          Domain.validateFood(draft);
          a.store.change(d -> J.replace(J.array(d, "foods"), J.copy(draft)), dialog::dismiss);
        });
  }

  void shopping() {
    LinearLayout c = u.column();
    c.setPadding(u.dp(18), u.dp(10), u.dp(18), u.dp(10));
    u.hint(
        c,
        "Quantità dei sette giorni della dieta base. Le modifiche per singola data sono escluse.");
    Switch grouped = new Switch(a);
    grouped.setText("Dividi per pasto");
    grouped.setChecked(true);
    c.addView(grouped);
    RowList results = new RowList(a);
    c.addView(results);
    Runnable show =
        () -> {
          List<KeyedRows.Item<RowList.Row>> rows = new ArrayList<>();
          String group = "";
          List<JSONObject> items = Domain.shopping(a.store.data, grouped.isChecked());
          for (JSONObject item : items) {
            if (!group.equals(item.optString("group"))) {
              group = item.optString("group");
              String title = group;
              rows.add(
                  results.item(
                      "group/" + group,
                      J.obj("title", group),
                      parent -> {
                        u.space(parent, 10);
                        parent.addView(u.bold(title));
                      }));
            }
            String key =
                "item/" + group + "/" + item.optString("foodID") + "/" + item.optString("unit");
            rows.add(
                results.item(
                    key,
                    item,
                    parent ->
                        parent.addView(
                            u.text(
                                item.optString("name")
                                    + "\n"
                                    + Ui.fmt(item.optDouble("quantity"))
                                    + " "
                                    + item.optString("unit"),
                                15,
                                Ui.WHITE))));
          }
          if (items.isEmpty())
            rows.add(
                results.item(
                    "empty",
                    J.obj(),
                    parent ->
                        u.hint(parent, "Aggiungi alimenti alla dieta base per creare la lista.")));
          results.show(rows);
        };
    grouped.setOnCheckedChangeListener((v, b) -> show.run());
    show.run();
    ScrollView scroll = new ScrollView(a);
    scroll.addView(c);
    a.showDialog(
        new AlertDialog.Builder(a)
            .setTitle("Lista della spesa")
            .setView(scroll)
            .setPositiveButton("Chiudi", null)
            .create());
  }
}
