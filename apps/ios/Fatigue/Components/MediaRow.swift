import AVKit
import PhotosUI
import SwiftUI

/// The dashed square at the end of the media row.
/// Nonisolated so PhotosPicker's label closure can make it. The content inside reads the palette.
private nonisolated struct AddMediaLabel: View {
    let isFirst: Bool

    var body: some View {
        AddMediaLabelContent(isFirst: isFirst)
    }
}

private struct AddMediaLabelContent: View {
    @Environment(\.palette) private var palette
    let isFirst: Bool

    var body: some View {
        VStack(spacing: Tokens.Space.xs) {
            Image(systemName: "plus")
                .imageScale(.medium)
            Text(isFirst ? "Add media" : "Add")
                .textStyle(Tokens.Typography.caption)
        }
        .foregroundStyle(palette.foregroundMuted)
        .frame(width: MediaRow.thumbnailSide, height: MediaRow.thumbnailSide)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                .strokeBorder(palette.borderControl, style: StrokeStyle(lineWidth: Tokens.Size.line, dash: [4, 3]))
        )
        .contentShape(Rectangle())
    }
}

/// The photos and videos on a workout as a row of square thumbnails, with "Add media" at the end.
/// Tapping one opens it full screen. Shown on the finish summary and the workout's page.
struct MediaRow: View {
    @Environment(\.palette) private var palette
    @Environment(MediaStore.self) private var media
    let workoutID: UUID

    @State private var picks: [PhotosPickerItem] = []
    @State private var viewing: WorkoutMedia?

    static let thumbnailSide: CGFloat = 88

    private var items: [WorkoutMedia] { media.media(for: workoutID) }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(items.isEmpty ? "Media" : "Media · \(items.count) of \(MediaStore.limit)")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                Spacer()
                if media.importing.contains(workoutID) {
                    Text("Adding…")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundFaint)
                        .transition(.opacity)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Tokens.Space.s) {
                    ForEach(items) { item in
                        Button { viewing = item } label: {
                            MediaThumbnail(media: item, side: Self.thumbnailSide)
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel(item.kind == .video ? "Video" : "Photo")
                        .accessibilityHint("Opens it full screen")
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                    // The label is its own view: PhotosPicker's label closure isn't on the main actor,
                    // so it can't call `textStyle` directly.
                    // Gone once the workout is full, and the picker stops at what's left.
                    if media.room(for: workoutID) > 0 {
                        PhotosPicker(selection: $picks, maxSelectionCount: media.room(for: workoutID), matching: .any(of: [.images, .videos])) {
                            AddMediaLabel(isFirst: items.isEmpty)
                        }
                        .buttonStyle(.press)
                        .accessibilityLabel("Add media")
                        .accessibilityHint("Picks up to \(media.room(for: workoutID)) more photos or videos from your library")
                        .transition(.opacity)
                    }
                }
                .padding(.vertical, Tokens.Space.xs)
            }
            .scrollClipDisabled()
            .animation(.standard, value: items.map(\.id))
        }
        .animation(.standard, value: media.importing.contains(workoutID))
        .onChange(of: picks) { _, picked in
            guard !picked.isEmpty else { return }
            picks = []
            Task { await media.add(picked, to: workoutID) }
        }
        .fullScreenCover(item: $viewing) { item in
            MediaViewer(workoutID: workoutID, start: item)
                .environment(\.palette, palette)
        }
    }
}

