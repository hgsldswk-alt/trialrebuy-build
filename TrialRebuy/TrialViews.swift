import PhotosUI
import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var model: LibraryModel
    @EnvironmentObject private var commerce: Commerce
    @Environment(\.dynamicTypeSize) private var typeSize
    let draft: CaptureDraft
    var missingMatch = false
    var knownText: String?
    @State private var recordID: UUID?
    @State private var hints = ProductRecord()
    @State private var reason = ""
    @State private var recognition = ""
    @State private var identified = false
    @FocusState private var focus: Bool

    var body: some View {
        Screen {
            StorageNotice()
            if missingMatch {
                Label(L.t("match.none"), systemImage: "magnifyingglass")
                    .font(.subheadline).padding(10).background(Theme.sand, in: RoundedRectangle(cornerRadius: 12))
            }
            if draft.photo != nil { PhotoTile(id: draft.photo, large: true, accessibilityID: "capture.photo").frame(height: 219) }
            if let source = draft.existing.flatMap({ model.record($0) }) {
                Text(source.title).font(.headline)
                if !source.shade.isEmpty { Text(source.shade).foregroundStyle(Theme.muted) }
            }
            Text(L.t("capture.question")).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { choices }
            } else {
                HStack(spacing: 7) { choices }
            }
            if let recordID {
                reasonField(recordID)
                if !model.failed && !model.writing {
                    Label(L.t("capture.saved"), systemImage: "checkmark.circle")
                        .font(.caption).foregroundStyle(Theme.muted).accessibilityIdentifier("capture.saved")
                }
            }
            if draft.existing == nil { fields }
        }
        .navigationTitle(L.t("capture.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: draft.id) {
            if let knownText { receive(knownText) }
            else if let photo = draft.photo {
                let result = await recognitionText(photo)
                if !Task.isCancelled { receive(result) }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(L.t("action.done")) { focus = false }.accessibilityIdentifier("capture.done")
            }
        }
    }

    private var savedVerdict: Verdict? {
        guard let id = recordID else { return nil }
        return model.record(id)?.trials.first { $0.id == draft.id }?.verdict
    }

    private var choices: some View {
        ForEach(Verdict.allCases) { verdict in
            Button { save(verdict) } label: {
                VStack(spacing: 6) {
                    Image(systemName: verdict.symbol).font(.system(size: 23, weight: .semibold))
                    Text(verdict.label).font(.subheadline.bold())
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 79)
                .foregroundStyle(Theme.ink)
                .background(verdict.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(verdict.hue, lineWidth: savedVerdict == verdict ? 3 : 1) }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(savedVerdict == verdict ? [.isSelected] : [])
            .accessibilityIdentifier("verdict." + verdict.rawValue)
        }
    }

    private func reasonField(_ id: UUID) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(L.t("reason.label")).font(.subheadline.bold())
            TextField(L.t("reason.prompt"), text: Binding(get: { reason }, set: { writeReason($0, to: id) }), axis: .vertical)
                .lineLimit(2...4)
                .padding(9).background(Theme.base, in: RoundedRectangle(cornerRadius: 10))
                .focused($focus).accessibilityIdentifier("capture.reason")
            if commerce.hasPro, !model.library.templates.isEmpty {
                Menu {
                    ForEach(model.library.templates) { item in
                        Button(item.text) { writeReason(item.text, to: id) }
                    }
                } label: {
                    Label(L.t("templates.use"), systemImage: "text.badge.plus").frame(minHeight: 44)
                }
                .accessibilityIdentifier("capture.templates")
            }
        }
        .padding(12).whiteCard()
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.t("capture.optional")).sectionHeading()
            if identified, !recognition.isEmpty {
                Text(L.t("capture.detected")).font(.caption.bold())
                Text(recognition).font(.caption).lineLimit(3).foregroundStyle(Theme.muted)
                if hints.name.isEmpty, let suggestion = firstLine {
                    Button {
                        hints.name = String(suggestion.prefix(120))
                        syncNames()
                    } label: {
                        Label(L.t("capture.suggestion"), systemImage: "text.viewfinder").frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("capture.suggestion")
                }
            }
            MetadataFields(brand: $hints.brand, product: $hints.name, shade: $hints.shade, alias: $hints.alias, scope: "capture")
        }
        .padding(12).whiteCard()
        .onChange(of: hints) { _, _ in syncNames() }
    }

    private var firstLine: String? {
        recognition.split(whereSeparator: \.isNewline).first.map(String.init)
    }

    private func receive(_ text: String) {
        recognition = text
        identified = true
        hints.recognized = text
        if draft.existing == nil, let id = recordID {
            model.edit(id) { record in record.recognized = text }
        }
    }

    private func syncNames() {
        if let id = recordID, draft.existing == nil {
            model.edit(id) { record in
                record.brand = hints.brand
                record.name = hints.name
                record.shade = hints.shade
                record.alias = hints.alias
            }
        }
    }

    private func writeReason(_ value: String, to id: UUID) {
        let limited = String(value.prefix(100))
        reason = limited
        model.correctTrial(id, trial: draft.id) { $0.reason = limited }
    }

    private func save(_ verdict: Verdict) {
        if let id = recordID {
            model.correctTrial(id, trial: draft.id) { $0.verdict = verdict }
        } else {
            let trial = Trial(id: draft.id, verdict: verdict, reason: reason, photo: draft.photo)
            recordID = model.saveTrial(trial, hints: hints, existing: draft.existing)
            if !Launch.testing { focus = true }
        }
    }

    @MainActor private func recognitionText(_ photo: UUID) async -> String {
        if Launch.testing { return ProcessInfo.processInfo.environment["TRIALREBUY_OCR"] ?? "" }
        guard let jpeg = try? await model.disk.recognitionImage(photo) else { return "" }
        return await PackageOCR.read(jpeg)
    }
}

