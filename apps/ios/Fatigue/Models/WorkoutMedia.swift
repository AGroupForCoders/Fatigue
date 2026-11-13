import AVFoundation
import CoreTransferable
import ImageIO
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// A photo or video kept with a workout, such as a form check or the machine's settings.
/// The file lives on this phone only for now; backing it up is a follow-up.
nonisolated struct WorkoutMedia: Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case photo, video
    }

    let id: UUID
    var workoutID: UUID
    let kind: Kind
    /// Such as "7A1C….heic", inside the media folder.
    let fileName: String
    /// Pixel size, the right way up.
    var width: Int?
    var height: Int?
    /// Seconds, videos only.
    var duration: TimeInterval?
    var createdAt: Date

    /// "0:42" for a video, nothing for a photo.
    var durationLabel: String? {
        guard kind == .video, let duration else { return nil }
        let seconds = Int(duration.rounded())
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// The photos and videos on every workout, and the files behind them.
///
/// Files are copied out of the picker into Application Support/media, named after the row's id, so they
/// stay when the photo library changes and aren't cleared like Caches. A thumbnail is made once per file
/// and kept next to it in media/thumbnails, then held in memory while the app runs.
@Observable
final class MediaStore {
    /// Everything that isn't deleted, by workout, oldest first.
    private(set) var byWorkout: [UUID: [WorkoutMedia]] = [:]
    /// Workouts with a pick still being copied in, so the row can show it's working.
    private(set) var importing: Set<UUID> = []
    private var thumbnails: [UUID: UIImage] = [:]
    @ObservationIgnored private var loadingThumbnails: Set<UUID> = []
    private let database: AppDatabase?
    let folder: URL

    /// Keeps everything in memory and the files in a scratch folder, as tests and previews do.
    init(folder: URL = FileManager.default.temporaryDirectory.appending(path: "media-\(UUID().uuidString)")) {
        database = nil
        self.folder = folder
    }

    /// Loads what's saved on the phone.
    init(database: AppDatabase, folder: URL = URL.applicationSupportDirectory.appending(path: "media")) {
        self.database = database
        self.folder = folder
        let rows = (try? database.media()) ?? []
        byWorkout = Dictionary(grouping: rows.compactMap(WorkoutMedia.init(stored:)), by: \.workoutID)
    }

    /// The most photos and videos one workout can hold.
    static let limit = 3

    func media(for workoutID: UUID) -> [WorkoutMedia] { byWorkout[workoutID] ?? [] }

    /// How many more a workout can take before it reaches the limit. Never negative, so a workout
    /// saved with more than the limit before there was one keeps what it has and takes no more.
    func room(for workoutID: UUID) -> Int { max(0, Self.limit - media(for: workoutID).count) }

    /// The first photo or video on a workout, for its history row.
    func cover(for workoutID: UUID) -> WorkoutMedia? { byWorkout[workoutID]?.first }

    func fileURL(for media: WorkoutMedia) -> URL { folder.appending(path: media.fileName) }

    private func thumbnailURL(for media: WorkoutMedia) -> URL {
        folder.appending(path: "thumbnails").appending(path: "\(media.id.uuidString).jpg")
    }

    // MARK: Adding

    /// Copies what was picked into the media folder and puts it on the workout. Each pick is saved as soon
    /// as it's in, so a slow iCloud download for one doesn't hold up the others. Picks that can't be read are skipped,
    /// and so are any past the limit.
    func add(_ picks: [PhotosPickerItem], to workoutID: UUID) async {
        let picks = Array(picks.prefix(room(for: workoutID)))
        guard !picks.isEmpty else { return }
        importing.insert(workoutID)
        defer { importing.remove(workoutID) }
        let folder = folder
        for pick in picks {
            let id = UUID()
            let imported = await Task.detached(priority: .userInitiated) { () -> (WorkoutMedia, UIImage?)? in
                guard let file = try? await pick.loadTransferable(type: PickedMediaFile.self) else { return nil }
                return try? await MediaFiles.store(file, id: id, workoutID: workoutID, in: folder)
            }.value
            guard let imported else { continue }
            let (media, thumbnail) = imported
            // Checked again here, since another pick for the same workout can finish while this one copies.
            guard room(for: workoutID) > 0 else {
                removeFiles(of: media)
                break
            }
            if let thumbnail { thumbnails[media.id] = thumbnail }
            byWorkout[workoutID, default: []].append(media)
            let stored = media.stored
            persist { try $0.insert(stored) }
        }
    }

    // MARK: Removing and moving

    func delete(_ media: WorkoutMedia) {
        byWorkout[media.workoutID]?.removeAll { $0.id == media.id }
        if byWorkout[media.workoutID]?.isEmpty == true { byWorkout[media.workoutID] = nil }
        thumbnails[media.id] = nil
        persist { try $0.deleteMedia(id: media.id.uuidString) }
        removeFiles(of: media)
    }

    /// Forgets every photo and video and deletes their files, after the database was wiped.
    func forgetAll() {
        byWorkout = [:]
        thumbnails = [:]
        let folder = folder
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
    }

    /// Removes everything on a workout, for when the workout is deleted or thrown away.
    func deleteAll(for workoutID: UUID) {
        guard let items = byWorkout.removeValue(forKey: workoutID) else { return }
        for media in items {
            thumbnails[media.id] = nil
            removeFiles(of: media)
        }
        persist { try $0.deleteMedia(workoutId: workoutID.uuidString) }
    }

    /// Moves everything on one workout to another, for when finishing saves the workout under a new id.
    func move(from workoutID: UUID, to newWorkoutID: UUID) {
        guard workoutID != newWorkoutID, let items = byWorkout.removeValue(forKey: workoutID) else { return }
        let moved = items.map { media in
            var media = media
            media.workoutID = newWorkoutID
            return media
        }
        byWorkout[newWorkoutID, default: []].append(contentsOf: moved)
        persist { try $0.moveMedia(from: workoutID.uuidString, to: newWorkoutID.uuidString) }
    }

    private func removeFiles(of media: WorkoutMedia) {
        let urls = [fileURL(for: media), thumbnailURL(for: media)]
        Task.detached(priority: .utility) {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
    }

    // MARK: Thumbnails

    /// The small image for a row, once it's ready. Nil the first time, while it loads from disk or is made.
    func thumbnail(for media: WorkoutMedia) -> UIImage? {
        if let image = thumbnails[media.id] { return image }
        if loadingThumbnails.insert(media.id).inserted {
            Task { await loadThumbnail(for: media) }
        }
        return nil
    }

    private func loadThumbnail(for media: WorkoutMedia) async {
        let file = fileURL(for: media)
        let thumbnail = thumbnailURL(for: media)
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            if let saved = UIImage(contentsOfFile: thumbnail.path(percentEncoded: false)) { return saved }
            guard let made = try? await MediaFiles.makeThumbnail(of: file, kind: media.kind) else { return nil }
            try? MediaFiles.write(thumbnail: made, to: thumbnail)
            return made
        }.value
        loadingThumbnails.remove(media.id)
        guard let image else { return }
        thumbnails[media.id] = image
    }

    /// Runs a database write, if there's a database. A failed write is logged rather than shown.
    private func persist(_ write: (AppDatabase) throws -> Void) {
        guard let database else { return }
        do { try write(database) } catch {
            #if DEBUG
            print("Saving media failed: \(error)")
            #endif
        }
    }
}

// MARK: - Files

/// What the picker hands over: a copy of the file in the app's temporary folder, and whether it's a photo or video.
nonisolated struct PickedMediaFile: Transferable {
    let url: URL
    let kind: WorkoutMedia.Kind

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            PickedMediaFile(url: try stash(received.file), kind: .video)
        }
        // Loaded as data rather than a file, as Apple's picker sample does, so HEIC and other formats come through.
        DataRepresentation(importedContentType: .image) { data in
            PickedMediaFile(url: try stash(data), kind: .photo)
        }
    }

    /// The picker's file is only readable inside the import closure, so it's copied out first.
    private static func stash(_ file: URL) throws -> URL {
        let target = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(file.pathExtension.isEmpty ? "mov" : file.pathExtension.lowercased())")
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }

    private static func stash(_ data: Data) throws -> URL {
        let type = CGImageSourceCreateWithData(data as CFData, nil)
            .flatMap(CGImageSourceGetType)
            .flatMap { UTType($0 as String) }
        let target = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).\(type?.preferredFilenameExtension ?? "jpg")")
        try data.write(to: target, options: .atomic)
        return target
    }
}

