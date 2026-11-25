import Foundation

struct Entitlement: Codable, Equatable {
    static let duration: TimeInterval = 30 * 86_400
    var firstOpen = Date()
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var purchasedPro = false

    var trialStart: Date {
        let local = proStartedAt ?? firstOpen
        return min(local, trialClaimedAt ?? local)
    }
    var trialEnd: Date { trialStart.addingTimeInterval(Self.duration) }

    mutating func startPaidMode(at date: Date) {
        if proStartedAt == nil { proStartedAt = date }
    }

    func hasPro(at date: Date, free: Bool = Launch.isFree) -> Bool {
        free || purchasedPro || (date >= trialStart && date < trialEnd)
    }

    func daysLeft(at date: Date) -> Int {
        max(0, min(30, Int(ceil(trialEnd.timeIntervalSince(date) / 86_400))))
    }
}
