import Charts
import SwiftUI

/// The Stats tab: this week against last, weekly volume for 12 weeks, then every exercise you've done
/// with a small trend. Tapping an exercise opens its page.
struct StatsScreen: View {
    @Environment(\.palette) private var palette
    @Environment(WorkoutStore.self) private var store
    @AppStorage(WeightUnit.storageKey) private var unit: WeightUnit = .kg
    @State private var opened: TrainingStats.ExerciseTrend?

    private var stats: TrainingStats { TrainingStats(history: store.history) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Stats")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                    .padding(.top, Tokens.Space.l)
                    .padding(.bottom, Tokens.Space.xxl)

                if store.history.isEmpty {
                    Text("Finish a workout and your weeks and exercises show up here.")
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                } else {
                    thisWeek
                    weeklyVolume
                    exercises
                }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .background(palette.background)
        .sheet(item: $opened) { trend in
            ExerciseScreen(name: trend.name, brand: trend.brand, history: store.history)
                .environment(\.palette, palette)
        }
    }

    // MARK: This week

    private var thisWeek: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            caption("This week")
            HStack(alignment: .top, spacing: 0) {
                stat("\(stats.thisWeek.workouts)", label: "Workouts", last: "\(stats.lastWeek.workouts)")
                stat("\(stats.thisWeek.sets)", label: "Sets", last: "\(stats.lastWeek.sets)")
                stat(Self.volume(stats.thisWeek.volume, in: unit), label: "Volume", last: Self.volume(stats.lastWeek.volume, in: unit))
            }
        }
    }

    /// A number, what it counts, and last week's number under it.
    private func stat(_ value: String, label: String, last: String) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            Text(value)
                .textStyle(Tokens.Typography.exerciseName)
                .monospacedDigit()
                .foregroundStyle(palette.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundMuted)
            Text("\(last) last week")
                .textStyle(Tokens.Typography.caption)
                .monospacedDigit()
                .foregroundStyle(palette.foregroundFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Weekly volume

    private var weeklyVolume: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            caption("Weekly volume, last 12 weeks")
            Chart(stats.weeks) { week in
                BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Volume", unit.amount(fromKilograms: week.volume)))
                    .foregroundStyle(week.id == stats.weeks.last?.id ? palette.accent : palette.foreground)
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(palette.foregroundMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(palette.borderSoft)
                    AxisValueLabel().foregroundStyle(palette.foregroundMuted)
                }
            }
            .frame(height: 160)
            .accessibilityLabel("Weekly volume in \(unit.name) for the last 12 weeks")
        }
        .padding(.top, Tokens.Space.xxxl)
    }

    // MARK: Exercises

    private var exercises: some View {
        VStack(alignment: .leading, spacing: 0) {
            caption("Exercises")
                .padding(.bottom, Tokens.Space.s)
            Hairline()
            ForEach(stats.exercises) { trend in
                Button { opened = trend } label: { row(trend) }
                    .buttonStyle(.pressRow)
                Hairline(soft: true)
            }
        }
        .padding(.top, Tokens.Space.xxxl)
    }

    private func row(_ trend: TrainingStats.ExerciseTrend) -> some View {
        HStack(spacing: Tokens.Space.m) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(trend.name)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                Text([trend.brand?.display, trend.lastDone.formatted(.relative(presentation: .named))].compactMap { $0 }.joined(separator: " · "))
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
            }
            Spacer(minLength: Tokens.Space.s)
            if trend.values.count > 1 {
                Chart(Array(trend.values.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("Workout", index), y: .value("Best set volume", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(palette.foregroundMuted)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(width: 56, height: 24)
                .accessibilityHidden(true)
            }
            Text(trend.change.map(Self.percent) ?? "New")
                .textStyle(Tokens.Typography.control)
                .monospacedDigit()
                .foregroundStyle((trend.change ?? 0) > 0 ? palette.accent : palette.foregroundMuted)
                .frame(minWidth: 48, alignment: .trailing)
            Image(systemName: "chevron.right")
                .imageScale(.small)
                .foregroundStyle(palette.foregroundFaint)
        }
        .frame(minHeight: Tokens.Size.setRow + Tokens.Space.s)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens its progress")
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .textStyle(Tokens.Typography.caption)
            .foregroundStyle(palette.foregroundMuted)
    }

    /// A volume in kilograms shown in `unit`, such as "4,254 kg" or "0 lb".
    static func volume(_ kilograms: Double, in unit: WeightUnit) -> String { unit.wholeLabelled(max(0, kilograms)) }

    /// Such as "+12%", "-3%" or "0%".
    static func percent(_ change: Double) -> String {
        let rounded = Int((change * 100).rounded())
        return rounded > 0 ? "+\(rounded)%" : "\(rounded)%"
    }
}
