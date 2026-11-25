import CoreImage
import Foundation
import XCTest

final class CoreTests: XCTestCase {
    private func lipstick(brand: String = "霧島", shade: String) -> ProductRecord {
        ProductRecord(brand: brand, name: "絲絨唇膏", shade: shade, trials: [Trial(verdict: .buy)])
    }

    func testBrandNormalizationAndMultipleShadesRemainCandidates() {
        let first = lipstick(shade: "05 栗棕")
        let second = lipstick(shade: "02 豆沙")
        let records = [first, second]
        XCTAssertEqual(Set(ProductSearch.search("雾岛 丝绒 ０５", in: records).map(\.id)), [first.id])
        guard case .candidates(let ids) = ProductSearch.match("雾岛", in: records) else { return XCTFail("Expected candidates") }
        XCTAssertEqual(Set(ids), [first.id, second.id])
    }

    func testExactRequiresBrandProductAndEvidencedShade() {
        let first = lipstick(brand: "Mist Isle", shade: "05 Chestnut")
        let second = lipstick(brand: "Mist Isle", shade: "02 Dusty Rose")
        let records = [first, second]
        XCTAssertEqual(ProductSearch.match("MIST-ISLE\n丝绒唇膏\n０５ Chestnut", in: records), .exact(first.id))
        XCTAssertEqual(ProductSearch.match("Other label", in: records), .none)
        for text in ["Mist Isle 丝绒唇膏 105 Chestnut",
                     "Mist Isle 丝绒唇膏 05 Chestnut 02 Dusty Rose"] {
            guard case .candidates(let ids) = ProductSearch.match(text, in: records) else { return XCTFail(text) }
            XCTAssertEqual(Set(ids), [first.id, second.id])
        }
    }

    func testNoShadeNeverAutoConfirmsBrandOrProduct() {
        let record = lipstick(shade: "")
        XCTAssertEqual(ProductSearch.match("霧島 絲絨唇膏", in: [record]), .candidates([record.id]))
    }

    func testSearchIncludesOCRTextAndUsesNewestReason() {
        let earlier = Trial(date: Date(timeIntervalSince1970: 1), verdict: .buy, reason: "old")
        let later = Trial(date: Date(timeIntervalSince1970: 2), verdict: .skip)
        let record = ProductRecord(recognized: "LOOSE POWDER M05", trials: [later, earlier])
        XCTAssertEqual(ProductSearch.search("loose m05", in: [record]).first?.id, record.id)
        XCTAssertNil(ProductSearch.search("m06", in: [record]).first)
        XCTAssertEqual(record.latest?.verdict, .skip)
        XCTAssertEqual(record.latest?.reason, "")
    }

    func testStyleRoundTripAndInvalidInput() {
        let original = ShareStyle(palette: .sand, preferPhotos: true)
        let code = ShareCode.encode(original)
        XCTAssertEqual(ShareCode.decode(" \n" + code + "\n"), original)
        XCTAssertEqual(ShareCode.encode(try XCTUnwrap(ShareCode.decode(code))), code)
        XCTAssertNil(ShareCode.decode(code.replacingOccurrences(of: "TRY1:", with: "TRY2:")))
        XCTAssertNil(ShareCode.decode("TRY1:" + String(repeating: "A", count: 500)))
        XCTAssertNil(ShareCode.decode(code + "?"))
        let json = Data(#"{"palette":"rose","preferPhotos":false,"records":[]}"#.utf8)
        XCTAssertNil(ShareCode.decode("TRY1:" + json.base64EncodedString()))
    }

    func testTrialUsesFirstOpenAndEarlyReceiptWithoutExtending() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var value = Entitlement(firstOpen: start)
        XCTAssertTrue(value.hasPro(at: start, free: false))
        XCTAssertFalse(value.hasPro(at: start.addingTimeInterval(-1), free: false))
        XCTAssertTrue(value.hasPro(at: start.addingTimeInterval(Entitlement.duration - 1), free: false))
        XCTAssertFalse(value.hasPro(at: value.trialEnd, free: false))
        value.trialClaimedAt = start.addingTimeInterval(86_400)
        XCTAssertEqual(value.trialStart, start)
        value.trialClaimedAt = start.addingTimeInterval(-86_400)
        XCTAssertEqual(value.trialStart, start.addingTimeInterval(-86_400))
        XCTAssertEqual(value.daysLeft(at: value.trialEnd), 0)
    }

    func testPaidModeMigrationAndLifetimeAccess() throws {
        let older = Date(timeIntervalSince1970: 1_600_000_000)
        let paid = older.addingTimeInterval(60 * 86_400)
        var value = Entitlement(firstOpen: older)
        value.startPaidMode(at: paid)
        value.startPaidMode(at: paid.addingTimeInterval(60))
        XCTAssertEqual(value.trialStart, paid)
        let later = paid.addingTimeInterval(31 * 86_400)
        XCTAssertFalse(value.hasPro(at: later, free: false))
        XCTAssertTrue(value.hasPro(at: later, free: true))
        value.purchasedPro = true
        let restored = try JSONDecoder().decode(Entitlement.self, from: JSONEncoder().encode(value))
        XCTAssertTrue(restored.hasPro(at: later, free: false))
    }

