package it.dailyfit.app;

/** Pure timer arithmetic; elapsed time is authoritative within the same device boot. */
public final class Countdown {
  private Countdown() {}

  public static int remaining(
      boolean running,
      long elapsedDeadline,
      long wallDeadline,
      int savedBoot,
      int boot,
      int paused,
      long elapsedNow,
      long wallNow) {
    if (!running) return Math.max(0, Math.min(3600, paused));
    long delta = savedBoot == boot ? elapsedDeadline - elapsedNow : wallDeadline - wallNow;
    if (delta <= 0) return 0;
    return (int) Math.min(3600, (delta + 999) / 1000);
  }
}
