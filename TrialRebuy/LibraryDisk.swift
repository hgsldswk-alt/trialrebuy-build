import Foundation
import ImageIO
import UniformTypeIdentifiers

struct Backup: Codable {
    let version: Int
    let library: Library
    let photos: [String: Data]
}

actor LibraryDisk {
    enum Failure: Error { case invalid, missingPhoto, image }
    static let backupLimit = 150_000_000
    static let photoLimit = 8_000_000
    private var savedRevision = 0
    private var directory: URL?

    init(directory: URL? = nil) { self.directory = directory }

    private func root() throws -> URL {
        if let directory { return directory }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let folder = base.appendingPathComponent(Launch.testing ? "TrialRebuyUITest" : "TrialRebuy", isDirectory: true)
        try prepareFolder(folder)
        directory = folder
        return folder
    }

    private func prepareFolder(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var url = folder
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    func load(reset: Bool) throws -> Library {
        let folder = try root()
        let file = folder.appendingPathComponent("library.json")
        if reset {
            try FileManager.default.removeItem(at: folder)
            try prepareFolder(folder)
            savedRevision = 0
        }
        let library = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode(Library.self, from: Data(contentsOf: file)) : Library()
        if let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            let referenced = Set(library.photoIDs.map(\.uuidString))
            for url in files where ["jpg", "thumb"].contains(url.pathExtension) &&
                UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil &&
                !referenced.contains(url.deletingPathExtension().lastPathComponent) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        return library
    }

    func save(_ library: Library, revision: Int) throws {
        guard revision > savedRevision else { return }
        let file = try root().appendingPathComponent("library.json")
        try JSONEncoder().encode(library).write(to: file, options: .atomic)
        savedRevision = revision
    }

    private func photoURL(_ id: UUID, thumbnail: Bool = false) throws -> URL {
        try root().appendingPathComponent(id.uuidString).appendingPathExtension(thumbnail ? "thumb" : "jpg")
    }

    func discardPhoto(_ id: UUID) {
        for thumbnail in [false, true] {
            if let url = try? photoURL(id, thumbnail: thumbnail) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func shareFolder() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TrialRebuyShares", isDirectory: true)
        let props: Set<URLResourceKey> = [.contentModificationDateKey]
        if let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(props)) {
            let expiry = Date.now.addingTimeInterval(-86_400)
            for folder in folders where ((try? folder.resourceValues(forKeys: props).contentModificationDate) ?? .distantPast) < expiry {
                try? FileManager.default.removeItem(at: folder)
            }
        }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func removeShareFolder(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    func writePNG(_ cgImage: CGImage, index: Int, into folder: URL) throws -> URL {
        let url = folder.appendingPathComponent("TrialRebuy-\(index + 1).png")
        guard let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.image }
        CGImageDestinationAddImage(writer, cgImage, nil)
        guard CGImageDestinationFinalize(writer) else { throw Failure.image }
        return url
    }

    func thumbnail(_ id: UUID) -> Data? {
        guard let url = try? photoURL(id, thumbnail: true) else { return nil }
        return try? Data(contentsOf: url)
    }

    func addPhoto(_ data: Data) throws -> (UUID, Data) {
        let id = UUID()
        let full = try Self.jpeg(data, pixels: 4096)
        guard full.count <= Self.photoLimit else { throw Failure.image }
        let thumb = try Self.jpeg(full, pixels: 640)
        try full.write(to: photoURL(id), options: .atomic)
        try thumb.write(to: photoURL(id, thumbnail: true), options: .atomic)
        return (id, thumb)
    }

    func recognitionImage(_ id: UUID) throws -> Data {
        try Self.jpeg(Data(contentsOf: photoURL(id)), pixels: 2200)
    }

    static func jpeg(_ data: Data, pixels: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels
              ] as CFDictionary) else { throw Failure.image }
        let result = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(result, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw Failure.image }
        CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw Failure.image }
        return result as Data
    }

    func export(_ library: Library) throws -> Data {
        var photos = [String: Data]()
        var rawSize = 0
        for id in library.photoIDs {
            let data = try Data(contentsOf: photoURL(id))
            rawSize += data.count
            guard rawSize <= Self.backupLimit * 3 / 4 else { throw Failure.invalid }
            photos[id.uuidString] = data
        }
        var snapshot = library
        snapshot.review = ReviewProgress()
        snapshot.pendingMilestones = []
        let data = try JSONEncoder().encode(Backup(version: 1, library: snapshot, photos: photos))
        guard data.count <= Self.backupLimit else { throw Failure.invalid }
        return data
    }

    func read(_ url: URL, limit: Int) throws -> Data {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            guard let chunk = try handle.read(upToCount: min(1_048_576, limit + 1 - data.count)),
                  !chunk.isEmpty else { return data }
            data.append(chunk)
        }
        throw Failure.invalid
    }

    func preview(_ data: Data) throws -> Backup {
        guard data.count <= Self.backupLimit else { throw Failure.invalid }
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        let library = backup.library
        let trialIDs = library.records.flatMap { $0.trials.map(\.id) }
        guard backup.version == 1, library.records.count <= 50_000,
              Set(library.records.map(\.id)).count == library.records.count,
              Set(trialIDs).count == trialIDs.count,
              Set(library.templates.map(\.id)).count == library.templates.count,
              library.milestones.isSubset(of: [5, 15, 30]),
              Set(backup.photos.keys) == Set(library.photoIDs.map(\.uuidString)),
              library.templates.allSatisfy({ !$0.text.isEmpty && $0.text.count <= 100 }),
              library.records.allSatisfy({ record in
                  !record.trials.isEmpty && record.trials.allSatisfy { $0.reason.count <= 100 } &&
                  [record.brand, record.name, record.shade, record.alias].allSatisfy { $0.count <= 120 } &&
                  record.recognized.count <= 4_000
              }) else { throw Failure.invalid }
        for photo in backup.photos.values {
            guard photo.count <= Self.photoLimit,
                  let source = CGImageSourceCreateWithData(photo as CFData, nil),
                  let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
                  let width = info[kCGImagePropertyPixelWidth as String] as? Int,
                  let height = info[kCGImagePropertyPixelHeight as String] as? Int,
                  (1...8192).contains(width), (1...8192).contains(height),
                  let type = CGImageSourceGetType(source), type as String == UTType.jpeg.identifier else { throw Failure.image }
        }
        return backup
    }

    func stageRestore(_ backup: Backup, skipping existing: Set<UUID>) throws -> Library {
        var library = backup.library
        library.records.removeAll { existing.contains($0.id) }
        var remapped = [UUID: UUID]()
        for id in library.photoIDs {
            guard let photo = backup.photos[id.uuidString] else { throw Failure.missingPhoto }
            remapped[id] = try addPhoto(photo).0
        }
        for i in library.records.indices {
            for j in library.records[i].trials.indices {
                if let photo = library.records[i].trials[j].photo {
                    library.records[i].trials[j].photo = remapped[photo]
                }
            }
        }
        return library
    }

    func parseCSV(_ url: URL) throws -> [ProductRecord] {
        try CSVImport.parse(read(url, limit: CSVImport.limit))
    }
}