struct MetadataFields: View {
    @Binding var brand: String
    @Binding var product: String
    @Binding var shade: String
    @Binding var alias: String
    let scope: String

    var body: some View {
        field("brand", text: $brand)
        field("product", text: $product)
        field("shade", text: $shade)
        field("alias", text: $alias)
    }

    private func field(_ key: String, text: Binding<String>) -> some View {
        TextField(L.t("field." + key), text: text)
            .padding(.horizontal, 9).frame(minHeight: 44)
            .background(Theme.base, in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier(scope + "." + key)
            .onChange(of: text.wrappedValue) { _, value in
                if value.count > 120 { text.wrappedValue = String(value.prefix(120)) }
            }
    }
}

struct MatchView: View {
    @EnvironmentObject private var model: LibraryModel
    let draft: CaptureDraft
    @Binding var path: [Route]
    @State private var recognized: String?
    @State private var result: ProductSearch.Match?

    var body: some View {
        Group {
            if let result {
                switch result {
                case .none:
                    CaptureView(draft: draft, missingMatch: true, knownText: recognized)
                case .exact(let id):
                    if let record = model.record(id) {
                        candidates([record], exact: true)
                    } else {
                        CaptureView(draft: draft, missingMatch: true, knownText: recognized)
                    }
                case .candidates(let ids):
                    candidates(ids.compactMap { model.record($0) }, exact: false)
                }
            } else {
                Screen {
                    if draft.photo != nil { PhotoTile(id: draft.photo, large: true).frame(height: 140) }
                    ProgressView(L.t("match.scanning")).accessibilityIdentifier("match.scanning")
                }
            }
        }
        .task(id: draft.id) {
            let text: String
            if Launch.testing {
                text = ProcessInfo.processInfo.environment["TRIALREBUY_OCR"] ?? (L.t("demo.brand") + "\n" + L.t("demo.lip"))
            } else if let photo = draft.photo, let jpeg = try? await model.disk.recognitionImage(photo) {
                text = await PackageOCR.read(jpeg)
            } else {
                text = ""
            }
            guard !Task.isCancelled else { return }
            recognized = text
            let match = ProductSearch.match(text, in: model.library.records)
            result = match
            if case .exact = match { model.completeCoreAction() }
        }
    }

