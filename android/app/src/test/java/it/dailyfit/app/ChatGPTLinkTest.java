package it.dailyfit.app;

import static org.junit.Assert.*;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import org.junit.Test;

public class ChatGPTLinkTest {
  private static final String CHAT = "https://chatgpt.com/c/abc-123";

  private static final class Fake implements ChatGPTLink.Launcher {
    final List<String> calls = new ArrayList<>();
    final String accepted;

    Fake(String accepted) {
      this.accepted = accepted;
    }

    private boolean attempt(String destination, String url) {
      calls.add(destination + url);
      return destination.equals(accepted);
    }

    public boolean openApp() {
      return attempt("home", "");
    }

    public boolean openWeb(String url) {
      return attempt("web:", url);
    }
  }

  @Test
  public void installedAppWithPrivateChatReceivesNoUrlAndNeverOpensWeb() {
    Fake launcher = new Fake("home");
    assertTrue(ChatGPTLink.open(CHAT, launcher));
    assertEquals(Arrays.asList("home"), launcher.calls);
  }

  @Test
  public void installedAppWithHomeLinkNeverOpensWeb() {
    Fake launcher = new Fake("home");
    assertTrue(ChatGPTLink.open("https://chatgpt.com/", launcher));
    assertEquals(Arrays.asList("home"), launcher.calls);
  }

  @Test
  public void absentAppPreservesPrivateChatInWebFallback() {
    Fake launcher = new Fake("web:");
    assertTrue(ChatGPTLink.open(CHAT, launcher));
    assertEquals(Arrays.asList("home", "web:" + CHAT), launcher.calls);
  }

  @Test
  public void noHandlerReportsFailureWithoutRepeatedAttempts() {
    Fake launcher = new Fake("none");
    assertFalse(ChatGPTLink.open(CHAT, launcher));
    assertEquals(Arrays.asList("home", "web:" + CHAT), launcher.calls);
  }

  @Test
  public void emptySettingOpensHomeInAppFirst() {
    Fake launcher = new Fake("home");
    assertTrue(ChatGPTLink.open("  ", launcher));
    assertEquals(Arrays.asList("home"), launcher.calls);
  }

  @Test
  public void emptySettingWithoutAppOpensWebHomeOnce() {
    Fake launcher = new Fake("web:");
    assertTrue(ChatGPTLink.open("  ", launcher));
    assertEquals(Arrays.asList("home", "web:https://chatgpt.com/"), launcher.calls);
  }

  @Test
  public void invalidSettingsNeverLaunchAnExternalHandler() {
    for (String link :
        Arrays.asList(
            "https://chatgpt.com.evil.test/c/abc",
            "chatgpt://",
            "https://chatgpt.com/c/abc?token=secret",
            "http://chatgpt.com/")) {
      Fake launcher = new Fake("home");
      assertThrows(IllegalArgumentException.class, () -> ChatGPTLink.open(link, launcher));
      assertTrue(launcher.calls.isEmpty());
    }
  }
}
