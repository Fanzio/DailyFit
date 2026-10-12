import UIKit

@MainActor
enum ChatGPTLauncher {
    enum Destination: Equatable { case universalLink, appHome, web }

    static func open(_ link: String) async throws -> Bool {
        try await open(link, using: openSystem)
    }

    static func open(_ link: String, using launch: (URL, Destination) async -> Bool) async throws -> Bool {
        let url = try Input.chatURL(link)
        if await launch(url, .universalLink) { return true }
        // Compatibility fallback only: this scheme has no documented OpenAI contract.
        // Pass no private conversation identifier to the custom-scheme handler.
        if let home = URL(string: "chatgpt://"), await launch(home, .appHome) { return true }
        return await launch(url, .web)
    }

    private static func openSystem(_ url: URL, _ destination: Destination) async -> Bool {
        let app = UIApplication.shared
        switch destination {
        case .universalLink:
            return await app.open(url, options: [.universalLinksOnly: true])
        case .appHome:
            guard app.canOpenURL(url) else { return false }
            return await app.open(url, options: [:])
        case .web:
            return await app.open(url, options: [:])
        }
    }
}
