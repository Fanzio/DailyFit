package it.dailyfit.app;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;

final class ChatGPTLauncher implements ChatGPTLink.Launcher {
  private static final String PACKAGE = "com.openai.chatgpt";
  private final Activity activity;

  ChatGPTLauncher(Activity activity) {
    this.activity = activity;
  }

  public boolean openApp() {
    try {
      return launch(activity.getPackageManager().getLaunchIntentForPackage(PACKAGE));
    } catch (SecurityException unavailable) {
      return false;
    }
  }

  public boolean openWeb(String url) {
    return launch(
        new Intent(Intent.ACTION_VIEW, Uri.parse(url)).addCategory(Intent.CATEGORY_BROWSABLE));
  }

  private boolean launch(Intent intent) {
    if (intent == null) return false;
    try {
      activity.startActivity(intent);
      return true;
    } catch (ActivityNotFoundException | SecurityException unavailable) {
      return false;
    }
  }
}
