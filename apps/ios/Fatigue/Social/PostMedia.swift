import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A photo or video on a shared workout, as the API returns it. `url` is a download link that stops
/// working at `expiresAt`; loading the feed again hands out fresh ones.
nonisolated struct PostMedia: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let kind: WorkoutMedia.Kind
    let width: Int?
    let height: Int?
    let durationSeconds: Double?
    let position: Int
    let url: URL
    let expiresAt: Date

    /// Width over height, or square when the size isn't known.
    var aspectRatio: CGFloat {
        guard let width, let height, width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

/// One of the workout's photos or videos picked to go on the post, in the order it shows.
nonisolated struct ShareMedia: Codable, Hashable, Sendable {
    /// The phone's media row ID, which the post's media reuses.
    var id: String
    var kind: WorkoutMedia.Kind
    /// The file in the media folder.
    var fileName: String
    var position: Int
}

extension ShareMedia {
    init(_ media: WorkoutMedia, position: Int) {
        self.init(id: media.id.uuidString, kind: media.kind, fileName: media.fileName, position: position)
    }
}

/// A photo or video still to upload to a shared workout. Kept on the phone until it's in, so an upload
/// cut off by a lost connection or a closed app finishes later.
nonisolated struct MediaUpload: Codable, Hashable, Sendable {
    var workoutId: String
    var media: ShareMedia
}

/// What the API needs to know about a file before it hands out an upload link.
nonisolated struct MediaDetails: Encodable, Hashable, Sendable {
    var kind: WorkoutMedia.Kind
    var contentType: String
    var byteSize: Int
    var width: Int?
    var height: Int?
    var durationSeconds: Double?
    var position: Int
}

/// Where to send a file: the link, and the headers to send with it exactly.
nonisolated struct UploadLink: Decodable, Hashable, Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
}

/// The API's answer to asking for an upload link. No link once the file is already in.
nonisolated struct PreparedUpload: Decodable, Hashable, Sendable {
    let id: String
    let status: String
    let upload: UploadLink?
}

/// A file shrunk and ready to send.
nonisolated struct ExportedMedia: Sendable {
    let url: URL
    let details: MediaDetails
}

/// Shrinks photos and videos before they leave the phone: photos to 2048 pixels on the long side as JPEG,
/// videos to 1080p MP4. The copies go in a scratch folder and are removed once sent.
nonisolated enum MediaExport {
    static let photoSide: CGFloat = 2048

    static var folder: URL { URL.cachesDirectory.appending(path: "uploads") }

    static func export(_ source: URL, kind: WorkoutMedia.Kind, id: String, position: Int) async throws -> ExportedMedia {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        switch kind {
        case .photo: return try photo(source, id: id, position: position)
        case .video: return try await video(source, id: id, position: position)
        }
    }

    private static func photo(_ source: URL, id: String, position: Int) throws -> ExportedMedia {
        guard let image = CGImageSourceCreateWithURL(source as CFURL, nil) else { throw ExportError.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: photoSide,
        ]
        guard let shrunk = CGImageSourceCreateThumbnailAtIndex(image, 0, options as CFDictionary) else { throw ExportError.unreadable }
        let target = folder.appending(path: "\(id).jpg")
        try? FileManager.default.removeItem(at: target)
        guard let destination = CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw ExportError.unwritable }
        CGImageDestinationAddImage(destination, shrunk, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ExportError.unwritable }
        let details = MediaDetails(kind: .photo, contentType: "image/jpeg", byteSize: try size(of: target), width: shrunk.width, height: shrunk.height,
                                   durationSeconds: nil, position: position)
        return ExportedMedia(url: target, details: details)
    }

    private static func video(_ source: URL, id: String, position: Int) async throws -> ExportedMedia {
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080) else { throw ExportError.unreadable }
        session.shouldOptimizeForNetworkUse = true
        let target = folder.appending(path: "\(id).mp4")
        try? FileManager.default.removeItem(at: target)
        try await session.export(to: target, as: .mp4)

        let exported = AVURLAsset(url: target)
        var width: Int?
        var height: Int?
        if let track = try? await exported.loadTracks(withMediaType: .video).first,
           case let (natural, transform)? = try? await track.load(.naturalSize, .preferredTransform) {
            let rect = CGRect(origin: .zero, size: natural).applying(transform)
            width = Int(abs(rect.width).rounded())
            height = Int(abs(rect.height).rounded())
        }
        let duration = try? await exported.load(.duration)
        let details = MediaDetails(kind: .video, contentType: "video/mp4", byteSize: try size(of: target), width: width, height: height,
                                   durationSeconds: duration.flatMap { $0.isNumeric ? $0.seconds : nil }, position: position)
        return ExportedMedia(url: target, details: details)
    }

    private static func size(of url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int) ?? 0
    }

    enum ExportError: Error {
        case unreadable, unwritable
    }
}
