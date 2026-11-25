import AVFoundation
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.scenePhase) private var scene
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var path: [Route]
    @Binding var homeBusy: Bool
    @StateObject private var camera = PackageCamera()
    @State private var query = ""
    @FocusState private var searchFocus: Bool
    @State private var filter: Verdict?
    @State private var cameraReady = false
    @State private var visible = false
    @State private var captureToken: UUID?
    @State private var captureMessage: String?
    @State private var countdown: Int?
    @State private var configuredAuthorization = false

    var body: some View {
        Screen {
            heading
            SearchField(query: $query, focus: $searchFocus)
            StorageNotice()
            if !model.ready && !model.failed { ProgressView().frame(maxWidth: .infinity) }
            else if !searchFocus && query.isEmpty {
                hero
                if let count = model.library.pendingMilestones.first { milestone(count) }
                recent
            } else {
                results
            }
            UndoNotice()
        }
        .onAppear { visible = true }
        .onDisappear {
            visible = false
            cancelCapture()
            searchFocus = false
            query = ""
            homeBusy = false
            if !Launch.testing { Task { _ = await camera.setRunning(false) } }
        }
        .onChange(of: scene) { _, new in
            if new == .background { cancelCapture() }
        }
        .task(id: cameraWanted) {
            if Launch.testing { return }
            if !cameraWanted { cameraReady = false }
            let running = await camera.setRunning(cameraWanted)
            if !Task.isCancelled { cameraReady = running }
        }
        .onChange(of: blocksReview, initial: true) { _, blocked in homeBusy = visible && blocked }
    }

    private var blocksReview: Bool { captureToken != nil || captureMessage != nil || searchFocus || !query.isEmpty }

    private var cameraWanted: Bool {
        visible && path.isEmpty && scene == .active && query.isEmpty && !searchFocus &&
        (configuredAuthorization || AVCaptureDevice.authorizationStatus(for: .video) == .authorized)
    }

    private var heading: some View {
        HStack(spacing: 11) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white).frame(width: 44, height: 44)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(L.t("app.name")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(L.t("home.subtitle")).font(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.t("home.hero")).font(.headline)
            ZStack(alignment: .bottom) {
                if cameraReady {
                    CameraPreview(session: camera.session)
                } else {
                    RoundedRectangle(cornerRadius: 13).fill(Color(hex: 0xEBD8CE))
                    if Launch.testing {
                        Image("SamplePreview").resizable().scaledToFit().padding(10).frame(maxWidth: .infinity)
                    } else {
                        Image(systemName: "shippingbox").font(.system(size: 43, weight: .light))
                            .foregroundStyle(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.accent.opacity(0.74), style: StrokeStyle(lineWidth: 1.5, dash: [14, 8]))
                    .padding(11)
                Text(countdown.map { L.f("capture.countdown", $0) } ?? L.t("home.align"))
                    .font(.caption2.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Theme.base, in: Capsule()).padding(.bottom, 7)
            }
            .frame(height: 125)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { captureButtons }
                VStack(spacing: 6) { captureButtons }
            }
            if captureToken != nil {
                PrimaryButton(title: L.t("action.cancel"), symbol: "xmark", id: "capture.cancel", secondary: true, action: cancelCapture)
            } else if let captureMessage {
                Text(captureMessage).font(.footnote).foregroundStyle(Theme.ink)
                    .accessibilityIdentifier("camera.message")
            }
            Button {
                captureMessage = nil
                homeBusy = false
                path.append(.capture(CaptureDraft()))
            } label: {
                Label(L.t("home.manual"), systemImage: "square.and.pencil")
                    .font(.footnote.weight(.semibold))
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
            .accessibilityIdentifier("home.manual")
            .disabled(!model.ready)
        }
        .padding(12)
        .background(
            LinearGradient(colors: [Theme.rose, Color(hex: 0xF5E5E2)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18)
        )
        .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color(hex: 0xE8D4D5)) }
        .shadow(color: Theme.ink.opacity(0.08), radius: 12, x: 0, y: 4)
    }

    @ViewBuilder
    private var captureButtons: some View {
        PrimaryButton(title: L.t("home.capture"), symbol: "camera.fill", id: "home.capture") { begin(.record) }
            .disabled(captureToken != nil || !model.ready)
        PrimaryButton(title: L.t("home.lookup"), symbol: "viewfinder", id: "home.lookup", secondary: true) { begin(.query) }
            .disabled(captureToken != nil || !model.ready)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(L.t("home.recent")).sectionHeading()
            VerdictFilter(selected: $filter, scope: "home")
            let records = ProductRecord.sorted(model.library.records).filter { filter == nil || $0.latest?.verdict == filter }
            if records.isEmpty {
                EmptyRecords(title: L.t("record.empty")) {
                    if filter != nil { filter = nil }
                    else { path.append(.capture(CaptureDraft())) }
                } label: {
                    L.t(filter == nil ? "home.manual" : "records.reset")
                }
                .disabled(!model.ready)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                    ForEach(Array(records.prefix(4))) { record in
                        Button { path.append(.detail(record.id)) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                PhotoTile(id: record.photo).frame(height: 51)
                                Text(record.title).font(.caption.weight(.semibold)).lineLimit(2)
                                if let trial = record.latest { StatusPill(verdict: trial.verdict) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8).whiteCard()
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.record." + record.id.uuidString)
                    }
                }
            }
        }
    }

    private var results: some View {
        let records = ProductSearch.search(query, in: model.library.records)
        return VStack(alignment: .leading, spacing: 9) {
            Text(L.t("match.last")).sectionHeading()
            if records.isEmpty {
                EmptyRecords(title: L.t("match.none")) { query = ""; searchFocus = false } label: { L.t("records.reset") }
            } else {
                ForEach(records) { record in
                    RecordButton(record: record, scope: "search") {
                        model.completeCoreAction()
                        path.append(.detail(record.id))
                    }
                }
            }
        }
    }

    private func milestone(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.f("milestone.reached", count)).font(.headline)
            HStack {
                PrimaryButton(title: L.t("milestone.open"), symbol: "sparkles", id: "milestone.open") {
                    dismissMilestone(count)
                    path.append(.milestone(count))
                }
                Button {
                    dismissMilestone(count)
                } label: {
                    Text(L.t("action.later")).font(.footnote.weight(.semibold))
                        .padding(.horizontal, 7).frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("milestone.dismiss")
            }
        }
        .padding(12).whiteCard()
    }

    private func dismissMilestone(_ count: Int) {
        model.update { $0.pendingMilestones.removeAll { $0 == count } }
    }

    private func cancelCapture() {
        captureToken = nil
        countdown = nil
        homeBusy = blocksReview
    }

    private func begin(_ mode: CaptureDraft.Mode) {
        guard captureToken == nil, model.ready else { return }
        let token = UUID()
        captureToken = token
        captureMessage = nil
        homeBusy = true
        Task { @MainActor in
            defer {
                if captureToken == token { cancelCapture() }
            }
            do {
                let photo: UUID?
                if Launch.testing {
                    if Launch.arguments.contains("-camera-denied") {
                        captureMessage = L.t("capture.denied")
                        return
                    }
                    photo = try await model.bundledSamplePhoto()
                } else {
                    let first = AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined
                    if first {
                        let accepted = await AVCaptureDevice.requestAccess(for: .video)
                        guard captureToken == token else { return }
                        guard accepted else { captureMessage = L.t("capture.denied"); return }
                        configuredAuthorization = true
                        for _ in 0..<12 where scene != .active {
                            try await Task.sleep(for: .milliseconds(100))
                            guard captureToken == token else { return }
                        }
                    }
                    guard captureToken == token, visible, path.isEmpty, scene == .active else { return }
                    guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                        captureMessage = L.t("capture.denied")
                        return
                    }
                    if !cameraReady {
                        cameraReady = await camera.setRunning(true)
                        guard cameraWanted, captureToken == token else {
                            _ = await camera.setRunning(false)
                            cameraReady = false
                            return
                        }
                    }
                    guard cameraReady else { captureMessage = L.t("capture.unavailable"); return }
                    if first {
                        for remaining in [2, 1] {
                            countdown = remaining
                            try await Task.sleep(for: .seconds(1))
                            guard captureToken == token, cameraWanted else { return }
                        }
                        countdown = nil
                    }
                    guard captureToken == token, cameraWanted else { return }
                    let data = try await camera.capture()
                    guard captureToken == token, cameraWanted else { return }
                    photo = try await model.disk.addPhoto(data).0
                }
                guard captureToken == token, visible, path.isEmpty, scene == .active else {
                    if let photo { await model.disk.discardPhoto(photo) }
                    return
                }
                let draft = CaptureDraft(id: token, photo: photo)
                path.append(mode == .record ? .capture(draft) : .match(draft))
            } catch {
                if captureToken == token { captureMessage = L.t("capture.unavailable") }
            }
        }
    }
}

