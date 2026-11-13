import SwiftUI

/// One finished workout in the history list: its name, then the day, time, sets and volume,
/// then a list of the first five exercises, each with its set count in front. Anything past five is summed up as "… 2 more".
/// The first photo or video on it sits at the top right.
struct HistoryRow: View {
    @Environment(\.palette) private var palette
    @Environment(MediaStore.self) private var media
    let workout: FinishedWorkout

    static let exerciseLimit = 5
    static let coverSide: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            HStack(alignment: .top, spacing: Tokens.Space.m) {
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    Text(workout.title)
                        .textStyle(Tokens.Typography.exerciseName)
                        .foregroundStyle(palette.foreground)
                    Text(Self.summary(workout))
                        .textStyle(Tokens.Typography.caption)
                        .monospacedDigit()
                        .foregroundStyle(palette.foregroundMuted)
                    if !workout.description.isEmpty {
                        Text(workout.description)
                            .textStyle(Tokens.Typography.control)
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(2)
                            .padding(.top, Tokens.Space.xs)
                    }
                }
                if let cover = media.cover(for: workout.id) {
                    Spacer(minLength: 0)
                    MediaThumbnail(media: cover, side: Self.coverSide)
                }
            }
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                ForEach(Array(workout.exercises.prefix(Self.exerciseLimit).enumerated()), id: \.offset) { _, exercise in
                    // One line per exercise, read left to right like Hevy: "3 sets  Lat Pulldown".
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                        Text("\(exercise.sets.count) set\(exercise.sets.count == 1 ? "" : "s")")
                            .monospacedDigit()
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(width: Tokens.Size.weightColumn, alignment: .leading)
                        Text(exercise.name)
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                    }
                    .textStyle(Tokens.Typography.control)
                }
                if let more = Self.hiddenCount(workout) {
                    Text("… \(more) more")
                        .textStyle(Tokens.Typography.control)
                        .foregroundStyle(palette.foregroundFaint)
                }
            }
            .padding(.top, Tokens.Space.xs)
        }
        .padding(.vertical, Tokens.Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this workout")
    }

    /// How many exercises the row leaves out, or nil when it shows them all.
    static func hiddenCount(_ workout: FinishedWorkout) -> Int? {
        let hidden = workout.exercises.count - exerciseLimit
        return hidden > 0 ? hidden : nil
    }

    /// Such as "Wed 11 Nov · 52 min · 9 sets · 4,254 kg", with "Today" or "Yesterday" for recent ones.
    static func summary(_ workout: FinishedWorkout, now: Date = .now) -> String {
        let minutes = max(1, Int((workout.duration / 60).rounded()))
        var parts = [when(workout.startedAt, now: now), duration(minutes), "\(workout.setCount) set\(workout.setCount == 1 ? "" : "s")"]
        if workout.volume > 0 { parts.append("\(Int(workout.volume).formatted()) kg") }
        return parts.joined(separator: " · ")
    }

    /// "52 min", or "1 h 14 min" past the hour.
    static func duration(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// "Today", "Yesterday", or the weekday and date, such as "Wed 11 Nov".
    static func when(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
}
