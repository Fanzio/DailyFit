package it.dailyfit.app;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;
import org.json.*;

/** Minimal OOXML workbook. User strings are inline strings, never executable formulas. */
public final class ExcelExport {
  private ExcelExport() {}

  static final class Sheet {
    final String name;
    final List<Object[]> rows = new ArrayList<>();

    Sheet(String name, String... headers) {
      this.name = name;
      rows.add(headers);
    }

    void add(Object... values) {
      rows.add(values);
    }
  }

  public static byte[] encode(JSONObject data) throws IOException {
    Domain.validate(data);
    List<Sheet> sheets = sheets(data);
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    try (ZipOutputStream zip = new ZipOutputStream(out)) {
      String ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main",
          rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
      StringBuilder types =
          new StringBuilder(
              "<Types"
                  + " xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default"
                  + " Extension=\"rels\""
                  + " ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default"
                  + " Extension=\"xml\" ContentType=\"application/xml\"/><Override"
                  + " PartName=\"/xl/workbook.xml\""
                  + " ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>");
      StringBuilder book =
          new StringBuilder("<workbook xmlns=\"" + ns + "\" xmlns:r=\"" + rel + "\"><sheets>");
      StringBuilder refs =
          new StringBuilder(
              "<Relationships"
                  + " xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">");
      int index = 0;
      for (Sheet sheet : sheets) {
        int id = ++index;
        types
            .append("<Override PartName=\"/xl/worksheets/sheet")
            .append(id)
            .append(
                ".xml\""
                    + " ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>");
        book.append("<sheet name=\"")
            .append(xml(sheet.name))
            .append("\" sheetId=\"")
            .append(id)
            .append("\" r:id=\"rId")
            .append(id)
            .append("\"/>");
        refs.append("<Relationship Id=\"rId")
            .append(id)
            .append("\" Type=\"")
            .append(rel)
            .append("/worksheet\" Target=\"worksheets/sheet")
            .append(id)
            .append(".xml\"/>");
        StringBuilder body =
            new StringBuilder(
                "<worksheet xmlns=\""
                    + ns
                    + "\"><sheetViews><sheetView workbookViewId=\"0\"><pane ySplit=\"1\""
                    + " topLeftCell=\"A2\" activePane=\"bottomLeft\""
                    + " state=\"frozen\"/></sheetView></sheetViews><sheetData>");
        int row = 0;
        for (Object[] cells : sheet.rows) {
          int r = ++row;
          Domain.require(r <= 1048576, "Troppi dati per un foglio Excel.");
          body.append("<row r=\"").append(r).append("\">");
          int col = 0;
          for (Object value : cells) {
            String coordinate = column(++col) + r;
            if (value == null || value == JSONObject.NULL) continue;
            if (value instanceof Number) {
              double n = ((Number) value).doubleValue();
              Domain.require(Double.isFinite(n), "Numero non esportabile.");
              body.append("<c r=\"")
                  .append(coordinate)
                  .append("\"><v>")
                  .append(value)
                  .append("</v></c>");
            } else {
              String text = value.toString();
              Domain.require(text.length() <= 32767, "Testo troppo lungo per una cella Excel.");
              body.append("<c r=\"")
                  .append(coordinate)
                  .append("\" t=\"inlineStr\"><is><t xml:space=\"preserve\">")
                  .append(xml(text))
                  .append("</t></is></c>");
            }
          }
          body.append("</row>");
        }
        body.append("</sheetData></worksheet>");
        entry(zip, "xl/worksheets/sheet" + id + ".xml", body.toString());
      }
      entry(zip, "[Content_Types].xml", types + "</Types>");
      entry(zip, "xl/workbook.xml", book + "</sheets></workbook>");
      entry(zip, "xl/_rels/workbook.xml.rels", refs + "</Relationships>");
      entry(
          zip,
          "_rels/.rels",
          "<Relationships"
              + " xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship"
              + " Id=\"office\" Type=\""
              + rel
              + "/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>");
    }
    return out.toByteArray();
  }

  static List<Sheet> sheets(JSONObject d) {
    Sheet summary = new Sheet("Riepilogo", "Contenuto", "Quantità / indicazione");
    summary.add("Schede", J.array(d, "plans").length());
    summary.add("Esercizi, inclusi archiviati", J.array(d, "exercises").length());
    summary.add("Alimenti, inclusi archiviati", J.array(d, "foods").length());
    summary.add("Note diario", J.array(d, "notes").length());
    summary.add(
        "Ripristino",
        "Usa il backup JSON, che conserva anche le immagini. Excel è una copia per consultazione.");
    summary.add("Note lunghe", "Suddivise in parti consecutive senza perdere testo.");
    Sheet goals =
        new Sheet(
            "Obiettivi base",
            "Peso (kg)",
            "Kcal/giorno",
            "Proteine (g/kg)",
            "Grassi (g/kg)",
            "Carboidrati (g/kg)",
            "Proteine (g/giorno)",
            "Grassi (g/giorno)",
            "Carboidrati (g/giorno)");
    JSONObject g = Domain.goals(d);
    Double weight = Domain.optional(d, "bodyWeight");
    Double[] targets = Domain.targets(g, weight);
    goals.add(
        weight,
        targets[0],
        g.opt("proteinPerKg"),
        g.opt("fatPerKg"),
        g.opt("carbsPerKg"),
        targets[1],
        targets[2],
        targets[3]);
    Sheet plans = new Sheet("Schede", "ID scheda", "Ordine", "Scheda", "Giornate"),
        days =
            new Sheet(
                "Giornate palestra",
                "ID scheda",
                "Scheda",
                "ID giornata",
                "Ordine",
                "Giornata",
                "Esercizi"),
        sets =
            new Sheet(
                "Serie",
                "Scheda",
                "Giornata",
                "Ordine esercizio",
                "ID esercizio",
                "Esercizio",
                "Serie",
                "Valore minimo",
                "Carico (kg)",
                "Recupero (secondi)",
                "ID scheda",
                "ID giornata",
                "ID inserimento",
                "ID serie",
                "Valore massimo",
                "Unità");
    int pi = 0;
    for (JSONObject p : J.list(J.array(d, "plans"))) {
      plans.add(J.id(p), ++pi, p.optString("name"), J.array(p, "days").length());
      int di = 0;
      for (JSONObject day : J.list(J.array(p, "days"))) {
        days.add(
            J.id(p),
            p.optString("name"),
            J.id(day),
            ++di,
            day.optString("name"),
            J.array(day, "entries").length());
        int ei = 0;
        for (JSONObject e : J.list(J.array(day, "entries"))) {
          ei++;
          int si = 0;
          for (JSONObject s : J.list(J.array(e, "sets")))
            sets.add(
                p.optString("name"),
                day.optString("name"),
                ei,
                e.optString("exerciseID"),
                Domain.entryName(d, e),
                ++si,
                s.optInt("reps"),
                s.optDouble("load"),
                e.optInt("rest"),
                J.id(p),
                J.id(day),
                J.id(e),
                J.id(s),
                s.opt("upperReps"),
                s.optString("unit").equals("seconds") ? "Secondi" : "Ripetizioni");
        }
      }
    }
    Sheet exercises =
        new Sheet(
            "Esercizi",
            "ID esercizio",
            "Nome",
            "Gruppo muscolare",
            "Parte descrizione",
            "Esecuzione",
            "Link video",
            "Immagine",
            "Immagine muscoli",
            "Archiviato");
    for (JSONObject e : J.list(J.array(d, "exercises"))) {
      int part = 0;
      for (String chunk : chunks(e.optString("execution")))
        exercises.add(
            J.id(e),
            e.optString("name"),
            e.optString("muscle"),
            ++part,
            chunk,
            e.optString("video"),
            e.isNull("photo") ? "No" : "Nel backup JSON",
            e.isNull("musclePhoto") ? "No" : "Nel backup JSON",
            e.optBoolean("archived") ? "Sì" : "No");
    }
    Sheet notes =
        new Sheet("Diario", "ID nota", "Titolo", "Ultima modifica (UTC)", "Parte", "Testo");
    for (JSONObject n : J.list(J.array(d, "notes"))) {
      int part = 0;
      String date =
          Instant.ofEpochMilli((long) ((n.optDouble("updatedAt") + 978307200) * 1000)).toString();
      for (String chunk : chunks(n.optString("body")))
        notes.add(J.id(n), n.optString("title"), date, ++part, chunk);
    }
    Sheet foods =
        new Sheet(
            "Alimenti",
            "ID alimento",
            "Alimento",
            "Unità per 100",
            "Kcal",
            "Proteine (g)",
            "Grassi (g)",
            "Carboidrati (g)",
            "Fonte",
            "Link fonte",
            "Archiviato");
    for (JSONObject f : J.list(J.array(d, "foods"))) {
      JSONObject n = J.object(f, "nutrients");
      foods.add(
          J.id(f),
          f.optString("name"),
          f.optString("unit"),
          n.optDouble("kcal"),
          n.optDouble("protein"),
          n.optDouble("fat"),
          n.optDouble("carbs"),
          f.optString("source"),
          f.optString("sourceURL"),
          f.optBoolean("archived") ? "Sì" : "No");
    }
    Sheet
        diet =
            new Sheet(
                "Dieta",
                "Tipo",
                "Giorno",
                "Data",
                "Ordine pasto",
                "Pasto",
                "Spuntino",
                "ID alimento",
                "Alimento",
                "Quantità",
                "Unità",
                "Kcal porzione",
                "Proteine (g)",
                "Grassi (g)",
                "Carboidrati (g)",
                "Fonte",
                "Link fonte",
                "ID pasto",
                "ID porzione"),
        totals =
            new Sheet(
                "Totali dieta",
                "Tipo",
                "Giorno",
                "Data",
                "Kcal",
                "Proteine (g)",
                "Grassi (g)",
                "Carboidrati (g)");
    int i = 0;
    for (JSONObject day : J.list(J.array(d, "week")))
      dietRows(d, day, "Base", Domain.DAYS[i++], null, diet, totals);
    JSONObject dates = J.object(d, "dates");
    for (String key : Domain.keys(dates))
      dietRows(d, J.object(dates, key), "Personalizzata", key, key, diet, totals);
    Sheet settings = new Sheet("Impostazioni", "Impostazione", "Valore");
    settings.add("ChatGPT", d.optString("chatLink"));
    settings.add(
        "Schermo acceso durante allenamento", d.optBoolean("keepScreenAwake") ? "Sì" : "No");
    return Arrays.asList(
        summary, goals, plans, days, sets, exercises, notes, foods, diet, totals, settings);
  }

  private static void dietRows(
      JSONObject data,
      JSONObject day,
      String kind,
      String label,
      String date,
      Sheet diet,
      Sheet totals) {
    double[] n = Domain.totals(data, day);
    totals.add(kind, label, date, n[0], n[1], n[2], n[3]);
    int mi = 0;
    for (JSONObject m : J.list(J.array(day, "meals"))) {
      mi++;
      JSONArray items = J.array(m, "items");
      if (items.length() == 0)
        diet.add(
            kind,
            label,
            date,
            mi,
            m.optString("name"),
            m.optBoolean("isSnack") ? "Sì" : "No",
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            null,
            J.id(m),
            null);
      for (JSONObject item : J.list(items)) {
        JSONObject f = Domain.food(data, item), v = J.object(f, "nutrients");
        double factor = item.optDouble("quantity") / 100;
        diet.add(
            kind,
            label,
            date,
            mi,
            m.optString("name"),
            m.optBoolean("isSnack") ? "Sì" : "No",
            J.id(f),
            f.optString("name"),
            item.optDouble("quantity"),
            f.optString("unit"),
            v.optDouble("kcal") * factor,
            v.optDouble("protein") * factor,
            v.optDouble("fat") * factor,
            v.optDouble("carbs") * factor,
            f.optString("source"),
            f.optString("sourceURL"),
            J.id(m),
            J.id(item));
      }
    }
  }

  static List<String> chunks(String text) {
    List<String> out = new ArrayList<>();
    for (int start = 0; start < text.length(); ) {
      int end = Math.min(start + 1000, text.length());
      if (end < text.length() && Character.isHighSurrogate(text.charAt(end - 1))) end--;
      out.add(text.substring(start, end));
      start = end;
    }
    if (out.isEmpty()) out.add("");
    return out;
  }

  static String xml(String value) {
    StringBuilder out = new StringBuilder();
    value
        .codePoints()
        .filter(
            c ->
                c == 9
                    || c == 10
                    || c == 13
                    || (c >= 32 && c <= 0xd7ff)
                    || (c >= 0xe000 && c <= 0xfffd)
                    || (c >= 0x10000 && c <= 0x10ffff))
        .forEach(out::appendCodePoint);
    return out.toString()
        .replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\"", "&quot;")
        .replace("'", "&apos;");
  }

  static String column(int n) {
    String s = "";
    while (n > 0) {
      n--;
      s = (char) ('A' + n % 26) + s;
      n /= 26;
    }
    return s;
  }

  static void entry(ZipOutputStream zip, String name, String body) throws IOException {
    zip.putNextEntry(new ZipEntry(name));
    zip.write(
        ("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" + body)
            .getBytes(StandardCharsets.UTF_8));
    zip.closeEntry();
  }
}
