package it.dailyfit.app;

import android.content.Context;
import android.graphics.*;
import android.media.ExifInterface;
import android.net.Uri;
import android.util.LruCache;
import android.widget.ImageView;
import java.io.*;
import java.util.Base64;
import org.json.JSONObject;

public final class Photos {
  private final LruCache<String, Bitmap> cache =
      new LruCache<String, Bitmap>(12 * 1024 * 1024) {
        @Override
        protected int sizeOf(String k, Bitmap b) {
          return b.getByteCount();
        }
      };

  public ImageView view(MainActivity a, JSONObject exercise, String key, boolean large) {
    ImageView v = new ImageView(a);
    v.setScaleType(ImageView.ScaleType.FIT_CENTER);
    v.setAdjustViewBounds(true);
    v.setContentDescription(
        (key.equals("photo") ? "Esecuzione di " : "Muscoli di ") + exercise.optString("name"));
    String image = exercise.optString(key, "");
    String identity =
        ImageArchive.isReference(image)
            ? image
            : ImageArchive.digest(image.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    String cacheKey = identity + "/" + large;
    v.setImageResource(R.drawable.ic_launcher);
    v.addOnAttachStateChangeListener(
        new android.view.View.OnAttachStateChangeListener() {
          private java.util.concurrent.Future<?> pending;
          private int generation;

          @Override
          public void onViewAttachedToWindow(android.view.View ignored) {
            int request = ++generation;
            v.setImageResource(R.drawable.ic_launcher);
            Bitmap cached = cache.get(cacheKey);
            if (cached != null) {
              v.setImageBitmap(cached);
              return;
            }
            if (image.isEmpty()) return;
            pending =
                a.store.imageWorker.submit(
                    () -> {
                      try {
                        if (Thread.currentThread().isInterrupted()) return;
                        Bitmap bitmap = decode(a.store.readImage(image), large ? 1600 : 192);
                        if (Thread.currentThread().isInterrupted()) return;
                        cache.put(cacheKey, bitmap);
                        a.runOnUiThread(
                            () -> {
                              if (generation == request && v.isAttachedToWindow())
                                v.setImageBitmap(bitmap);
                            });
                      } catch (Exception error) {
                        a.runOnUiThread(
                            () -> {
                              if (generation == request && v.isAttachedToWindow()) {
                                v.setImageResource(android.R.drawable.ic_dialog_alert);
                                v.setContentDescription(
                                    "Immagine non disponibile: " + exercise.optString("name"));
                              }
                            });
                      }
                    });
          }

          @Override
          public void onViewDetachedFromWindow(android.view.View ignored) {
            generation++;
            if (pending != null) pending.cancel(true);
            pending = null;
            v.setImageDrawable(null);
          }
        });
    return v;
  }

  void clearMemory() {
    cache.evictAll();
  }

  static Bitmap decode(byte[] bytes, int max) throws IOException {
    BitmapFactory.Options bounds = new BitmapFactory.Options();
    bounds.inJustDecodeBounds = true;
    BitmapFactory.decodeByteArray(bytes, 0, bytes.length, bounds);
    if (bounds.outWidth < 1
        || bounds.outHeight < 1
        || (long) bounds.outWidth * bounds.outHeight > 80_000_000)
      throw new IOException("Immagine non valida o troppo grande.");
    BitmapFactory.Options options = new BitmapFactory.Options();
    options.inSampleSize = 1;
    while (Math.max(bounds.outWidth, bounds.outHeight) / options.inSampleSize > max * 2)
      options.inSampleSize *= 2;
    Bitmap result = BitmapFactory.decodeByteArray(bytes, 0, bytes.length, options);
    if (result == null) throw new IOException("Immagine non leggibile.");
    return result;
  }

  public static String importImage(Context context, Uri uri) throws IOException {
    byte[] bytes;
    try (InputStream in = context.getContentResolver().openInputStream(uri)) {
      bytes = Store.read(in, 25_000_000);
    }
    Bitmap b = decode(bytes, 1600);
    Matrix m = new Matrix();
    ExifInterface exif = new ExifInterface(new ByteArrayInputStream(bytes));
    int orientation =
        exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
    switch (orientation) {
      case 2:
        m.setScale(-1, 1);
        break;
      case 3:
        m.setRotate(180);
        break;
      case 4:
        m.setScale(1, -1);
        break;
      case 5:
        m.setRotate(90);
        m.postScale(-1, 1);
        break;
      case 6:
        m.setRotate(90);
        break;
      case 7:
        m.setRotate(-90);
        m.postScale(-1, 1);
        break;
      case 8:
        m.setRotate(-90);
        break;
    }
    if (!m.isIdentity()) b = Bitmap.createBitmap(b, 0, 0, b.getWidth(), b.getHeight(), m, true);
    float ratio = 1600f / Math.max(b.getWidth(), b.getHeight());
    if (ratio < 1)
      b =
          Bitmap.createScaledBitmap(
              b, Math.round(b.getWidth() * ratio), Math.round(b.getHeight() * ratio), true);
    ByteArrayOutputStream out = new ByteArrayOutputStream();
    for (int quality = 90; quality >= 50; quality -= 10) {
      out.reset();
      b.compress(Bitmap.CompressFormat.JPEG, quality, out);
      if (out.size() <= 2_000_000) break;
    }
    Domain.require(out.size() <= 2_000_000, "Immagine troppo grande.");
    return Base64.getEncoder().encodeToString(out.toByteArray());
  }
}
