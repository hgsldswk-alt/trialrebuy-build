import SwiftUI
import UIKit

private enum ShareCollection: String, CaseIterable, Identifiable {
    case one, buy, skip
    var id: Self { self }
    var title: String { L.t("share." + rawValue) }
}

struct ShareView: View {
    @EnvironmentObject private var model: LibraryModel
    let productID: UUID?
    let milestone: Int?
    @State private var collection: ShareCollection
    @State private var excluded: Set<UUID> = []
    @State private var photos: Set<UUID> = []
    @State private var reasons: Set<UUID> = []
    @State private var images: [UUID: UIImage] = [:]
    @State private var rectangular = false
    @State private var qr: CGImage?
    @State private var activity: Activity?
    @State private var generated = false
    @State private var failed = false
    @State private var rendering = false
    @State private var options = false

    init(productID: UUID? = nil, milestone: Int? = nil) {
        self.productID = productID
        self.milestone = milestone
        _collection = State(initialValue: productID == nil ? .buy : .one)
    }

    var body: some View {
        Screen {
            if milestone == nil {
                Picker(L.t("share.collection"), selection: $collection) {
                    ForEach(ShareCollection.allCases.filter { productID != nil || $0 != .one }) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.segmented).accessibilityIdentifier("share.collection")
            }
            if selected.isEmpty, milestone == nil {
                EmptyIllustration().frame(maxWidth: .infinity)
                Text(L.t("share.empty")).font(.subheadline)
            } else {
                poster(Array(selected.prefix(4)))
                if selected.count > 4 {
                    Text(L.f("share.pages", (selected.count + 3) / 4)).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            DisclosureGroup(L.t("share.customize"), isExpanded: $options) {
                Toggle(L.t("share.fixed"), isOn: $rectangular).accessibilityIdentifier("share.fixed")
                if milestone != nil {
                    Text(L.t("share.milestonePrivacy")).font(.footnote).foregroundStyle(Theme.muted)
                }
                optionRows
            }
            .padding(11).whiteCard().accessibilityIdentifier("share.options")
            PrimaryButton(title: L.t("share.image"), symbol: "square.and.arrow.up", id: "share.image") {
                Task { await render() }
            }
            .disabled((selected.isEmpty && milestone == nil) || rendering || qr == nil)
            if rendering { ProgressView() }
            if generated {
                Label(L.t("share.ready"), systemImage: "checkmark.circle").accessibilityIdentifier("share.requested")
            }
            if failed { Text(L.t("share.failed")).font(.footnote) }
        }
        .disabled(rendering)
        .navigationTitle(L.t("share.title")).navigationBarTitleDisplayMode(.inline)
        .task {
            let text = Launch.downloadURL ?? L.t("share.hashtag")
            qr = await Task.detached(priority: .userInitiated) { DownloadQR.image(for: text) }.value
        }
        .task(id: photos) {
            let selectedPhotos = photos
            let records = model.library.records.filter { selectedPhotos.contains($0.id) }
            var loaded = [UUID: UIImage]()
            for record in records {
                if let photo = record.photo, let data = await model.disk.thumbnail(photo),
                   let image = UIImage(data: data) { loaded[record.id] = image }
            }
            if !Task.isCancelled { images = loaded }
        }
        .sheet(item: $activity) { activity in ActivityView(items: activity.items, folder: activity.folder) }
    }

    private var available: [ProductRecord] {
        if milestone != nil {
            return Array(ProductRecord.sorted(model.library.records).prefix(12))
        }
        switch collection {
        case .one: return productID.flatMap(model.record).map { [$0] } ?? []
        case .buy: return ProductRecord.sorted(model.library.records.filter { $0.latest?.verdict == .buy })
        case .skip: return ProductRecord.sorted(model.library.records.filter { $0.latest?.verdict == .skip })
        }
    }

    private var selected: [ProductRecord] {
        available.filter { milestone == nil ? !excluded.contains($0.id) : excluded.contains($0.id) }
    }

    private var optionRows: some View {
        LazyVStack(alignment: .leading, spacing: 9) {
            ForEach(available) { item in
                Toggle(item.shareName, isOn: Binding(get: {
                    milestone == nil ? !excluded.contains(item.id) : excluded.contains(item.id)
                }, set: { value in
                    if value == (milestone != nil) { excluded.insert(item.id) } else { excluded.remove(item.id) }
                }))
                .accessibilityIdentifier("share.item." + item.id.uuidString)
                if selected.contains(where: { $0.id == item.id }) {
                    if item.photo != nil, model.library.style.preferPhotos {
                        photoToggle(item)
                    }
                    if item.latest?.reason.isEmpty == false {
                        Toggle(L.t("share.reason"), isOn: membership(item.id, in: $reasons))
                            .accessibilityIdentifier("share.reason." + item.id.uuidString)
                    }
                    if item.photo != nil, !model.library.style.preferPhotos {
                        photoToggle(item)
                    }
                }
                Divider()
            }
        }
        .font(.subheadline)
    }

    private func photoToggle(_ item: ProductRecord) -> some View {
        Toggle(L.t("share.photo"), isOn: membership(item.id, in: $photos))
            .accessibilityIdentifier("share.photo." + item.id.uuidString)
    }

    private func membership(_ id: UUID, in selection: Binding<Set<UUID>>) -> Binding<Bool> {
        Binding(get: { selection.wrappedValue.contains(id) }, set: { enabled in
            if enabled { selection.wrappedValue.insert(id) } else { selection.wrappedValue.remove(id) }
        })
    }

    private func poster(_ records: [ProductRecord]) -> some View {
        let heading = milestone.map { L.f("milestone.reached", $0) } ?? collection.title
        let counts = milestone == nil ? [] : Verdict.allCases.map { verdict in
            L.f("share.count", verdict.label, model.library.records.filter { $0.latest?.verdict == verdict }.count)
        }
        return SharePoster(title: heading, counts: counts, rows: records.map {
            SharePoster.Row(name: $0.shareName, verdict: $0.latest?.verdict ?? .retry,
                            reason: reasons.contains($0.id) ? $0.latest?.reason : nil,
                            image: photos.contains($0.id) ? images[$0.id] : nil)
        }, palette: model.library.style.palette, qr: qr, fixed: rectangular)
    }

    @MainActor private func render() async {
        rendering = true
        generated = false
        failed = false
        defer { rendering = false }
        let records = selected
        let photoIDS = photos
        for record in records where photoIDS.contains(record.id) && images[record.id] == nil {
            if let photo = record.photo, let data = await model.disk.thumbnail(photo) {
                images[record.id] = UIImage(data: data)
            }
        }
        let pages = stride(from: 0, to: max(records.count, 1), by: 4)
        var folder: URL?
        do {
            let output = try await model.disk.shareFolder()
            folder = output
            var urls = [URL]()
            for (page, offset) in pages.enumerated() {
                let subset = Array(records.dropFirst(offset).prefix(4))
                let content = poster(subset).frame(width: 360).dynamicTypeSize(.medium)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 3
                guard let image = renderer.cgImage else { throw LibraryDisk.Failure.image }
                urls.append(try await model.disk.writePNG(image, index: page, into: output))
            }
            if Launch.testing {
                await model.disk.removeShareFolder(output)
                generated = true
            } else {
                var items: [Any] = urls.map { $0 as Any }
                items.append(L.t("share.hashtag"))
                activity = Activity(items: items, folder: output)
            }
        } catch {
            if let folder { await model.disk.removeShareFolder(folder) }
            failed = true
        }
    }

    private struct Activity: Identifiable {
        let id = UUID()
        let items: [Any]
        let folder: URL
    }

    private struct ActivityView: UIViewControllerRepresentable {
        @EnvironmentObject private var model: LibraryModel
        let items: [Any]
        let folder: URL
        func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
            let disk = model.disk
            controller.completionWithItemsHandler = { _, _, _, _ in
                Task { await disk.removeShareFolder(folder) }
            }
            return controller
        }
        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }
}

private struct SharePoster: View {
    struct Row {
        let name: String
        let verdict: Verdict
        let reason: String?
        let image: UIImage?
    }

