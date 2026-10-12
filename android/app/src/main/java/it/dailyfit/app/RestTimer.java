package it.dailyfit.app;

import android.app.*;
import android.content.*;
import android.os.Build;
import android.os.SystemClock;
import android.provider.Settings;
import java.util.UUID;

/** One stored deadline and one system alarm. No service, wake lock, or background tick. */
public final class RestTimer {
  private static final String CHANNEL = "rest", PREF = "rest-timer";
  private static final int ID = 401;
  final Context context;
  final SharedPreferences prefs;
  final AlarmManager alarms;
  private final int bootCount;
  private String scheduledToken = "";
  private boolean scheduledExact;

  public RestTimer(Context c) {
    context = c.getApplicationContext();
    prefs = context.getSharedPreferences(PREF, 0);
    alarms = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
    bootCount = Settings.Global.getInt(context.getContentResolver(), Settings.Global.BOOT_COUNT, 0);
  }

  public static void channel(Context c) {
    NotificationChannel channel =
        new NotificationChannel(CHANNEL, "Fine recupero", NotificationManager.IMPORTANCE_HIGH);
    channel.setDescription("Un avviso alla fine del recupero che avvii tu.");
    channel.setLockscreenVisibility(Notification.VISIBILITY_PRIVATE);
    c.getSystemService(NotificationManager.class).createNotificationChannel(channel);
  }

  private int boot() {
    return bootCount;
  }

  public boolean exists() {
    return prefs.contains("entry");
  }

  public boolean running() {
    return exists() && prefs.getBoolean("running", false);
  }

  public String entry() {
    return prefs.getString("entry", "");
  }

  public String name() {
    return prefs.getString("name", "");
  }

  public int duration() {
    return prefs.getInt("duration", 90);
  }

  public int remaining() {
    return Countdown.remaining(
        running(),
        prefs.getLong("elapsed", 0),
        prefs.getLong("wall", 0),
        prefs.getInt("boot", -1),
        boot(),
        prefs.getInt("paused", 0),
        SystemClock.elapsedRealtime(),
        System.currentTimeMillis());
  }

  public boolean exactAllowed() {
    return Build.VERSION.SDK_INT < 31 || alarms.canScheduleExactAlarms();
  }

  public void start(String entry, String name, int seconds) {
    Domain.require(seconds >= 1 && seconds <= 3600, "Recupero da 1 a 3600 secondi.");
    cancelAlarm();
    commit(
        prefs.edit().putString("entry", entry).putString("name", name).putInt("duration", seconds));
    resume(seconds);
  }

  public void toggle() {
    if (!exists()) return;
    if (running() && remaining() > 0) pause();
    else resume(remaining() > 0 ? remaining() : duration());
  }

  public void pause() {
    int left = remaining();
    commit(
        prefs
            .edit()
            .putBoolean("running", false)
            .putInt("paused", left)
            .putString("token", UUID.randomUUID().toString()));
    cancelAlarm();
  }

  public void restart() {
    if (exists()) resume(duration());
  }

  private void resume(int seconds) {
    cancelAlarm();
    long elapsed = SystemClock.elapsedRealtime() + seconds * 1000L;
    commit(
        prefs
            .edit()
            .putBoolean("running", true)
            .putInt("paused", 0)
            .putInt("boot", boot())
            .putLong("elapsed", elapsed)
            .putLong("wall", System.currentTimeMillis() + seconds * 1000L)
            .putString("token", UUID.randomUUID().toString()));
    schedule();
  }

  public void stop() {
    commit(prefs.edit().clear());
    cancelAlarm();
  }

  public void reconcile() {
    if (!exists()) return;
    if (running() && remaining() == 0) finish(prefs.getString("token", ""));
    else if (running() && prefs.getInt("boot", -1) != boot()) resume(remaining());
  }

  public void schedule() {
    if (!running()) return;
    if (remaining() == 0) {
      reconcile();
      return;
    }
    String token = prefs.getString("token", "");
    boolean exact = exactAllowed();
    if (token.equals(scheduledToken) && exact == scheduledExact) return;
    long time = SystemClock.elapsedRealtime() + remaining() * 1000L;
    PendingIntent intent = pending(token);
    try {
      if (exact)
        alarms.setExactAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, time, intent);
      else alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, time, intent);
    } catch (SecurityException revoked) {
      alarms.setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP, time, intent);
      exact = false;
    }
    scheduledToken = token;
    scheduledExact = exact;
  }

  private PendingIntent pending(String token) {
    return PendingIntent.getBroadcast(
        context,
        ID,
        new Intent(context, RestReceiver.class).putExtra("token", token),
        PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
  }

  private void cancelAlarm() {
    scheduledToken = "";
    alarms.cancel(pending(""));
    context.getSystemService(NotificationManager.class).cancel(ID);
  }

  public void finish(String token) {
    if (!running() || token == null || !token.equals(prefs.getString("token", ""))) return;
    if (remaining() > 0) {
      scheduledToken = ""; // An early alarm has already fired; it needs a replacement.
      schedule();
      return;
    }
    commit(prefs.edit().putBoolean("running", false).putInt("paused", 0));
    NotificationManager manager = context.getSystemService(NotificationManager.class);
    if (!manager.areNotificationsEnabled()) return;
    PendingIntent open =
        PendingIntent.getActivity(
            context,
            ID,
            new Intent(context, MainActivity.class),
            PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    Notification n =
        new Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_timer)
            .setContentTitle("Recupero terminato")
            .setContentText("Puoi tornare alla prossima serie.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .build();
    try {
      manager.notify(ID, n);
    } catch (SecurityException denied) {
      /* In-app completion is still visible. */
    }
  }

  private static void commit(SharedPreferences.Editor edit) {
    if (!edit.commit()) throw new IllegalStateException("Impossibile salvare il timer.");
  }
}