    func testBackupMergePreservesExistingAndDoesNotRetriggerMilestones() {
        var local = Library()
        local.records = (0..<5).map { _ in lipstick(shade: "05") }
        local.checkMilestones()
        XCTAssertEqual(local.pendingMilestones, [5])
        local.pendingMilestones = []
        local.records.removeLast()
        var identical = local.records[0]
        identical.shade = "Do not replace"
        let another = lipstick(shade: "02")
        var backup = Library()
        backup.records = [identical, another]
        local.merge(backup)
        local.checkMilestones()
        local.merge(backup)
        XCTAssertEqual(local.records.count, 5)
        XCTAssertEqual(local.records.first?.shade, "05")
        XCTAssertTrue(local.pendingMilestones.isEmpty)
    }

    func testThirdDistinctUseDayNeedsCoreActionAndVersionIsRecorded() throws {
        var progress = ReviewProgress()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        progress.complete(at: day, calendar: calendar)
        progress.complete(at: day.addingTimeInterval(10), calendar: calendar)
        progress.use(at: day.addingTimeInterval(86_400), calendar: calendar)
        progress.use(at: day.addingTimeInterval(172_800), calendar: calendar)
        XCTAssertFalse(progress.canRequest(version: "1.0"))
        progress.complete(at: day.addingTimeInterval(172_800), calendar: calendar)
        XCTAssertTrue(progress.canRequest(version: "1.0"))
        progress.markRequested(version: "1.0")
        XCTAssertFalse(progress.canRequest(version: "1.0"))
        XCTAssertFalse(progress.canRequest(version: "1.1"))
        progress.complete(at: day.addingTimeInterval(172_800), calendar: calendar)
        XCTAssertFalse(progress.canRequest(version: "1.0"))
        XCTAssertTrue(progress.canRequest(version: "1.1"))
    }

    func testCSVSupportsQuotesCRLFAndRejectsInvalidRows() throws {
        let csv = "brand,product,shade,verdict,reason\r\nMist Isle,\"Velvet, Night\",05,skip,\"A \"\"strong\"\" color\"\r\n"
        let products = try CSVImport.parse(Data(csv.utf8))
        XCTAssertEqual(products.first?.name, "Velvet, Night")
        XCTAssertEqual(products.first?.latest?.reason, "A \"strong\" color")
        XCTAssertEqual(products.first?.latest?.verdict, .skip)
        for text in [csv.replacingOccurrences(of: ",skip,", with: ",unknown,"),
                     csv.replacingOccurrences(of: "\"\r\n", with: "\r\n")] {
            XCTAssertThrowsError(try CSVImport.parse(Data(text.utf8)))
        }
    }

    func testQRCodeRoundTripWithCIDetector() throws {
        let url = "https://apps.apple.com/app/id123456789"
        let image = try XCTUnwrap(DownloadQR.image(for: url))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: context,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for scale in [1.0, 0.5] {
            let input = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let decoded = detector.features(in: input).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertTrue(decoded.contains(url))
        }
    }

    func testDiskBackupRoundTripValidatesPhotosAndKeepsNewestWrite() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let home = base.appendingPathComponent("library", isDirectory: true)
        let replacement = base.appendingPathComponent("restored", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let image = try XCTUnwrap(DownloadQR.image(for: "#TrialRebuy"))
        let context = CIContext(options: [.useSoftwareRenderer: true])
        let jpeg = try XCTUnwrap(context.jpegRepresentation(of: CIImage(cgImage: image),
                                                             colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:]))
        let disk = LibraryDisk(directory: home)
        let (photoID, _) = try await disk.addPhoto(jpeg)
        var library = Library()
        var product = lipstick(shade: "05")
        product.trials[0].photo = photoID
        library.records = [product]
        library.review.days = ["local-only"]
        try await disk.save(library, revision: 2)
        try await disk.save(Library(), revision: 1)
        let current = try await disk.load(reset: false)
        XCTAssertEqual(current, library)

        let file = try await disk.export(library)
        let verified = try await disk.preview(file)
        XCTAssertEqual(verified.version, 1)
        XCTAssertEqual(verified.photos.count, 1)
        XCTAssertTrue(verified.library.review.days.isEmpty)
        let restore = LibraryDisk(directory: replacement)
        let restored = try await restore.stageRestore(verified, skipping: [])
        XCTAssertEqual(restored.records.first?.id, product.id)
        let restoredID = try XCTUnwrap(restored.records.first?.photo)
        XCTAssertNotEqual(restoredID, photoID)
        let thumbnail = await restore.thumbnail(restoredID)
        XCTAssertNotNil(thumbnail)

        let broken = try JSONEncoder().encode(Backup(version: 1, library: library, photos: [:]))
        do {
            _ = try await disk.preview(broken)
            XCTFail("Missing photo was accepted")
        } catch LibraryDisk.Failure.invalid {
        }
    }

    func testAppTranslationsReachHostlessBundle() {
        XCTAssertTrue(["试用回购卡", "Beauty Inventory", "試用回購卡"].contains(L.t("app.name")))
    }
}