    let title: String
    let counts: [String]
    let rows: [Row]
    let palette: ShareStyle.Palette
    let qr: CGImage?
    let fixed: Bool

    var body: some View {
        if fixed {
            Color.clear.aspectRatio(4.0 / 5.0, contentMode: .fit)
                .overlay {
                    GeometryReader { geometry in
                        content.frame(width: geometry.size.width, height: geometry.size.height).clipped()
                    }
                }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 22, weight: .medium)).rotationEffect(.degrees(-10))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 43, height: 43)
                    .background(.white, in: RoundedRectangle(cornerRadius: 11))
                Text(title).font(.title3.bold()).foregroundStyle(Theme.ink)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Theme.tint(palette), in: RoundedRectangle(cornerRadius: 12))
            ForEach(counts, id: \.self) { count in Text(count).font(.caption.weight(.semibold)) }
            ForEach(Array(rows.indices), id: \.self) { i in
                row(rows[i])
            }
            if fixed { Spacer(minLength: 0) }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L.t("share.hashtag")).font(.subheadline.bold()).foregroundStyle(Theme.accent)
                    Text(L.t(Launch.downloadURL == nil ? "share.qrPlaceholder" : "share.qrDownload"))
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if let qr {
                    Image(decorative: qr, scale: 1, orientation: .up)
                        .resizable().interpolation(.none).frame(width: 56, height: 56)
                }
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 15))
        .padding(2)
        .background(
            LinearGradient(colors: [Theme.accent, Theme.tint(palette), Theme.sand], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 17)
        )
        .foregroundStyle(Theme.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("share.card")
    }

    private func row(_ item: Row) -> some View {
        HStack(alignment: .top, spacing: 7) {
            if let image = item.image {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.footnote.bold()).lineLimit(2)
                if let reason = item.reason, !reason.isEmpty {
                    Text(reason).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            Spacer(minLength: 2)
            StatusPill(verdict: item.verdict)
        }
        .padding(.vertical, 3)
    }

}