struct VerdictFilter: View {
    @Binding var selected: Verdict?
    let scope: String
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 4) { choices }
            } else {
                HStack(spacing: 4) { choices }
            }
        }
        .padding(3)
        .background(Color(hex: 0xF0E6DF), in: RoundedRectangle(cornerRadius: 13))
    }

    @ViewBuilder private var choices: some View {
        choice(nil)
        ForEach(Verdict.allCases) { verdict in choice(verdict) }
    }

    private func choice(_ verdict: Verdict?) -> some View {
        Button { selected = verdict } label: {
            Text(verdict?.label ?? L.t("records.all"))
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selected == verdict ? Theme.accent : Theme.muted)
                .background(selected == verdict ? .white : .clear, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected == verdict ? [.isSelected] : [])
        .accessibilityIdentifier(scope + ".filter." + (verdict?.rawValue ?? "all"))
    }
}

struct RecordButton: View {
    let record: ProductRecord
    let scope: String
    let action: () -> Void

    var body: some View {
        if let trial = record.latest {
            Button(action: action) {
                IconRow(verdict: trial.verdict, title: record.title,
                        subtitle: [record.shade, trial.date.formatted(date: .abbreviated, time: .omitted)]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                        detail: trial.reason.isEmpty ? L.t("reason.empty") : trial.reason, photo: record.photo)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(scope + ".record." + record.id.uuidString)
        }
    }
}

struct EmptyRecords: View {
    let title: String
    let action: () -> Void
    let label: () -> String

