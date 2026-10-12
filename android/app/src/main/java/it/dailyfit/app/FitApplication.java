package it.dailyfit.app;

import android.app.Application;

public final class FitApplication extends Application {
  public Store store;

  @Override
  public void onCreate() {
    super.onCreate();
    store = new Store(this);
    RestTimer.channel(this);
  }
}
