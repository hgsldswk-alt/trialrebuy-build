import SwiftUI
import StoreKit
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var path: [Route]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        Screen {
            Text(L.t("settings.title")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            StorageNotice()
            Text(L.t("settings.library")).sectionHeading()
            LazyVGrid(columns: columns, spacing: 9) {
                tile("share.title", "square.and.arrow.up", "settings.share", .share(nil))
                tile("code.title", "link", "settings.code", .code, tint: Theme.leaf)
                tile("backup.title", "tray.and.arrow.down", "settings.backup", .backup, tint: Theme.sand)
                tile("milestone.title", "sparkles", "settings.milestones", .milestones)
            }
            Text(L.t("settings.tools")).sectionHeading()
            LazyVGrid(columns: columns, spacing: 9) {
                tile("stats.title", "chart.bar.xaxis", "settings.stats", .stats, tint: Theme.leaf)
                tile("templates.title", "text.badge.plus", "settings.templates", .templates)
                tile("csv.title", "tablecells", "settings.csv", .csv, tint: Theme.sand)
                if !Launch.isFree { tile("pay.title", "seal", "settings.paywall", .paywall) }
                IconTile(title: L.t("settings.language"), symbol: "character.bubble", id: "settings.language") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
        }
    }

    private func tile(_ key: String, _ icon: String, _ id: String, _ route: Route, tint: Color = Theme.rose) -> some View {
        IconTile(title: L.t(key), symbol: icon, id: id, tint: tint) { path.append(route) }
            .disabled(!model.ready)
    }
}

struct PaywallView: View {
    @EnvironmentObject private var commerce: Commerce
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen {
            if let value = commerce.entitlement {
                hero(value)
                VStack(alignment: .leading, spacing: 12) {
                    Text(L.t("pay.after")).sectionHeading()
                    Label(L.t("pay.core"), systemImage: "checkmark.circle").font(.subheadline)
                    Divider()
                    Label(L.t("pay.pro"), systemImage: "lock").font(.subheadline)
                }
                .padding(13).whiteCard()
                if !value.purchasedPro {
                    PrimaryButton(title: purchaseTitle, symbol: "seal", id: "pay.buy") {
                        Task { await commerce.buy(Launch.proID) }
                    }
                    if value.trialClaimedAt == nil, value.hasPro(at: .now, free: false) {
                        PrimaryButton(title: L.t("pay.claim"), symbol: "calendar.badge.checkmark", id: "pay.claim", secondary: true) {
                            Task { await commerce.buy(Launch.trialID) }
                        }
                    }
                }
                PrimaryButton(title: L.t("pay.restore"), symbol: "arrow.clockwise", id: "pay.restore", secondary: true) {
                    Task { await commerce.restore() }
                }
                PrimaryButton(title: L.t("pay.continue"), symbol: "arrow.left", id: "pay.continue", secondary: true) { dismiss() }
                if commerce.busy { ProgressView() }
                if let message = commerce.message { Text(message).font(.footnote).accessibilityIdentifier("pay.message") }
                Text(L.t("pay.notice")).font(.footnote).foregroundStyle(Theme.muted)
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .disabled(commerce.busy)
        .navigationTitle(L.t("pay.title")).navigationBarTitleDisplayMode(.inline)
        .task { await commerce.fetchProducts() }
    }

    private var purchaseTitle: String {
        if let price = commerce.products[Launch.proID]?.displayPrice { return L.f("pay.buyPrice", price) }
        return Launch.testing ? L.f("pay.buyPrice", "US$4.99") : L.t("pay.buy")
    }

    private func hero(_ value: Entitlement) -> some View {
        let days = value.daysLeft(at: .now)
        return VStack(spacing: 9) {
            ZStack {
                Circle().stroke(Theme.rose, lineWidth: 6)
                Circle().trim(from: 0, to: value.purchasedPro ? 1 : CGFloat(days) / 30)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                if value.purchasedPro {
                    Image(systemName: "checkmark").font(.system(size: 36, weight: .semibold))
                } else {
                    VStack(spacing: 0) {
                        Text(days, format: .number).font(.system(size: 40, weight: .bold, design: .rounded))
                        Text(L.t("pay.days")).font(.caption.weight(.semibold))
                    }
                }
            }
            .foregroundStyle(Theme.accent)
            .frame(width: 106, height: 106)
            .accessibilityHidden(true)
            Text(value.purchasedPro ? L.t("pay.unlocked") : (days > 0 ? L.f("pay.remaining", days) : L.t("pay.expired")))
                .font(.title3.bold()).accessibilityIdentifier(value.purchasedPro ? "pay.unlocked" : "pay.status")
            if days > 0, !value.purchasedPro {
                Text(L.f("pay.ends", value.trialEnd.formatted(date: .abbreviated, time: .omitted)))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity).padding(17)
        .background(Theme.paleRose, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct MilestonesView: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var path: [Route]

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        Screen {
            EmptyIllustration().frame(maxWidth: .infinity)
            ForEach([5, 15, 30], id: \.self) { count in
                if model.library.milestones.contains(count) {
                    IconTile(title: L.f("milestone.reached", count), symbol: "sparkles", id: "milestone." + String(count)) {
                        path.append(.milestone(count))
                    }
                } else {
                    Label(L.f("milestone.target", count), systemImage: "circle.dotted")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(10).whiteCard()
                }
            }
        }
        .navigationTitle(L.t("milestone.title")).navigationBarTitleDisplayMode(.inline)
    }
}

struct StatsView: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var brand: String?

    private var groups: [Date: [Trial]] {
        let records = model.library.records.filter { brand == nil || $0.brand == brand }
        let calendar = Calendar.current
        return Dictionary(grouping: records.flatMap(\.trials)) { trial in
            calendar.dateInterval(of: .month, for: trial.date)?.start ?? trial.date
        }
    }

    var body: some View {
        Screen {
            Text(L.t("stats.brand")).sectionHeading()
            let brands = Set(model.library.records.map(\.brand).filter { !$0.isEmpty }).sorted()
            Menu {
                Button(L.t("records.all")) { brand = nil }
                ForEach(brands, id: \.self) { name in Button(name) { brand = name } }
            } label: {
                Label(brand ?? L.t("records.all"), systemImage: "line.3.horizontal.decrease")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 12).whiteCard()
            }
            .accessibilityIdentifier("stats.brand")
            if groups.isEmpty {
                EmptyIllustration().frame(maxWidth: .infinity)
                Text(L.t("stats.empty"))
            }
            ForEach(groups.keys.sorted(by: >), id: \.self) { month in
                VStack(alignment: .leading, spacing: 8) {
                    Label(month.formatted(.dateTime.year().month(.wide)), systemImage: "calendar").font(.headline)
                    ForEach(Verdict.allCases) { verdict in
                        HStack {
                            StatusPill(verdict: verdict)
                            Spacer()
                            Text((groups[month] ?? []).filter { $0.verdict == verdict }.count, format: .number)
                                .font(.system(.body, design: .rounded).weight(.semibold))
                        }
                    }
                }
                .padding(12).whiteCard()
            }
        }
        .navigationTitle(L.t("stats.title")).navigationBarTitleDisplayMode(.inline)
    }
}

struct TemplatesView: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var text = ""
    @State private var editing: UUID?

