import XCTest
@testable import DailyFit

@MainActor
final class ChatGPTLauncherTests: XCTestCase {
    private let chat = "https://chatgpt.com/c/abc-123"

    func testAcceptedUniversalLinkNeverLaunchesFallbacks() async throws {
        var urls: [String] = []
        let accepted = try await ChatGPTLauncher.open(chat) { url, destination in
            urls.append(url.absoluteString)
            XCTAssertEqual(destination, .universalLink)
            return true
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(urls, [chat])
    }

    func testUnsupportedUniversalLinkOpensAppHomeWithoutPrivateIdentifier() async throws {
        var urls: [String] = []
        let accepted = try await ChatGPTLauncher.open(chat) { url, destination in
            urls.append(url.absoluteString)
            return destination == .appHome
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(urls, [chat, "chatgpt://"])
    }

    func testUnavailableAppPreservesConversationInWebFallback() async throws {
        var destinations: [ChatGPTLauncher.Destination] = []
        let accepted = try await ChatGPTLauncher.open(chat) { url, destination in
            destinations.append(destination)
            if destination == .web { XCTAssertEqual(url.absoluteString, self.chat) }
            return destination == .web
        }
        XCTAssertTrue(accepted)
        XCTAssertEqual(destinations, [.universalLink, .appHome, .web])
    }

    func testNoHandlerReturnsFailureWithoutRetryLoop() async throws {
        var count = 0
        let accepted = try await ChatGPTLauncher.open(chat) { _, _ in count += 1; return false }
        XCTAssertFalse(accepted)
        XCTAssertEqual(count, 3)
    }

    func testEmptySettingAttemptsHomeAsUniversalLink() async throws {
        let accepted = try await ChatGPTLauncher.open("  ") { url, destination in
            XCTAssertEqual(url.absoluteString, "https://chatgpt.com/")
            XCTAssertEqual(destination, .universalLink)
            return true
        }
        XCTAssertTrue(accepted)
    }

    func testInvalidSettingsDoNotOpenExternalApplications() async {
        for link in ["https://chatgpt.com.evil.test/c/abc", "chatgpt://",
                     "https://chatgpt.com/c/abc?token=secret", "http://chatgpt.com/"] {
            do {
                _ = try await ChatGPTLauncher.open(link) { _, _ in
                    XCTFail("An invalid link must not reach the operating system")
                    return true
                }
                XCTFail("Expected validation error")
            } catch { /* Expected validation failure. */ }
        }
    }
}