    private func candidates(_ records: [ProductRecord], exact: Bool) -> some View {
        Screen {
            Text(L.t("match.last")).sectionHeading()
            Label(L.t(exact ? "match.exact" : "match.verify"), systemImage: exact ? "checkmark.circle" : "scope")
                .font(.footnote.weight(.semibold)).padding(10)
                .background(exact ? Theme.leaf : Theme.sand, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier(exact ? "match.exact" : "match.verify")
            ForEach(records) { record in
                RecordButton(record: record, scope: "match") {
                    if !exact { model.completeCoreAction() }
                    path.append(.detail(record.id))
                }
            }
            PrimaryButton(title: L.t("match.recordNew"), symbol: "plus", id: "match.new", secondary: true) {
                path.append(.capture(draft))
            }
        }
        .navigationTitle(L.t("match.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DetailView: View {
    @EnvironmentObject private var model: LibraryModel
    let id: UUID
    @Binding var path: [Route]
    @State private var editing: EditSheet?
    @State private var confirmDelete = false

    var body: some View {
        Screen {
            StorageNotice()
            if let record = model.record(id), let trial = record.latest {
                if let photo = record.photo { PhotoTile(id: photo, large: true, accessibilityID: "detail.photo").frame(height: 191) }
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.title2.bold())
                        if !record.shade.isEmpty { Text(record.shade).foregroundStyle(Theme.muted) }
                    }
                    Spacer(minLength: 6)
                    StatusPill(verdict: trial.verdict)
                }
                Text(L.t("detail.lastReason")).sectionHeading()
                VStack(alignment: .leading, spacing: 6) {
                    Text(trial.date.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(Theme.muted)
                    Text(trial.reason.isEmpty ? L.t("reason.empty") : trial.reason).font(.subheadline)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).whiteCard()
                HStack {
                    PrimaryButton(title: L.t("detail.append"), symbol: "plus", id: "detail.append") {
                        path.append(.capture(CaptureDraft(existing: id)))
                    }
                    PrimaryButton(title: L.t("detail.share"), symbol: "square.and.arrow.up", id: "detail.share", secondary: true) {
                        path.append(.share(id))
                    }
                }
                Text(L.t("detail.history")).sectionHeading()
                ForEach(record.trials.sorted { $0.date > $1.date }) { past in
                    Button { editing = EditSheet(trial: past.id) } label: {
                        IconRow(verdict: past.verdict,
                                title: past.date.formatted(date: .abbreviated, time: .omitted),
                                subtitle: past.reason.isEmpty ? L.t("reason.empty") : past.reason, photo: past.photo)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("history.trial." + past.id.uuidString)
                }
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label(L.t("record.delete"), systemImage: "trash").frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("detail.delete")
            }
        }
        .navigationTitle(L.t("detail.title")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = EditSheet(trial: nil) } label: {
                    Image(systemName: "square.and.pencil").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .accessibilityLabel(L.t("detail.edit"))
                .accessibilityIdentifier("detail.edit")
            }
        }
        .sheet(item: $editing) { item in EditView(id: id, trial: item.trial).environmentObject(model) }
        .alert(L.t("record.deleteTitle"), isPresented: $confirmDelete) {
            Button(L.t("record.delete"), role: .destructive) {
                if !path.isEmpty { path.removeLast() }
                model.delete(id)
            }
            Button(L.t("action.cancel"), role: .cancel) {}
        } message: { Text(L.t("record.deleteMessage")) }
    }

    private struct EditSheet: Identifiable {
        let id = UUID()
        let trial: UUID?
    }
}

struct EditView: View {
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    let id: UUID
    let trial: UUID?
    @State private var values = ProductRecord()
    @State private var verdict: Verdict = .retry
    @State private var reason = ""
    @State private var photo: UUID?
    @State private var picked: PhotosPickerItem?
    @State private var failed = false
    @State private var readingPhoto = false

    var body: some View {
        NavigationStack {
            Screen {
                if trial != nil {
                    Picker(L.t("capture.question"), selection: $verdict) {
                        ForEach(Verdict.allCases) { item in Text(item.label).tag(item) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("edit.verdict")
                    TextField(L.t("reason.prompt"), text: $reason, axis: .vertical)
                        .lineLimit(2...5).padding(12).whiteCard()
                        .accessibilityIdentifier("edit.reason")
                } else {
                    MetadataFields(brand: $values.brand, product: $values.name,
                                   shade: $values.shade, alias: $values.alias, scope: "edit")
                }
                if let photo { PhotoTile(id: photo, large: true).frame(height: 146) }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(L.t("detail.replacePhoto"), systemImage: "photo").frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityIdentifier("detail.replacePhoto")
                if readingPhoto { ProgressView() }
                if failed { Text(L.t("photo.failed")).font(.footnote) }
                PrimaryButton(title: L.t("action.save"), symbol: "checkmark", id: "edit.save") { save() }
                    .disabled(readingPhoto)
            }
            .navigationTitle(L.t("detail.edit")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("action.cancel")) { dismiss() }.accessibilityIdentifier("edit.cancel")
                }
            }
        }
        .onAppear {
            guard let record = model.record(id) else { return }
            values = record
            let initial = trial.flatMap { uuid in record.trials.first { $0.id == uuid } } ?? record.latest
            verdict = initial?.verdict ?? .retry
            reason = initial?.reason ?? ""
            photo = trial == nil ? record.photo : initial?.photo
        }
        .task(id: picked) {
            guard let picked else { return }
            readingPhoto = true
            defer { if !Task.isCancelled { readingPhoto = false } }
            do {
                guard let data = try await picked.loadTransferable(type: Data.self), data.count <= 40_000_000
                else { throw LibraryDisk.Failure.image }
                let id = try await model.disk.addPhoto(data).0
                if !Task.isCancelled { photo = id; failed = false }
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
    }

    private func save() {
        if let trial {
            model.correctTrial(id, trial: trial) { trial in
                trial.verdict = verdict
                trial.reason = String(reason.prefix(100))
                trial.photo = photo
            }
        } else {
            model.edit(id) { record in
                record.brand = String(values.brand.prefix(120))
                record.name = String(values.name.prefix(120))
                record.shade = String(values.shade.prefix(120))
                record.alias = String(values.alias.prefix(120))
                if let photo, photo != record.photo, let newest = record.latest,
                   let index = record.trials.firstIndex(where: { $0.id == newest.id }) {
                    record.trials[index].photo = photo
                }
            }
        }
        dismiss()
    }
}
