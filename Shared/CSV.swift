import Foundation

enum CSVImport {
    enum Failure: Error { case invalid }
    static let limit = 2_000_000

    static func parse(_ data: Data) throws -> [ProductRecord] {
        guard data.count <= limit, let input = String(data: data, encoding: .utf8) else { throw Failure.invalid }
        let lines = try rows(input.drop(while: { $0 == "\u{FEFF}" }))
        guard let first = lines.first, first.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) ==
                ["brand", "product", "shade", "verdict", "reason"], lines.count > 1, lines.count <= 2_001 else {
            throw Failure.invalid
        }
        return try lines.dropFirst().map { row in
            guard row.count == 5, let verdict = Verdict(rawValue: row[3].trimmingCharacters(in: .whitespaces).lowercased()),
                  !row[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  row.prefix(3).allSatisfy({ $0.count <= 120 }), row[4].count <= 100 else { throw Failure.invalid }
            return ProductRecord(brand: row[0], name: row[1], shade: row[2],
                                 trials: [Trial(verdict: verdict, reason: row[4])])
        }
    }

    private static func rows(_ input: Substring) throws -> [[String]] {
        enum State { case open, quoted, closed }
        var state = State.open
        var field = ""
        var row = [String]()
        var table = [[String]]()
        func finishField() { row.append(field); field = ""; state = .open }
        func finishRow() {
            finishField()
            if row.count > 1 || row.first != "" { table.append(row) }
            row.removeAll()
        }
        for character in input {
            switch (state, character) {
            case (.quoted, "\""): state = .closed
            case (.closed, "\""): field.append("\""); state = .quoted
            case (.open, "\"") where field.isEmpty: state = .quoted
            case (.open, "\""): throw Failure.invalid
            case (.quoted, _): field.append(character)
            case (_, ","): finishField()
            case (_, "\r\n"), (_, "\n"), (_, "\r"): finishRow()
            case (.closed, _): throw Failure.invalid
            case (.open, _): field.append(character)
            }
        }
        guard state != .quoted else { throw Failure.invalid }
        finishRow()
        return table
    }
}
