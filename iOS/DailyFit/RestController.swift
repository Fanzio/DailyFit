import Foundation
import UserNotifications
import UIKit
import Combine

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound] }
}

@MainActor
final class RestController: ObservableObject {
    private let store: AppStore
    private let center = UNUserNotificationCenter.current()
    private let delegate = NotificationDelegate()
    private var scheduling: Task<Void, Never>?
    private var generation = UUID()
    private var requestID: String? = nil
    private var denialExplained = false
    init(store: AppStore) { self.store = store; center.delegate = delegate }
    func start(_ entry: TrainingEntry, name: String) {
        let timer = RestTimer(entryID: entry.id, name: name, duration: entry.rest, deadline: Date().addingTimeInterval(Double(entry.rest)))
        guard store.change({ $0.timer = timer }) else { return }
        schedule(timer)
    }
    func toggle() {
        guard var timer = store.data.timer else { return }
        if timer.running && timer.remaining() > 0 { timer.pause() } else { timer.resume() }
        guard store.change({ $0.timer = timer }) else { return }
        if timer.running { schedule(timer) } else { cancelNotification() }
    }
    func restart() {
        guard var timer = store.data.timer else { return }
        timer.pausedSeconds = 0; timer.deadline = Date().addingTimeInterval(Double(timer.duration))
        guard store.change({ $0.timer = timer }) else { return }
        schedule(timer)
    }
    func stop() { cancelNotification(); store.change { $0.timer = nil } }
    func reconcile() {
        guard var timer = store.data.timer else { return }
        if timer.running && timer.remaining() == 0 {
            timer.pause()
            store.change { $0.timer = timer }
            // Foreground visual feedback also works when notifications were denied.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
    func restore() async {
        // Remove orphan requests after an interrupted edit or a previous process.
        let token = generation
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix("dailyfit-rest-") && $0.identifier != requestID }.map(\.identifier))
        guard token == generation else { return }
        reconcile()
        if let timer = store.data.timer, timer.running { schedule(timer, askPermission: false) }
    }
    private func cancelNotification() {
        generation = UUID(); scheduling?.cancel()
        if let requestID { center.removePendingNotificationRequests(withIdentifiers: [requestID]); center.removeDeliveredNotifications(withIdentifiers: [requestID]) }
        requestID = nil
    }
    private func schedule(_ timer: RestTimer, askPermission: Bool = true) {
        cancelNotification()
        let token = generation, identifier = "dailyfit-rest-" + UUID().uuidString
        requestID = identifier
        scheduling = Task { [weak self] in
            guard let self else { return }
            do {
                var settings = await center.notificationSettings()
                if settings.authorizationStatus == .notDetermined && askPermission {
                    _ = try await center.requestAuthorization(options: [.alert, .sound])
                    settings = await center.notificationSettings()
                }
                guard !Task.isCancelled, generation == token else { return }
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    if askPermission && !denialExplained { denialExplained = true; store.message = "Il timer funziona nell’app. Per l’avviso a schermo bloccato abilita le notifiche di DailyFit nelle Impostazioni iPhone." }
                    return
                }
                let seconds = timer.deadline?.timeIntervalSinceNow ?? 0
                guard seconds > 0 else { reconcile(); return }
                let content = UNMutableNotificationContent()
                content.title = "Recupero terminato"
                // Do not put exercise names or personal training data on the lock screen.
                content.body = "Puoi tornare alla prossima serie."
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                if Task.isCancelled || generation != token { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
            } catch is CancellationError { }
            catch { if generation == token { store.message = "Timer avviato, ma l’avviso non è stato programmato: \(error.localizedDescription)" } }
        }
    }
}
