import SwiftUI
import StoreKit
import UIKit

struct CaptureDraft: Equatable, Hashable {
    enum Mode: String { case record, query }
    let id: UUID
    var photo: UUID?
    var existing: UUID?

    init(id: UUID = UUID(), photo: UUID? = nil, existing: UUID? = nil) {
        self.id = id
        self.photo = photo
        self.existing = existing
    }
}

enum Route: Hashable {
    case capture(CaptureDraft), match(CaptureDraft), detail(UUID), share(UUID?), milestone(Int)
    case code, backup, paywall, stats, templates, csv, milestones
}

enum Tab: String, CaseIterable {
    case home, records, settings
    var symbol: String {
        switch self {
        case .home: "house"
        case .records: "square.stack"
        case .settings: "gearshape"
        }
    }
}

@main
struct TrialRebuyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @StateObject private var model = LibraryModel()
    @StateObject private var commerce = Commerce()
    @State private var tab = Tab.home
    @State private var path: [Route] = []
    @State private var keyboard = false
    @State private var homeBusy = false
    @State private var initialized = false
    @State private var now = Date()
    @Environment(\.scenePhase) private var scene
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch tab {
                case .home: HomeView(path: $path, homeBusy: $homeBusy)
                case .records: RecordsView(path: $path)
                case .settings: SettingsView(path: $path)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !keyboard { tabs }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                destination(route).toolbar(.visible, for: .navigationBar)
            }
        }
        .environmentObject(model)
        .environmentObject(commerce)
        .task { await model.load() }
        .task { await commerce.start() }
        .task(id: commerce.entitlement?.trialEnd) {
            guard let end = commerce.entitlement?.trialEnd else { return }
            let seconds = end.timeIntervalSinceNow
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            if !Task.isCancelled { now = .now }
        }
        .onChange(of: model.ready) { _, ready in
            if ready, !initialized {
                initialized = true
                if Launch.testing, Launch.arguments.contains("-paywall") { path = [.paywall] }
            }
        }
        .onChange(of: path) { old, new in
            let removed = Set(old.compactMap(temporaryPhoto)).subtracting(new.compactMap(temporaryPhoto))
            for id in removed where !model.library.photoIDs.contains(id) {
                Task { await model.disk.discardPhoto(id) }
            }
        }
        .onChange(of: scene) { _, phase in
            if phase == .active {
                now = .now
                if !Launch.testing { model.update { $0.review.use(at: .now) } }
            }
            if phase == .background { model.flushInBackground() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboard = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboard = false }
        .task(id: reviewEligible) {
            guard reviewEligible else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, reviewEligible else { return }
            Task { @MainActor in
                guard reviewEligible else { return }
                let previous = model.library.review.requestedVersion
                let task = model.update { $0.review.markRequested(version: version) }
                if await task?.value == true, reviewIdle {
                    requestReview()
                } else {
                    model.update {
                        $0.review.requestedVersion = previous
                        $0.review.qualified = true
                    }
                }
            }
        }
    }

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1" }
    private var reviewIdle: Bool {
        scene == .active && tab == .home && path.isEmpty && !keyboard && !model.failed &&
        model.undoRecord == nil && model.library.pendingMilestones.isEmpty && !homeBusy
    }
    private var reviewEligible: Bool {
        !Launch.testing && reviewIdle && model.library.review.canRequest(version: version)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .capture(let draft): CaptureView(draft: draft)
        case .match(let draft): MatchView(draft: draft, path: $path)
        case .detail(let id): DetailView(id: id, path: $path)
        case .share(let id): ShareView(productID: id)
        case .milestone(let count): ShareView(milestone: count)
        case .code: CodeView()
        case .backup: BackupView()
        case .paywall: PaywallView()
        case .stats, .templates, .csv:
            if Launch.isFree || commerce.entitlement?.hasPro(at: now) == true {
                switch route {
                case .stats: StatsView()
                case .templates: TemplatesView()
                default: CSVView()
                }
            } else if commerce.entitlement != nil {
                PaywallView()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.base)
            }
        case .milestones: MilestonesView(path: $path)
        }
    }

    private func temporaryPhoto(_ route: Route) -> UUID? {
        switch route {
        case .capture(let draft), .match(let draft): draft.photo
        default: nil
        }
    }

    private var tabs: some View {
        HStack(spacing: 5) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    if tab != item { tab = item }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .medium))
                        Text(L.t("tab." + item.rawValue)).font(.caption2.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 45)
                    .background(tab == item ? Theme.paleRose : .clear, in: RoundedRectangle(cornerRadius: 11))
                    .foregroundStyle(tab == item ? Theme.accent : Theme.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
                .accessibilityIdentifier("tab." + item.rawValue)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 5)
        .background(.white)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

