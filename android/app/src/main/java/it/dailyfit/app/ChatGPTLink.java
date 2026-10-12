package it.dailyfit.app;

/** App-first routing, with no account access or transfer of DailyFit data. */
final class ChatGPTLink {
  interface Launcher {
    boolean openApp();

    boolean openWeb(String url);
  }

  static boolean open(String link, Launcher launcher) {
    String url = Domain.web(link, true);
    // Do not send HTTPS VIEW intents to ChatGPT: its handler may open a browser itself.
    // Launch its home activity without a URL, then stop after a successful launch.
    return launcher.openApp() || launcher.openWeb(url);
  }

  private ChatGPTLink() {}
}