    var body: some View {
        Screen {
            Text(L.t("templates.intro")).font(.subheadline).foregroundStyle(Theme.muted)
            TextField(L.t("reason.prompt"), text: $text)
                .padding(12).whiteCard().accessibilityIdentifier("templates.field")
                .onChange(of: text) { _, value in if value.count > 100 { text = String(value.prefix(100)) } }
            PrimaryButton(title: L.t("action.save"), symbol: "checkmark", id: "templates.save") {
                let reason = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !reason.isEmpty else { return }
                model.update { library in
                    if let editing, let index = library.templates.firstIndex(where: { $0.id == editing }) {
                        library.templates[index].text = reason
                    } else {
                        library.templates.append(ReasonTemplate(text: reason))
                    }
                }
                text = ""
                editing = nil
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            StorageNotice()
            ForEach(model.library.templates) { item in
                HStack(spacing: 8) {
                    Button {
                        editing = item.id
                        text = item.text
                    } label: {
                        Label(item.text, systemImage: "text.bubble")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("templates.edit." + item.id.uuidString)
                    Button(role: .destructive) {
                        model.update { $0.templates.removeAll { $0.id == item.id } }
                        if editing == item.id { editing = nil; text = "" }
                    } label: {
                        Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(L.t("record.delete"))
                    .accessibilityIdentifier("templates.delete." + item.id.uuidString)
                }
                .padding(.horizontal, 10).whiteCard()
            }
        }
        .navigationTitle(L.t("templates.title")).navigationBarTitleDisplayMode(.inline)
    }
}

struct CSVView: View {
    @EnvironmentObject private var model: LibraryModel
    @EnvironmentObject private var commerce: Commerce
    @State private var selecting = false
    @State private var busy = false
    @State private var pending: [ProductRecord] = []
    @State private var status: String?

    var body: some View {
        Screen {
            Text(L.t("csv.intro")).font(.subheadline)
            Text(verbatim: "brand,product,shade,verdict,reason")
                .font(.system(.footnote, design: .monospaced)).padding(10).whiteCard()
            PrimaryButton(title: L.t("csv.choose"), symbol: "doc", id: "csv.choose") {
                if Launch.testing, let text = ProcessInfo.processInfo.environment["TRIALREBUY_CSV"] {
                    loadFixture(text)
                } else {
                    selecting = true
                }
            }
            .disabled(busy)
            if !pending.isEmpty {
                Text(L.f("csv.preview", pending.count)).font(.headline).accessibilityIdentifier("csv.preview")
                PrimaryButton(title: L.t("action.import"), symbol: "square.and.arrow.down", id: "csv.confirm") {
                    Task { await commit() }
                }
                .disabled(busy)
            }
            if busy { ProgressView() }
            if let status { Text(status).font(.footnote).accessibilityIdentifier("csv.status") }
            StorageNotice()
        }
        .navigationTitle(L.t("csv.title")).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $selecting, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
            Task {
                busy = true
                pending = []
                status = nil
                defer { busy = false }
                do { pending = try await model.disk.parseCSV(result.get()) }
                catch { status = L.t("csv.invalid") }
            }
        }
    }

    private func loadFixture(_ text: String) {
        status = nil
        do { pending = try CSVImport.parse(Data(text.utf8)) }
        catch { status = L.t("csv.invalid") }
    }

    @MainActor private func commit() async {
        guard commerce.hasPro, !pending.isEmpty else { return }
        busy = true
        defer { busy = false }
        let records = pending
        pending = []
        let saved = await model.update { library in
            library.records += records
            for threshold in [5, 15, 30] where library.records.count >= threshold {
                library.milestones.insert(threshold)
            }
        }?.value
        status = L.t(saved == true ? "csv.done" : "storage.saveError")
    }
}

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw LibraryDisk.Failure.invalid }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct BackupView: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var selecting = false
    @State private var exporting = false
    @State private var busy = false
    @State private var document: BackupDocument?
    @State private var pending: Backup?
    @State private var status: String?