struct CodeView: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var text = ""
    @State private var copied = false
    @State private var applied = false

    private var imported: ShareStyle? { ShareCode.decode(text) }

    var body: some View {
        Screen {
            Text(L.t("code.intro")).font(.subheadline).foregroundStyle(Theme.muted)
            Picker(L.t("code.palette"), selection: Binding(get: { model.library.style.palette }, set: { palette in
                model.update { $0.style.palette = palette }
            })) {
                ForEach(ShareStyle.Palette.allCases) { palette in Text(palette.label).tag(palette) }
            }
            .pickerStyle(.segmented).accessibilityIdentifier("code.palette")
            Toggle(L.t("code.photoFirst"), isOn: Binding(get: { model.library.style.preferPhotos }, set: { value in
                model.update { $0.style.preferPhotos = value }
            })).padding(10).whiteCard().accessibilityIdentifier("code.photoFirst")
            PrimaryButton(title: L.t("code.copy"), symbol: "doc.on.doc", id: "code.copy", secondary: true) {
                UIPasteboard.general.string = ShareCode.encode(model.library.style)
                copied = true
            }
            if copied { Text(L.t("code.copied")).font(.footnote).accessibilityIdentifier("code.copied") }
            TextField(L.t("code.prompt"), text: $text)
                .font(.system(.footnote, design: .monospaced))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).whiteCard().accessibilityIdentifier("code.field")
                .onChange(of: text) { _, _ in applied = false }
            PrimaryButton(title: L.t("code.paste"), symbol: "clipboard", id: "code.paste", secondary: true) {
                if Launch.testing, let fixture = ProcessInfo.processInfo.environment["TRIALREBUY_CODE"] {
                    text = fixture
                } else {
                    text = UIPasteboard.general.string ?? ""
                }
            }
            if let imported {
                Text(L.t("code.preview")).sectionHeading()
                VStack(alignment: .leading, spacing: 9) {
                    Label(imported.palette.label, systemImage: "rectangle.on.rectangle.angled")
                        .font(.subheadline.bold()).foregroundStyle(Theme.accent)
                    StatusPill(verdict: .buy)
                    StatusPill(verdict: .skip)
                    if imported.preferPhotos {
                        Label(L.t("code.photoFirst"), systemImage: "photo").font(.caption)
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.tint(imported.palette), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("code.preview")
                PrimaryButton(title: L.t("code.apply"), symbol: "checkmark", id: "code.apply") {
                    model.update { $0.style = imported }
                    applied = true
                }
            } else if !text.isEmpty {
                Text(L.t("code.invalid")).font(.footnote).accessibilityIdentifier("code.invalid")
            }
            if applied { Text(L.t("code.applied")).font(.footnote).accessibilityIdentifier("code.applied") }
            StorageNotice()
        }
        .navigationTitle(L.t("code.title")).navigationBarTitleDisplayMode(.inline)
    }
}