/// Reading and writing media files, off the main actor.
nonisolated enum MediaFiles {
    /// The longest side of a thumbnail, in pixels.
    static let thumbnailSize: CGFloat = 480

    /// Moves a picked file into the media folder as `<id>.<ext>`, reads its size and length, and makes its thumbnail.
    static func store(_ picked: PickedMediaFile, id: UUID, workoutID: UUID, in folder: URL) async throws -> (WorkoutMedia, UIImage?) {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder.appending(path: "thumbnails"), withIntermediateDirectories: true)
        let fileName = "\(id.uuidString).\(picked.url.pathExtension)"
        let destination = folder.appending(path: fileName)
        try? fileManager.removeItem(at: destination)
        try fileManager.moveItem(at: picked.url, to: destination)

        var media = WorkoutMedia(id: id, workoutID: workoutID, kind: picked.kind, fileName: fileName, createdAt: .now)
        switch picked.kind {
        case .photo:
            if let size = imageSize(of: destination) {
                media.width = Int(size.width)
                media.height = Int(size.height)
            }
        case .video:
            let asset = AVURLAsset(url: destination)
            if let duration = try? await asset.load(.duration), duration.isNumeric { media.duration = duration.seconds }
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               case let (natural, transform)? = try? await track.load(.naturalSize, .preferredTransform) {
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                media.width = Int(abs(rect.width).rounded())
                media.height = Int(abs(rect.height).rounded())
            }
        }
        let thumbnail = try? await makeThumbnail(of: destination, kind: picked.kind)
        if let thumbnail { try? write(thumbnail: thumbnail, to: folder.appending(path: "thumbnails").appending(path: "\(id.uuidString).jpg")) }
        return (media, thumbnail)
    }

    /// Pixel size with the orientation applied, so a portrait photo reads as portrait.
    static func imageSize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
        return orientation >= 5 ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    /// A small image for the row: the photo scaled down, or the video's first frame.
    static func makeThumbnail(of url: URL, kind: WorkoutMedia.Kind) async throws -> UIImage? {
        switch kind {
        case .photo:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailSize,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { UIImage(cgImage: $0) }
        case .video:
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: thumbnailSize, height: thumbnailSize)
            let (image, _) = try await generator.image(at: .zero)
            return UIImage(cgImage: image)
        }
    }

    static func write(thumbnail: UIImage, to url: URL) throws {
        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else { return }
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Storage

extension WorkoutMedia {
    var stored: StoredMedia {
        StoredMedia(
            id: id.uuidString, workoutId: workoutID.uuidString, kind: kind.rawValue, fileName: fileName,
            width: width, height: height, durationSeconds: duration, createdAt: createdAt
        )
    }

    /// Nil when the row's ids or kind can't be read, which only an outside write could cause.
    init?(stored: StoredMedia) {
        guard let id = UUID(uuidString: stored.id), let workoutID = UUID(uuidString: stored.workoutId), let kind = Kind(rawValue: stored.kind) else { return nil }
        self.init(id: id, workoutID: workoutID, kind: kind, fileName: stored.fileName, width: stored.width, height: stored.height,
                  duration: stored.durationSeconds, createdAt: stored.createdAt)
    }
}
