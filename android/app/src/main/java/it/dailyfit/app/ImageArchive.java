package it.dailyfit.app;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.*;
import org.json.JSONObject;

/**
 * Photo references shared by the legacy v2 envelope and v3 SQLite records. Backups keep the
 * original self-contained format. This codec is testable without Android.
 */
final class ImageArchive {
  interface Blobs {
    byte[] read(String name) throws IOException;

    default long size(String name) throws IOException {
      return read(name).length;
    }

    void writeIfAbsent(String name, byte[] bytes) throws IOException;

    void removeExcept(Set<String> names) throws IOException;
  }

  static final class Packed {
    final byte[] bytes;
    final JSONObject envelope;
    final long imageCharacters;
    final Set<String> files;
    final IdentityHashMap<String, String> keys;

    Packed(
        byte[] bytes,
        JSONObject envelope,
        Set<String> files,
        IdentityHashMap<String, String> keys,
        long imageCharacters) {
      this.bytes = bytes;
      this.envelope = envelope;
      this.imageCharacters = imageCharacters;
      this.files = files;
      this.keys = keys;
    }
  }

  private final Blobs blobs;
  private IdentityHashMap<String, String> imageKeys = new IdentityHashMap<>();
  private Set<String> committedFiles = new HashSet<>();

  ImageArchive(Blobs blobs) {
    this.blobs = blobs;
  }

  static boolean isLocal(JSONObject object) {
    return object.has("storageFormat");
  }

  JSONObject unpack(JSONObject stored) throws IOException {
    if (!isLocal(stored)) return stored;
    return materialize(references(stored));
  }

  static final String LOCAL = "local:";

  static boolean isReference(String value) {
    return value.startsWith(LOCAL);
  }

  byte[] readImage(String value) throws IOException {
    if (!isReference(value)) return Base64.getDecoder().decode(value);
    String name = value.substring(LOCAL.length());
    checkName(name);
    byte[] bytes = blobs.read(name);
    Domain.require(
        bytes.length > 0 && bytes.length <= 2_000_000 && name.equals(digest(bytes) + ".bin"),
        "Immagine locale mancante o danneggiata.");
    return bytes;
  }

  JSONObject materialize(JSONObject snapshot) throws IOException {
    JSONObject result = copyExerciseMetadata(snapshot);
    for (JSONObject exercise : J.list(J.array(result, "exercises"))) {
      for (String field : new String[] {"photo", "musclePhoto"}) {
        String value = exercise.optString(field, "");
        if (isReference(value))
          J.put(exercise, field, Base64.getEncoder().encodeToString(readImage(value)));
      }
    }
    return result;
  }

  /** Only metadata and file sizes are read at startup. Hashes are checked on image access. */
  JSONObject references(JSONObject stored) throws IOException {
    return references(stored, 0);
  }

  JSONObject references(JSONObject stored, long metadataBytes) throws IOException {
    if (!isLocal(stored)) return stored; // Legacy data-v1.json: migrate after validation.
    Domain.require(
        stored.optString("storageFormat").equals("DailyFitLocal")
            && stored.optInt("storageVersion") == 2,
        "Archivio locale non compatibile.");
    JSONObject data = copyExerciseMetadata(J.object(stored, "data")),
        images = J.object(stored, "images");
    for (JSONObject exercise : J.list(J.array(data, "exercises")))
      Domain.require(
          exercise.isNull("photo") && exercise.isNull("musclePhoto"),
          "Metadati immagini locali non validi.");
    IdentityHashMap<String, String> keys = new IdentityHashMap<>();
    Set<String> used = new HashSet<>();
    long size = metadataBytes;
    for (String id : Domain.keys(images)) {
      JSONObject exercise = J.find(J.array(data, "exercises"), id), refs = J.object(images, id);
      for (String field : Domain.keys(refs)) {
        Domain.require(
            field.equals("photo") || field.equals("musclePhoto"),
            "Riferimento immagine non valido.");
        String name = refs.optString(field);
        checkName(name);
        long count = blobs.size(name);
        Domain.require(count > 0 && count <= 2_000_000, "Immagine locale mancante o danneggiata.");
        String value = LOCAL + name;
        size += ((count + 2) / 3) * 4;
        Domain.require(size <= Domain.MAX_BYTES, "Archivio troppo grande.");
        J.put(exercise, field, value);
        keys.put(value, name);
        used.add(name);
      }
    }
    imageKeys = keys;
    committedFiles = used;
    return data;
  }

