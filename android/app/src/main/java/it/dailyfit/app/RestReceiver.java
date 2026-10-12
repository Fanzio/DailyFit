package it.dailyfit.app;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

public final class RestReceiver extends BroadcastReceiver {
  @Override
  public void onReceive(Context context, Intent intent) {
    new RestTimer(context).finish(intent.getStringExtra("token"));
  }
}
