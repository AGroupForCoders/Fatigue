import AVKit
import SwiftUI

/// A post's photos and videos, one at a time, swiped sideways when there's more than one. Shown on post
/// cards and the post's page. Videos play when tapped.
struct PostMediaView: View {
    @Environment(\.palette) private var palette
    let media: [PostMedia]

    var body: some View {
        if !media.isEmpty {
            TabView {
                ForEach(media) { item in
                    PostMediaItem(item: item)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: media.count > 1 ? .automatic : .never))
            .aspectRatio(Self.frameRatio(for: media), contentMode: .fit)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
        }
    }

    /// The first item's shape, kept between a 4:5 portrait and a 16:9 landscape so one odd file can't make
    /// the card very tall or very thin.
    static func frameRatio(for media: [PostMedia]) -> CGFloat {
        min(max(media.first?.aspectRatio ?? 1, 4.0 / 5.0), 16.0 / 9.0)
    }
}

private struct PostMediaItem: View {
    @Environment(\.palette) private var palette
    let item: PostMedia
    @State private var player: AVPlayer?

    var body: some View {
        switch item.kind {
        case .photo:
            AsyncImage(url: item.url, transaction: Transaction(animation: .quick)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(palette.foregroundFaint)
                default:
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .accessibilityLabel("Photo")
        case .video:
            ZStack {
                if let player {
                    VideoPlayer(player: player)
                } else {
                    Color.black
                    Button {
                        let player = AVPlayer(url: item.url)
                        self.player = player
                        player.play()
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 48))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.4))
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel(durationLabel.map { "Play video, \($0)" } ?? "Play video")
                }
            }
            .onDisappear { player?.pause() }
        }
    }

    private var durationLabel: String? {
        guard let seconds = item.durationSeconds else { return nil }
        let whole = Int(seconds.rounded())
        return "\(whole / 60):" + String(format: "%02d", whole % 60)
    }
}

/// The workout's photos and videos in the share sheet, each ticked to go on the post or not.
struct ShareMediaPicker: View {
    @Environment(\.palette) private var palette
    @Environment(MediaStore.self) private var store
    let items: [WorkoutMedia]
    @Binding var picked: Set<UUID>

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Photos and videos")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                HStack(spacing: Tokens.Space.s) {
                    ForEach(items) { item in
                        let isPicked = picked.contains(item.id)
                        Button {
                            if isPicked { picked.remove(item.id) } else { picked.insert(item.id) }
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Group {
                                    if let thumbnail = store.thumbnail(for: item) {
                                        Image(uiImage: thumbnail).resizable().scaledToFill()
                                    } else {
                                        palette.surface
                                    }
                                }
                                .frame(width: MediaRow.thumbnailSide, height: MediaRow.thumbnailSide)
                                .clipped()
                                .opacity(isPicked ? 1 : 0.4)
                                Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(isPicked ? .white : .white.opacity(0.9), isPicked ? palette.accent : .black.opacity(0.3))
                                    .imageScale(.large)
                                    .padding(Tokens.Space.xs)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(item.kind == .video ? "Video" : "Photo")
                        .accessibilityValue(isPicked ? "Goes on the post" : "Stays on your phone")
                    }
                }
            }
        }
    }
}
