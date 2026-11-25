import Foundation

enum Launch {
    static let freePeriod = false
    static let arguments = ProcessInfo.processInfo.arguments
    static let testing = arguments.contains("-ui-testing")
    static let proID = "com.hgsldswk.trialrebuy.pro"
    static let trialID = "com.hgsldswk.trialrebuy.trial"

    static func isFree(arguments: [String]) -> Bool {
        freePeriod && !(arguments.contains("-ui-testing") &&
            arguments.contains(where: { ["-paid-mode", "-paywall", "-expired"].contains($0) }))
    }

    static var isFree: Bool { isFree(arguments: arguments) }
    static var downloadURL: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String,
              !id.isEmpty, id.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return "https://apps.apple.com/app/id" + id
    }
}
