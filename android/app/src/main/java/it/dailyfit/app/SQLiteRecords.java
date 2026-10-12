package it.dailyfit.app;

import android.database.Cursor;
import android.database.sqlite.*;
import java.io.File;
import java.util.*;

/** One connection, owned exclusively by Store.worker. A batch is one durable transaction. */
final class SQLiteRecords {
  private final File file;
  private SQLiteDatabase database;

  SQLiteRecords(File file) {
    this.file = file;
  }

  private SQLiteDatabase db() {
    if (database != null) return database;
    SQLiteDatabase opened =
        SQLiteDatabase.openOrCreateDatabase(
            file.getPath(),
            null,
            corrupted -> {
              throw new SQLiteDatabaseCorruptException(
                  "Database non leggibile: i file sono stati conservati.");
            });
    try {
      int version = opened.getVersion();
      Domain.require(version == 0 || version == 3, "Database di una versione non supportata.");
      opened.enableWriteAheadLogging();
      opened.execSQL("PRAGMA synchronous=FULL");
      if (version == 0) {
        opened.beginTransaction();
        try {
          opened.execSQL(
              "CREATE TABLE records (key TEXT PRIMARY KEY NOT NULL, value BLOB NOT NULL)");
          opened.setVersion(3);
          opened.setTransactionSuccessful();
        } finally {
          opened.endTransaction();
        }
      }
      database = opened;
      return opened;
    } catch (RuntimeException error) {
      opened.close();
      throw error;
    }
  }

  Map<String, byte[]> read() {
    Map<String, byte[]> result = new LinkedHashMap<>();
    long total = 0;
    try (Cursor cursor = db().rawQuery("SELECT key,value FROM records", null)) {
      while (cursor.moveToNext()) {
        byte[] bytes = cursor.getBlob(1);
        total += bytes.length;
        Domain.require(
            total <= Domain.MAX_BYTES && result.size() < 200000, "Database troppo grande.");
        result.put(cursor.getString(0), bytes);
      }
    }
    return result;
  }

  void apply(RecordArchive.Delta delta) {
    if (delta.empty()) return;
    SQLiteDatabase db = db();
    db.beginTransaction();
    try (SQLiteStatement write =
            db.compileStatement("INSERT OR REPLACE INTO records(key,value) VALUES(?,?)");
        SQLiteStatement remove = db.compileStatement("DELETE FROM records WHERE key=?")) {
      for (Map.Entry<String, byte[]> row : delta.writes.entrySet()) {
        write.bindString(1, row.getKey());
        write.bindBlob(2, row.getValue());
        write.executeInsert();
        write.clearBindings();
      }
      for (String key : delta.deletes) {
        remove.bindString(1, key);
        remove.executeUpdateDelete();
        remove.clearBindings();
      }
      db.setTransactionSuccessful();
    } finally {
      db.endTransaction();
    }
  }
}