    var body: some View {
        VStack(spacing: 10) {
            EmptyIllustration()
            Text(title).font(.subheadline).multilineTextAlignment(.center)
            PrimaryButton(title: label(), symbol: "arrow.right", id: "records.emptyAction", action: action)
        }
        .padding(14).frame(maxWidth: .infinity).whiteCard()
    }
}

struct UndoNotice: View {
    @EnvironmentObject private var model: LibraryModel
    var body: some View {
        if model.undoRecord != nil {
            PrimaryButton(title: L.t("record.undo"), symbol: "arrow.uturn.backward", id: "record.undo", secondary: true) {
                model.undoDelete()
            }
        }
    }
}

struct RecordsView: View {
    @EnvironmentObject private var model: LibraryModel
    @Binding var path: [Route]
    @State private var search = ""
    @State private var verdict: Verdict?
    @FocusState private var focused: Bool

    var body: some View {
        Screen {
            Text(L.t("records.title")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            SearchField(query: $search, focus: $focused, id: "records.search")
            VerdictFilter(selected: $verdict, scope: "records")
            StorageNotice()
            UndoNotice()
            Text(L.t("records.recent")).sectionHeading()
            let items = ProductSearch.search(search, in: model.library.records).filter { verdict == nil || $0.latest?.verdict == verdict }
            if items.isEmpty {
                EmptyRecords(title: L.t("record.empty")) {
                    if search.isEmpty && verdict == nil { path.append(.capture(CaptureDraft())) }
                    else { search = ""; verdict = nil; focused = false }
                } label: {
                    L.t(search.isEmpty && verdict == nil ? "home.manual" : "records.reset")
                }
                .disabled(!model.ready)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(items) { record in
                        RecordButton(record: record, scope: "records") { path.append(.detail(record.id)) }
                    }
                }
            }
        }
    }
}
