import Foundation

enum Verdict: String, CaseIterable, Codable, Identifiable {
    case buy, retry, skip
    var id: String { rawValue }
    var label: String { L.t("verdict." + rawValue) }
}

struct Trial: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var verdict: Verdict
    var reason = ""
    var photo: UUID?
}

struct ProductRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var brand = ""
    var name = ""
    var shade = ""
    var alias = ""
    var recognized = ""
    var trials: [Trial] = []

    var latest: Trial? {
        trials.max {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }
    var title: String {
        let named = [brand, name].filter { !$0.isEmpty }.joined(separator: " ")
        return named.isEmpty ? L.t("record.unnamed") : named
    }
    var shareName: String {
        let productName = name.isEmpty ? brand : name
        return productName.isEmpty ? L.t("record.unnamed") : productName
    }
    var photo: UUID? {
        trials.filter { $0.photo != nil }.max { $0.date < $1.date }?.photo
    }

    static func sorted(_ records: [Self]) -> [Self] {
        records.sorted { ($0.latest?.date ?? .distantPast) > ($1.latest?.date ?? .distantPast) }
    }
}

enum ProductSearch {
    enum Match: Equatable { case exact(UUID), candidates([UUID]), none }

    static func canonical(_ text: String) -> String {
        let traditional = text.applyingTransform(StringTransform(rawValue: "Traditional-Simplified"), reverse: false) ?? text
        return traditional.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    static func normalize(_ text: String) -> String {
        canonical(text).filter { $0.isLetter || $0.isNumber }
    }

    static func search(_ query: String, in records: [ProductRecord]) -> [ProductRecord] {
        let terms = query.split(whereSeparator: \.isWhitespace).map { normalize(String($0)) }.filter { !$0.isEmpty }
        return ProductRecord.sorted(records).filter { record in
            let index = normalize([record.brand, record.name, record.shade, record.alias, record.recognized].joined(separator: " "))
            return terms.allSatisfy { index.contains($0) }
        }
    }

    static func match(_ text: String, in records: [ProductRecord]) -> Match {
        let scanned = canonical(text)
        func contains(_ value: String) -> Bool {
            let compact = normalize(value)
            guard !compact.isEmpty else { return false }
            if compact.count == 1 && compact.allSatisfy({ $0.isASCII }) { return false }
            let words = canonical(value).split { !$0.isLetter && !$0.isNumber }
            let flexible = words.map { NSRegularExpression.escapedPattern(for: String($0)) }
                .joined(separator: #"[^\p{L}\p{N}]*"#)
            let left = compact.first?.isASCII == true ? #"(?<![A-Za-z0-9])"# : ""
            let right = compact.last?.isASCII == true ? #"(?![A-Za-z0-9])"# : ""
            return scanned.range(of: left + flexible + right, options: .regularExpression) != nil
        }
        var exact = [UUID]()
        var candidates = [UUID]()
        for record in ProductRecord.sorted(records) {
            let brand = contains(record.brand)
            let name = contains(record.name)
            let shade = contains(record.shade)
            let alias = contains(record.alias)
            guard brand || name || alias else { continue }
            candidates.append(record.id)
            let distinctName = normalize(record.name) != normalize(record.brand)
            if brand && name && distinctName && shade { exact.append(record.id) }
        }
        if exact.count == 1, let id = exact.first { return .exact(id) }
        return candidates.isEmpty ? .none : .candidates(candidates)
    }
}

struct ShareStyle: Codable, Equatable {
    enum Palette: String, CaseIterable, Codable, Identifiable {
        case rose, sand, leaf
        var id: Self { self }
        var label: String { L.t("palette." + rawValue) }
    }
    var palette: Palette = .rose
    var preferPhotos = false
}

enum ShareCode {
    static let prefix = "TRY1:"
    static let maxLength = 256

    static func encode(_ style: ShareStyle) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let data = try? encoder.encode(style) else { return "" }
        return prefix + data.base64EncodedString()
    }

    static func decode(_ text: String) -> ShareStyle? {
        let code = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count <= maxLength, code.hasPrefix(prefix),
              let data = Data(base64Encoded: String(code.dropFirst(prefix.count))),
              let style = try? JSONDecoder().decode(ShareStyle.self, from: data),
              encode(style) == code else { return nil }
        return style
    }
}

struct ReasonTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
}

struct ReviewProgress: Codable, Equatable {
    var days: Set<String> = []
    var qualified = false
    var requestedVersion: String?

    mutating func use(at date: Date, calendar: Calendar = .current) {
        let day = calendar.dateComponents([.era, .year, .month, .day], from: date)
        let key = [day.era, day.year, day.month, day.day].map { String($0 ?? 0) }.joined(separator: "-")
        days.insert(key)
    }

    mutating func complete(at date: Date, calendar: Calendar = .current) {
        use(at: date, calendar: calendar)
        if days.count >= 3 { qualified = true }
    }

    func canRequest(version: String) -> Bool { qualified && requestedVersion != version }

    mutating func markRequested(version: String) {
        requestedVersion = version
        qualified = false
    }
}

struct Library: Codable, Equatable {
    var records: [ProductRecord] = []
    var style = ShareStyle()
    var templates: [ReasonTemplate] = []
    var milestones: Set<Int> = []
    var pendingMilestones: [Int] = []
    var review = ReviewProgress()

    var photoIDs: Set<UUID> { Set(records.flatMap { $0.trials.compactMap(\.photo) }) }

    mutating func checkMilestones() {
        for threshold in [5, 15, 30] where records.count >= threshold && !milestones.contains(threshold) {
            milestones.insert(threshold)
            pendingMilestones.append(threshold)
        }
    }

    mutating func merge(_ backup: Library) {
        if records.isEmpty && style == ShareStyle() { style = backup.style }
        var existing = Set(records.map(\.id))
        var trialIDs = Set(records.flatMap { $0.trials.map(\.id) })
        for var record in backup.records where !existing.contains(record.id) {
            record.trials = record.trials.filter { trialIDs.insert($0.id).inserted }
            if !record.trials.isEmpty {
                records.append(record)
                existing.insert(record.id)
            }
        }
        let templateIDs = Set(templates.map(\.id))
        templates += backup.templates.filter { !templateIDs.contains($0.id) }
        milestones.formUnion(backup.milestones)
        for threshold in [5, 15, 30] where records.count >= threshold { milestones.insert(threshold) }
    }
}
