import SwiftUI

/// A shared workout in full: who shared it, the caption and description, where, the records it beat,
/// then every exercise with its settings, notes and sets. Your own posts can be deleted from the menu.
struct PostScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    let post: Post
    @State private var confirmingDelete = false
    @State private var error: String?

    private var isMine: Bool { post.author.userId == social.myProfile?.userId }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PostAuthorLine(post: post)
                    .padding(.bottom, Tokens.Space.xl)
                if !post.media.isEmpty {
                    PostMediaView(media: post.media)
                        .padding(.bottom, Tokens.Space.xl)
                }
                if let snapshot = post.snapshot {
                    content(snapshot)
                } else {
                    Text("Shared from a newer version of Fatigue. Update the app to see it.")
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.s)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .defaultScrollAnchor(Self.debugScrollAnchor)
        .background(palette.background)
        .toolbarRole(.editor)
        .toolbar {
            if isMine {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Remove from feed", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(palette.foreground)
                    }
                    .accessibilityLabel("Post options")
                }
            }
        }
        .confirmationDialog("Remove from feed?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove from feed", role: .destructive) {
                Task {
                    do {
                        try await social.delete(post)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("The workout stays in your history. You can share it again later.")
        }
    }

    private func content(_ snapshot: PostSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(snapshot.title)
                .textStyle(Tokens.Typography.title)
                .foregroundStyle(palette.foreground)
            Text(Self.summary(snapshot, unit: unit))
                .textStyle(Tokens.Typography.control)
                .monospacedDigit()
                .foregroundStyle(palette.foregroundMuted)
            if let error {
                Text(error)
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.accent)
            }
            ForEach([post.caption, snapshot.description].compactMap { $0 }.filter { !$0.isEmpty }, id: \.self) { text in
                Text(text)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .padding(.top, Tokens.Space.s)
            }
            if let place = snapshot.gym {
                Label(place.name, systemImage: "mappin.and.ellipse")
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.top, Tokens.Space.s)
                if let gym = Gym(name: place.name, address: place.address, latitude: place.latitude, longitude: place.longitude),
                   let coordinate = gym.coordinate {
                    GymMap(gym: gym, coordinate: coordinate)
                        .padding(.top, Tokens.Space.s)
                }
            }
            if !snapshot.records.isEmpty { records(snapshot.records) }
            Hairline().padding(.top, Tokens.Space.xl)
            ForEach(Array(snapshot.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseView(exercise)
                Hairline()
            }
        }
    }

    private func records(_ records: [PostSnapshot.Record]) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text("Records")
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundMuted)
                .padding(.top, Tokens.Space.xl)
            ForEach(records, id: \.self) { record in
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    Image(systemName: "arrow.up").imageScale(.small).foregroundStyle(palette.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(record.record).foregroundStyle(palette.foreground)
                        Text([record.exercise, record.brand].compactMap { $0 }.joined(separator: " · "))
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    Spacer()
                    Text(record.value).monospacedDigit().foregroundStyle(palette.foreground)
                }
                .textStyle(Tokens.Typography.control)
                .padding(.vertical, Tokens.Space.xs)
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func exerciseView(_ exercise: PostSnapshot.Exercise) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            // Name and brand side by side when they fit, the brand under the name when they don't.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                    exerciseName(exercise.name)
                    if let brand = exercise.brand { brandText(brand) }
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    exerciseName(exercise.name)
                    if let brand = exercise.brand { brandText(brand) }
                }
            }
            if !exercise.settings.isEmpty {
                Text(exercise.settings.joined(separator: " · "))
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
            }
            ForEach(exercise.notes, id: \.self) { note in
                Text(note)
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
            }
            ForEach(Array(exercise.groups.enumerated()), id: \.offset) { _, group in
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    if !group.heading.isEmpty {
                        Text(group.heading)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .padding(.top, Tokens.Space.s)
                    }
                    ForEach(Array(group.sets.enumerated()), id: \.offset) { _, set in
                        HStack(spacing: Tokens.Space.l) {
                            Text(set.mark)
                                .foregroundStyle(set.isNormal ? palette.foregroundFaint : palette.foregroundMuted)
                                .frame(width: Tokens.Size.setNumberColumn, alignment: .leading)
                            Text(set.text(in: unit)).foregroundStyle(palette.foreground)
                            ForEach(set.values ?? [], id: \.self) { value in
                                Text(value).foregroundStyle(palette.foregroundMuted)
                            }
                            if let rpe = set.rpe {
                                Text("@\(PlainNumber.string(rpe))").foregroundStyle(palette.foregroundMuted)
                            }
                            Spacer()
                        }
                        .textStyle(Tokens.Typography.number)
                        .monospacedDigit()
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .padding(.vertical, Tokens.Space.xl)
    }

    /// Such as "52 min · 18 sets · 4,200 kg", in the viewer's unit.
    private func exerciseName(_ name: String) -> some View {
        Text(name)
            .textStyle(Tokens.Typography.exerciseName)
            .foregroundStyle(palette.foreground)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func brandText(_ brand: String) -> some View {
        Text(brand)
            .textStyle(Tokens.Typography.control)
            .foregroundStyle(palette.foregroundMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Such as "52 min · 18 sets · 4,200 kg", in the viewer's unit. The gym has its own line wherever this shows.
    static func summary(_ snapshot: PostSnapshot, unit: WeightUnit) -> String {
        let minutes = max(1, snapshot.durationSeconds / 60)
        var parts = [HistoryRow.duration(minutes), "\(snapshot.setCount.formatted()) set\(snapshot.setCount == 1 ? "" : "s")"]
        if snapshot.volumeKg > 0 { parts.append(unit.wholeLabelled(snapshot.volumeKg)) }
        return parts.joined(separator: " · ")
    }

    /// Debug builds can start the page scrolled with `-scrollAnchor center` or `-scrollAnchor bottom`, for screenshots.
    private static var debugScrollAnchor: UnitPoint? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-scrollAnchor"), index + 1 < args.count {
            return args[index + 1] == "bottom" ? .bottom : args[index + 1] == "center" ? .center : nil
        }
        #endif
        return nil
    }
}
