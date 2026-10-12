import SwiftUI
import UIKit
import ImageIO

enum FitTheme {
    static let lime = Color(red: 0.76, green: 0.95, blue: 0.42)
    static let background = Color(red: 0.06, green: 0.07, blue: 0.065)
    static let card = Color(red: 0.105, green: 0.12, blue: 0.105)
    static let muted = Color(red: 0.59, green: 0.63, blue: 0.56)
}
struct FitCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(FitTheme.card, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08))) }
}
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline).padding(14).frame(maxWidth: .infinity).background(FitTheme.lime.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(FitTheme.background)
    }
}
struct ExercisePicture: View {
    let exercise: Exercise
    var large = false
    var muscles = false
    @State private var picture: UIImage? = nil
    @State private var failed = false
    @EnvironmentObject private var store: AppStore
    private var bytes: Data? { muscles ? exercise.musclePhoto : exercise.photo }
    private var filename: String? { muscles ? exercise.musclePhotoFile : exercise.photoFile }
    private struct Request: Hashable { let bytes: Data?; let filename: String?; let large: Bool }
    init(exercise: Exercise, large: Bool = false, muscles: Bool = false) {
        self.exercise = exercise; self.large = large; self.muscles = muscles
    }
    var body: some View {
        Group {
            if let image = picture {
                if large { Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity) }
                else { Image(uiImage: image).resizable().scaledToFit().frame(width: 64, height: 64).background(.black) }
            }
            else {
                ZStack {
                    Color(red: 0.15, green: 0.2, blue: 0.12)
                    Image(systemName: failed ? "exclamationmark.triangle" : "figure.strengthtraining.traditional").resizable().scaledToFit().padding(large ? 40 : 14).foregroundStyle(FitTheme.lime)
                }.frame(width: large ? nil : 64, height: large ? 200 : 64)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14)).accessibilityLabel((muscles ? "Muscoli coinvolti" : "Esecuzione") + " di " + exercise.name)
        .task(id: Request(bytes: bytes, filename: filename, large: large)) {
            picture = nil; failed = false
            do {
                let key: String
                if let filename, bytes == nil { key = filename + (large ? ":large" : ":thumbnail") }
                else if let bytes { key = LocalRepository.imageDigest(bytes) + (large ? ":large" : ":thumbnail") }
                else { return }
                if let cached = ExerciseImageCache.images.object(forKey: key as NSString) { picture = cached; return }
                let source: Data
                if let bytes { source = bytes }
                else if let filename { source = try await store.imageBytes(filename) }
                else { return }
                try Task.checkCancellation()
                let maxSize = large ? 1600 : 192
                let job = Task.detached(priority: .userInitiated) { ImageProcessing.thumbnail(source, maxSize: maxSize) }
                let decoded = await withTaskCancellationHandler(operation: { await job.value }, onCancel: { job.cancel() })
                try Task.checkCancellation()
                guard let image = decoded else { failed = true; return }
                let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? source.count
                ExerciseImageCache.images.setObject(image, forKey: key as NSString, cost: cost)
                picture = image
            } catch is CancellationError { }
            catch { failed = true }
        }
        .onDisappear { picture = nil }
    }
}
private enum ExerciseImageCache {
    static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()
}
struct DecimalField: View {
    let label: String
    @Binding var value: String
    var body: some View { VStack(alignment: .leading, spacing: 7) { Text(label).font(.caption).foregroundStyle(FitTheme.muted); TextField("Da impostare", text: $value).keyboardType(.decimalPad).textFieldStyle(.roundedBorder) } }
}
struct EditorFrame<Content: View>: View {
    let title: String
    let save: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NavigationStack {
            Form { content }.scrollContentBackground(.hidden).background(FitTheme.background).navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annulla") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Salva", action: save).bold() } }
        }.tint(FitTheme.lime).preferredColorScheme(.dark)
            .onAppear { store.editorCount += 1 }.onDisappear { store.editorCount = max(0, store.editorCount - 1) }
            .alert("DailyFit", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) { Button("OK") { store.message = nil } } message: { Text(store.message ?? "") }
    }
}
func formatNumber(_ number: Double) -> String { number.formatted(.number.locale(Locale(identifier: "it_IT")).precision(.fractionLength(0...1))) }
func editNumber(_ number: Double?) -> String { number.map { String($0).replacingOccurrences(of: ".", with: ",") } ?? "" }
func timerText(_ seconds: Int) -> String { String(format: "%02d:%02d", seconds / 60, seconds % 60) }
