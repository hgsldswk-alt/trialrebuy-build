import SwiftUI
import UIKit

@MainActor
final class LibraryModel: ObservableObject {
    @Published private(set) var library = Library()
    @Published private(set) var ready = false
    @Published private(set) var failed = false
    @Published private(set) var writing = false
    @Published private(set) var undoRecord: ProductRecord?
    let disk = LibraryDisk()
    private var revision = 0
    private var currentWrite: Task<Bool, Never>?
    private var undoTask: Task<Void, Never>?
    private var loading = false
    private var didReset = false

    func load() async {
        guard !ready, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let reset = Launch.testing && Launch.arguments.contains("-reset") && !didReset
            library = try await disk.load(reset: reset)
            didReset = true
            if Launch.testing, !Launch.arguments.contains("-empty"), library.records.isEmpty {
                library.records = try await samples()
            }
            failed = false
            ready = true
            if !Launch.testing { update { $0.review.use(at: .now) } }
        } catch {
            failed = true
        }
    }

    @discardableResult
    func update(_ change: (inout Library) -> Void) -> Task<Bool, Never>? {
        guard ready else { return nil }
        change(&library)
        return persist()
    }

    @discardableResult
    func persist() -> Task<Bool, Never> {
        revision += 1
        let revision = self.revision
        let snapshot = library
        writing = true
        let task = Task {
            do {
                try await disk.save(snapshot, revision: revision)
                if self.revision == revision {
                    failed = false
                    writing = false
                }
                return true
            } catch {
                if self.revision == revision {
                    failed = true
                    writing = false
                }
                return false
            }
        }
        currentWrite = task
        return task
    }

    func flushInBackground() {
        guard writing, let currentWrite else { return }
        let app = UIApplication.shared
        let background = app.beginBackgroundTask(withName: "Save trial library", expirationHandler: nil)
        Task {
            _ = await currentWrite.value
            if background != .invalid { app.endBackgroundTask(background) }
        }
    }

    func record(_ id: UUID) -> ProductRecord? { library.records.first { $0.id == id } }

    func edit(_ id: UUID, change: (inout ProductRecord) -> Void) {
        guard let index = library.records.firstIndex(where: { $0.id == id }) else { return }
        update { change(&$0.records[index]) }
    }

    func saveTrial(_ trial: Trial, hints: ProductRecord, existing: UUID?) -> UUID {
        if let recorded = library.records.first(where: { $0.trials.contains { $0.id == trial.id } }) {
            return recorded.id
        }
        let id = existing ?? hints.id
        update { library in
            if let index = library.records.firstIndex(where: { $0.id == id }) {
                library.records[index].trials.append(trial)
            } else {
                var product = hints
                product.trials = [trial]
                library.records.append(product)
                library.checkMilestones()
            }
        }
        let save = currentWrite
        Task {
            if await save?.value == true { completeCoreAction() }
        }
        return id
    }

    func correctTrial(_ id: UUID, trial: UUID, change: (inout Trial) -> Void) {
        edit(id) { product in
            if let index = product.trials.firstIndex(where: { $0.id == trial }) {
                change(&product.trials[index])
            }
        }
    }

    func delete(_ id: UUID) {
        undoRecord = record(id)
        update { $0.records.removeAll { $0.id == id } }
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(9))
            if !Task.isCancelled { undoRecord = nil }
        }
    }

    func undoDelete() {
        guard let record = undoRecord else { return }
        undoTask?.cancel()
        undoRecord = nil
        update {
            if !$0.records.contains(where: { $0.id == record.id }) { $0.records.append(record) }
        }
    }

    func completeCoreAction() {
        guard !Launch.testing else { return }
        update { $0.review.complete(at: .now) }
    }

    func restore(_ backup: Backup) async throws {
        let staged = try await disk.stageRestore(backup, skipping: Set(library.records.map(\.id)))
        _ = await currentWrite?.value
        while true {
            var merged = library
            merged.merge(staged)
            revision += 1
            let next = revision
            try await disk.save(merged, revision: next)
            if revision == next {
                library = merged
                failed = false
                writing = false
                return
            }
            _ = await currentWrite?.value
        }
    }

    private func samples() async throws -> [ProductRecord] {
        let firstDate = Date(timeIntervalSince1970: 1_785_600_000)
        let photo = try await bundledSamplePhoto()
        return [
            ProductRecord(brand: L.t("demo.brand"), name: L.t("demo.lip"), shade: L.t("demo.shade05"), trials: [
                Trial(date: firstDate.addingTimeInterval(-604_800), verdict: .retry, reason: L.t("demo.retry"), photo: photo),
                Trial(date: firstDate, verdict: .skip, reason: L.t("demo.skip"), photo: photo)
            ]),
            ProductRecord(brand: L.t("demo.brand"), name: L.t("demo.lip"), shade: L.t("demo.shade02"), trials: [
                Trial(date: firstDate.addingTimeInterval(-86_400), verdict: .buy, reason: L.t("demo.buy"), photo: photo)
            ]),
            ProductRecord(brand: "June Atelier", name: L.t("demo.serum"), trials: [
                Trial(date: firstDate.addingTimeInterval(-172_800), verdict: .buy, reason: L.t("demo.serumReason"))
            ]),
            ProductRecord(brand: "Rive Lab", name: L.t("demo.cream"), trials: [
                Trial(date: firstDate.addingTimeInterval(-259_200), verdict: .retry, reason: L.t("demo.creamReason"))
            ])
        ]
    }

    func bundledSamplePhoto() async throws -> UUID? {
        guard let url = Bundle.main.url(forResource: "SamplePackage", withExtension: "jpg") else { return nil }
        let data = try await disk.read(url, limit: LibraryDisk.photoLimit)
        return try await disk.addPhoto(data).0
    }
}