    var body: some View {
        Screen {
            Text(L.t("backup.intro")).font(.subheadline).foregroundStyle(Theme.muted)
            IconTile(title: L.t("backup.export"), symbol: "square.and.arrow.up", id: "backup.export") {
                Task { await prepareExport() }
            }
            .disabled(!model.ready || busy)
            IconTile(title: L.t("backup.restore"), symbol: "tray.and.arrow.down", id: "backup.restore", tint: Theme.leaf) {
                if Launch.testing, let data = document?.data {
                    Task { await preview { try await model.disk.preview(data) } }
                } else {
                    selecting = true
                }
            }
            .disabled(!model.ready || busy)
            if let pending {
                Text(L.f("backup.preview", pending.library.records.count)).font(.headline).accessibilityIdentifier("backup.preview")
                Text(L.t("backup.keep")).font(.footnote)
                PrimaryButton(title: L.t("backup.apply"), symbol: "checkmark", id: "backup.confirm") {
                    Task { await restore(pending) }
                }.disabled(busy)
            }
            if busy { ProgressView() }
            if let status { Text(status).font(.footnote).accessibilityIdentifier("backup.status") }
            StorageNotice()
        }
        .navigationTitle(L.t("backup.title")).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $selecting, allowedContentTypes: [.json]) { result in
            Task {
                await preview {
                    let url = try result.get()
                    let data = try await model.disk.read(url, limit: LibraryDisk.backupLimit)
                    return try await model.disk.preview(data)
                }
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "TrialRebuy-Backup") { result in
            switch result {
            case .success: status = L.t("backup.exported")
            case .failure: status = L.t("backup.exportError")
            }
            document = nil
        }
    }

    @MainActor private func prepareExport() async {
        busy = true
        status = nil
        defer { busy = false }
        do {
            let data = try await model.disk.export(model.library)
            document = BackupDocument(data: data)
            if Launch.testing { status = L.t("backup.exported") }
            else { exporting = true }
        } catch {
            status = L.t("backup.exportError")
        }
    }

    @MainActor private func preview(_ operation: () async throws -> Backup) async {
        busy = true
        status = nil
        pending = nil
        defer { busy = false }
        do { pending = try await operation() }
        catch { status = L.t("backup.invalid") }
    }

    @MainActor private func restore(_ backup: Backup) async {
        busy = true
        status = nil
        defer { busy = false }
        do {
            try await model.restore(backup)
            status = L.t("backup.restored")
            pending = nil
        } catch {
            status = L.t("backup.restoreError")
        }
    }
}
