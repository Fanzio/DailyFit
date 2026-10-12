import SwiftUI
import UIKit

@main
struct DailyFitApp: App {
    @StateObject private var store: AppStore
    @StateObject private var rest: RestController
    @StateObject private var navigation = NavigationState()
    init() {
        let store = AppStore()
        _store = StateObject(wrappedValue: store)
        _rest = StateObject(wrappedValue: RestController(store: store))
    }
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store).environmentObject(rest).environmentObject(navigation).preferredColorScheme(.dark).tint(FitTheme.lime) }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rest: RestController
    @Environment(\.scenePhase) private var phase
    @EnvironmentObject private var navigation: NavigationState
    @State private var chatSettings = false
    @State private var openingChat = false
    var body: some View {
        Group {
            if store.ready {
                VStack(spacing: 0) {
                    ZStack {
                        GymView().opacity(navigation.area == 0 ? 1 : 0).allowsHitTesting(navigation.area == 0).accessibilityHidden(navigation.area != 0)
                        NutritionView().opacity(navigation.area == 1 ? 1 : 0).allowsHitTesting(navigation.area == 1).accessibilityHidden(navigation.area != 1)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if let undo = store.deletionUndo {
                        HStack {
                            Text(undo.label).font(.caption).lineLimit(2)
                            Spacer()
                            Button("Annulla") { store.undoLastDeletion() }.font(.subheadline.bold())
                            Button { store.discardDeletionUndo() } label: { Image(systemName: "xmark") }.accessibilityLabel("Chiudi annullamento")
                        }.padding(12).background(FitTheme.card).disabled(store.restoring)
                    }
                    if store.data.timer != nil { RestBar(active: phase == .active) }
                    HStack(spacing: 0) {
                        navButton("Palestra", symbol: "dumbbell", index: 0)
                        Button { openChat() } label: { VStack(spacing: 5) { Image(systemName: "bubble.left.and.text.bubble.right").font(.title3).padding(.horizontal, 12).padding(.vertical, 6).background(FitTheme.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 13)); Text("ChatGPT ↗").font(.caption2) }.frame(maxWidth: .infinity) }
                            .disabled(openingChat)
                            .contextMenu { Button("Imposta chat", systemImage: "link") { chatSettings = true } }
                            .accessibilityHint("Tieni premuto per impostare una chat dedicata")
                        navButton("Nutrizione", symbol: "carrot", index: 1)
                    }.padding(.top, 10).padding(.bottom, 6).background(FitTheme.card)
                }
            } else if let error = store.loadError {
                VStack(spacing: 20) { Text("Archivio non disponibile").font(.title2.bold()); Text(error); Button("Riprova") { Task { await store.load(); if store.ready { await rest.restore() } } }.buttonStyle(PrimaryButtonStyle()) }.padding(24)
            } else { ProgressView("Apertura dei tuoi dati…") }
        }
        .background(FitTheme.background)
        .task { await store.load(); if store.ready { await rest.restore() } }
        .onChange(of: phase) { _, value in
            if value == .active { rest.reconcile(); Task { await store.flush() } }
            else if value == .background { store.discardDeletionUndo(); store.flushForBackground() }
            else { Task { await store.flush() } }
        }
        .sheet(isPresented: $chatSettings) { ChatSettingsView() }
        .onChange(of: shouldKeepScreenAwake) { _, enabled in UIApplication.shared.isIdleTimerDisabled = enabled }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .alert("DailyFit", isPresented: Binding(get: { store.message != nil && store.editorCount == 0 }, set: { if !$0 && store.editorCount == 0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
    }
    private func navButton(_ label: String, symbol: String, index: Int) -> some View {
        Button { navigation.area = index } label: { VStack(spacing: 8) { Image(systemName: symbol).font(.title3); Text(label).font(.caption2) }.frame(maxWidth: .infinity).foregroundStyle(navigation.area == index ? FitTheme.lime : FitTheme.muted) }.accessibilityAddTraits(navigation.area == index ? .isSelected : [])
    }
    private var shouldKeepScreenAwake: Bool {
        ScreenAwakePolicy.enabled(preference: store.data.keepScreenAwake == true, active: phase == .active, gymVisible: navigation.area == 0, viewingDay: navigation.viewingTrainingDay, editing: store.editorCount > 0 || chatSettings)
    }
    private func openChat() {
        guard !openingChat else { return }
        let link = store.data.chatLink
        openingChat = true
        Task { @MainActor in
            defer { openingChat = false }
            do {
                let accepted = try await ChatGPTLauncher.open(link)
                if !accepted {
                    store.message = "Impossibile aprire ChatGPT. Controlla il collegamento tenendo premuto il pulsante."
                }
            } catch { chatSettings = true }
        }
    }
}
struct ChatSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    var body: some View {
        EditorFrame(title: "Collegamento ChatGPT", save: save) {
            Section("Chat dedicata · facoltativa") { TextField("https://chatgpt.com/c/…", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled() }
            Section { Text("Copia l’indirizzo della tua conversazione privata dal browser. Lascia vuoto per aprire ChatGPT. Non serve creare un link condiviso."); Text("Proviamo prima l’app ChatGPT e, se non disponibile, il browser. Se la chat dedicata non si apre nell’app, cercala nella sua cronologia. Schede, dieta e note non vengono inviate automaticamente. ChatGPT richiede Internet e il suo account.") }.font(.footnote)
        }.onAppear { link = store.data.chatLink == "https://chatgpt.com/" ? "" : store.data.chatLink }
    }
    private func save() { do { let url = try Input.chatURL(link); if store.change({ $0.chatLink = url.absoluteString }) { dismiss() } } catch { store.message = error.localizedDescription } }
}
struct RestBar: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var rest: RestController
    let active: Bool
    var body: some View {
        if let timer = store.data.timer {
            if active && timer.running {
                TimelineView(.periodic(from: .now, by: 1)) { context in timerContent(timer, at: context.date) }
            } else { timerContent(timer, at: Date()) }
        }
    }
    private func timerContent(_ timer: RestTimer, at date: Date) -> some View {
        let remaining = timer.remaining(at: date)
        return HStack {
                    VStack(alignment: .leading) { Text(timer.name).font(.caption).lineLimit(1); Text(timerText(remaining) + " · " + (remaining == 0 ? "Recupero terminato" : timer.running ? "Recupero" : "In pausa")).font(.headline).monospacedDigit() }
                    Spacer()
                    Button { rest.toggle() } label: { Image(systemName: timer.running && remaining > 0 ? "pause.fill" : "play.fill") }.accessibilityLabel(timer.running && remaining > 0 ? "Pausa recupero" : "Riprendi recupero")
                    Button { rest.restart() } label: { Image(systemName: "arrow.counterclockwise") }.accessibilityLabel("Riavvia recupero")
                    Button { rest.stop() } label: { Image(systemName: "xmark") }.accessibilityLabel("Ferma recupero")
                }.padding(14).background(FitTheme.lime.opacity(0.13))
                    .onChange(of: remaining) { _, seconds in if seconds == 0 { rest.reconcile() } }
    }
}