  Packed pack(JSONObject data) throws IOException {
    return prepare(data, true);
  }

  Packed prepare(JSONObject data) throws IOException {
    return prepare(data, false);
  }

  private Packed prepare(JSONObject data, boolean serialize) throws IOException {
    JSONObject metadata = copyExerciseMetadata(data), images = new JSONObject();
    IdentityHashMap<String, String> next = new IdentityHashMap<>();
    Set<String> used = new HashSet<>();
    long pictureCharacters = 0;
    for (JSONObject exercise : J.list(J.array(metadata, "exercises"))) {
      JSONObject refs = new JSONObject();
      for (String field : new String[] {"photo", "musclePhoto"}) {
        if (!exercise.isNull(field)) {
          String value = exercise.optString(field), name = imageKeys.get(value);
          if (isReference(value)) {
            name = value.substring(LOCAL.length());
            checkName(name);
          }
          if (name == null) {
            byte[] bytes = Base64.getDecoder().decode(value);
            Domain.require(
                bytes.length > 0 && bytes.length <= 2_000_000, "Immagine troppo grande.");
            name = digest(bytes) + ".bin";
            blobs.writeIfAbsent(name, bytes);
          }
          next.put(value, name);
          used.add(name);
          J.put(refs, field, name);
          long count = blobs.size(name);
          Domain.require(count > 0 && count <= 2_000_000, "Immagine locale mancante.");
          pictureCharacters += ((count + 2) / 3) * 4;
        }
        if (!exercise.isNull(field)) exercise.remove(field);
      }
      if (refs.length() > 0) J.put(images, J.id(exercise), refs);
    }
    JSONObject stored =
        J.obj(
            "storageFormat",
            "DailyFitLocal",
            "storageVersion",
            2,
            "data",
            metadata,
            "images",
            images);
    byte[] bytes = serialize ? stored.toString().getBytes(StandardCharsets.UTF_8) : new byte[0];
    Domain.require(bytes.length + pictureCharacters <= Domain.MAX_BYTES, "Archivio troppo grande.");
    return new Packed(bytes, stored, used, next, pictureCharacters);
  }

  boolean committed(Packed packed) {
    boolean changed = !committedFiles.equals(packed.files);
    committedFiles = new HashSet<>(packed.files);
    imageKeys = packed.keys;
    return changed;
  }

  void cleanup() throws IOException {
    blobs.removeExcept(new HashSet<>(committedFiles));
  }

  static void checkName(String name) {
    Domain.require(name.matches("[0-9a-f]{64}\\.bin"), "Percorso immagine non valido.");
  }

  private static JSONObject copyExerciseMetadata(JSONObject data) {
    JSONObject copy = new JSONObject();
    for (String key : Domain.keys(data)) J.put(copy, key, data.opt(key));
    org.json.JSONArray exercises = new org.json.JSONArray();
    for (JSONObject exercise : J.list(J.array(data, "exercises"))) exercises.put(J.copy(exercise));
    J.put(copy, "exercises", exercises);
    return copy;
  }

  static String digest(byte[] data) {
    try {
      byte[] hash = MessageDigest.getInstance("SHA-256").digest(data);
      StringBuilder result = new StringBuilder(64);
      for (byte value : hash) result.append(String.format(Locale.ROOT, "%02x", value & 255));
      return result.toString();
    } catch (java.security.NoSuchAlgorithmException impossible) {
      throw new IllegalStateException(impossible);
    }
  }
}