/// One square thumbnail, with a play mark and length on a video. A soft surface while the image loads.
struct MediaThumbnail: View {
    @Environment(\.palette) private var palette
    @Environment(MediaStore.self) private var store
    let media: WorkoutMedia
    let side: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                .fill(palette.surface)
            if let image = store.thumbnail(for: media) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.control))
                    .transition(.opacity)
            }
            if media.kind == .video {
                HStack(spacing: Tokens.Space.xs) {
                    Image(systemName: "play.fill")
                        .imageScale(.small)
                    if let length = media.durationLabel {
                        Text(length)
                            .textStyle(Tokens.Typography.label)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(Palette.dark.foreground)
                .padding(.horizontal, Tokens.Space.s)
                .padding(.vertical, Tokens.Space.xs)
                .background(Palette.dark.background.opacity(0.6), in: .rect(cornerRadius: Tokens.Radius.control - 2))
                .padding(Tokens.Space.xs)
            }
        }
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                .strokeBorder(palette.borderSoft, lineWidth: Tokens.Size.line)
        )
        .animation(.standard, value: store.thumbnail(for: media) == nil)
        .accessibilityHidden(true)
    }
}

/// A workout's photos and videos full screen, one at a time with a swipe between them.
/// Videos play in place. The trash at the top deletes the one you're on.
struct MediaViewer: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(MediaStore.self) private var store
    let workoutID: UUID
    let start: WorkoutMedia

    @State private var current: UUID
    @State private var confirmingDelete = false

    init(workoutID: UUID, start: WorkoutMedia) {
        self.workoutID = workoutID
        self.start = start
        _current = State(initialValue: start.id)
    }

    private var items: [WorkoutMedia] { store.media(for: workoutID) }
    private var position: Int? { items.firstIndex { $0.id == current } }
    private var currentItem: WorkoutMedia? { position.map { items[$0] } }

    var body: some View {
        ZStack(alignment: .top) {
            Palette.dark.background.ignoresSafeArea()
            if items.isEmpty {
                Color.clear.onAppear { dismiss() }
            } else {
                TabView(selection: $current) {
                    ForEach(items) { item in
                        MediaPage(media: item, isCurrent: item.id == current)
                            .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
            bar
        }
        .preferredColorScheme(.dark)
        .confirmationDialog("Delete this \(currentItem?.kind == .video ? "video" : "photo")?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteCurrent() }
        } message: {
            Text("It's removed from the workout. Your photo library isn't touched.")
        }
    }

    private var bar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .accessibilityLabel("Close")
            Spacer()
            if let position, items.count > 1 {
                Text("\(position + 1) of \(items.count)")
                    .textStyle(Tokens.Typography.caption)
                    .monospacedDigit()
                    .foregroundStyle(Palette.dark.foregroundMuted)
            }
            Spacer()
            Button { confirmingDelete = true } label: {
                Image(systemName: "trash")
                    .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .accessibilityLabel("Delete")
        }
        .foregroundStyle(Palette.dark.foreground)
        .padding(.horizontal, Tokens.Space.m)
        .padding(.top, Tokens.Space.xs)
    }

    /// Deletes what's on screen and moves to its neighbour, or closes when it was the last one.
    private func deleteCurrent() {
        guard let position, position < items.count else { return }
        let item = items[position]
        let remaining = items.filter { $0.id != item.id }
        if remaining.isEmpty {
            dismiss()
        } else {
            current = remaining[min(position, remaining.count - 1)].id
        }
        withAnimation(.standard) { store.delete(item) }
    }
}

/// One page of the viewer: the photo fitted to the screen, or the video with its player.
private struct MediaPage: View {
    @Environment(MediaStore.self) private var store
    let media: WorkoutMedia
    let isCurrent: Bool

    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        Group {
            switch media.kind {
            case .photo:
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else if let thumbnail = store.thumbnail(for: media) {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFit()
                }
            case .video:
                if let player {
                    VideoPlayer(player: player)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: media.id) {
            let url = store.fileURL(for: media)
            switch media.kind {
            case .photo:
                image = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path(percentEncoded: false)) }.value
            case .video:
                player = AVPlayer(url: url)
            }
        }
        .onChange(of: isCurrent) { _, current in
            // Swiping away from a video stops it, so two never play at once.
            if !current { player?.pause() }
        }
        .onDisappear { player?.pause() }
        .accessibilityLabel(media.kind == .video ? "Video" : "Photo")
    }
}
