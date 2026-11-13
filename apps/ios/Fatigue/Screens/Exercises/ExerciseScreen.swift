import Charts
import SwiftUI

/// One exercise across every workout, on one brand at a time: a graph of a metric, its records, and
/// every past set. Opens from an exercise's name, mid-workout or in history. See "Scores and stats" in the docs.
struct ExerciseScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let name: String
    let history: [FinishedWorkout]

    @State private var brand: String?
    @State private var metric: StatMetric = .setVolume
    @State private var weighted = true
    /// The setting the graph is split by. Remembered per exercise.
    @State private var splitBy: String?

    /// Opens on `brand`, the one you're on now, or the one you've used most if you've never done it there.
    init(name: String, brand: String?, history: [FinishedWorkout]) {
        self.name = name
        self.history = history
        let brands = ExerciseStats.brands(for: name, in: history)
        _brand = State(initialValue: brands.contains(brand) || brands.isEmpty ? brand : brands[0])
        _splitBy = State(initialValue: UserDefaults.standard.string(forKey: Self.splitKey(name)))
    }

    private static func splitKey(_ name: String) -> String { "exerciseSplit.\(name)" }

    private var brands: [String?] {
        let used = ExerciseStats.brands(for: name, in: history)
        return used.contains(brand) ? used : [brand] + used
    }

    private var stats: ExerciseStats { ExerciseStats(name: name, brand: brand, history: history) }

    /// Whether any setting on this brand counts towards the score. Without one, weighted and raw are the same.
    private var hasWeighting: Bool {
        stats.sessions.contains { $0.exercise.settings.contains(where: \.isTracked) }
    }

    private var isWeighted: Bool { metric.canBeWeighted && weighted && hasWeighting }

    /// The split, if this brand has the setting.
    private var split: String? {
        splitBy.flatMap { stats.splittableSettings.contains($0) ? $0 : nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                if brands.count > 1 { brandPicker }
                if stats.sessions.isEmpty {
                    Text("No ticked sets on \(brand ?? "no brand") yet. Finish a workout with this exercise and it shows up here.")
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tokens.Space.xxl)
                } else {
                    graph
                    recordsSection
                    historySection
                }
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.xxl)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .background(palette.background)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(palette.background)
        .animation(.standard, value: brand)
        .animation(.standard, value: metric)
        .animation(.standard, value: isWeighted)
        .animation(.standard, value: split)
        .sensoryFeedback(.selection, trigger: metric)
        .onChange(of: splitBy) { _, name in UserDefaults.standard.set(name, forKey: Self.splitKey(self.name)) }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(name)
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                Text(brand ?? "No brand")
                    .textStyle(Tokens.Typography.control)
                    .foregroundStyle(palette.foregroundMuted)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(palette.foreground)
                    .frame(width: Tokens.Size.control, height: Tokens.Size.control)
            }
            .buttonStyle(.press)
            .accessibilityLabel("Close")
        }
    }

    private var brandPicker: some View {
        chips(brands.map { ($0 ?? "No brand", $0) }, selected: brand) { brand = $0 }
            .padding(.top, Tokens.Space.l)
    }

    // MARK: Graph

    private var points: [StatPoint] { stats.points(metric, weighted: isWeighted, splitBy: split) }

    /// "kg" for plain kilograms, "weighted" for scores, so it's never a guess which one a number is.
    private var unit: String { isWeighted ? "weighted" : "kg" }

    private var lineStyles: [Color] { [palette.foreground, palette.accent, palette.foregroundMuted, palette.foregroundFaint] }

    private var graph: some View {
        VStack(alignment: .leading, spacing: 0) {
            chips(StatMetric.allCases.map { ($0.title, $0) }, selected: metric) { metric = $0 }
                .padding(.top, Tokens.Space.xxl)

            HStack(spacing: Tokens.Space.s) {
                if metric.canBeWeighted, hasWeighting {
                    chips([("Weighted", true), ("Raw", false)], selected: weighted, scrolls: false) { weighted = $0 }
                }
                Spacer()
                splitMenu
            }
            .padding(.top, Tokens.Space.m)

            latest
                .padding(.top, Tokens.Space.xl)

            if Set(points.map(\.date)).count > 1 {
                chart
                    .frame(height: 180)
                    .padding(.top, Tokens.Space.l)
            } else {
                Text("One workout so far. The line starts with your next one.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.top, Tokens.Space.s)
            }
        }
    }

    /// The latest value on each line, under its name.
    private var latest: some View {
        let names = split == nil ? [""] : stats.seriesNames(splitBy: split)
        return FlowLayout(spacing: Tokens.Space.xl) {
            ForEach(Array(names.enumerated()), id: \.element) { index, series in
                if let last = points.last(where: { $0.series == series }) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        if !series.isEmpty {
                            HStack(spacing: Tokens.Space.xs) {
                                Circle().fill(lineStyles[index % lineStyles.count]).frame(width: 7, height: 7)
                                Text(series)
                            }
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
                            Text(format(last.value))
                                .textStyle(series.isEmpty ? Tokens.Typography.timer : Tokens.Typography.number)
                                .foregroundStyle(palette.foreground)
                                .contentTransition(.numericText(value: last.value))
                            Text(unit)
                                .textStyle(Tokens.Typography.caption)
                                .foregroundStyle(palette.foregroundMuted)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var chart: some View {
        let names = stats.seriesNames(splitBy: split)
        let base = Chart(points) { point in
            LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(by: .value("Line", point.series))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                .foregroundStyle(by: .value("Line", point.series))
                .symbolSize(24)
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .foregroundStyle(palette.foregroundMuted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(palette.borderSoft)
                AxisValueLabel().foregroundStyle(palette.foregroundMuted)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .accessibilityLabel("\(metric.title) over time, \(unit)")

        if names.isEmpty {
            base.chartForegroundStyleScale(domain: [""], range: [palette.foreground])
        } else {
            base.chartForegroundStyleScale(domain: names, range: names.indices.map { lineStyles[$0 % lineStyles.count] })
        }
    }

    private var splitMenu: some View {
        Menu {
            Picker("Split by", selection: $splitBy) {
                Text("Nothing").tag(String?.none)
                ForEach(stats.splittableSettings, id: \.self) { Text($0).tag(String?.some($0)) }
            }
        } label: {
            OutlinedLabel(text: split.map { "Split by \($0.lowercased())" } ?? "Split by", showsChevron: true, isMuted: split == nil)
        }
        .opacity(stats.splittableSettings.isEmpty ? 0 : 1)
        .disabled(stats.splittableSettings.isEmpty)
    }

    // MARK: Records

    /// The four records, once per line when the graph is split.
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Records")
            if let split {
                ForEach(stats.seriesNames(splitBy: split), id: \.self) { series in
                    Text(series)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.top, Tokens.Space.l)
                        .padding(.bottom, Tokens.Space.xs)
                    records(stats.records(splitBy: split, series: series))
                }
            } else {
                records(stats.records())
            }
        }
    }

    private func records(_ records: ExerciseRecords) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            recordRow("Heaviest weight", records.heaviestWeight, unit: "kg")
            Hairline(soft: true)
            recordRow("Best 1RM", records.bestOneRepMax, unit: "kg")
            Hairline(soft: true)
            recordRow("Best set volume", records.bestSetVolume, unit: "kg", weightedBest: records.weightedSetVolume)
            Hairline(soft: true)
            recordRow("Best session volume", records.bestSessionVolume, unit: "kg", weightedBest: records.weightedSessionVolume)
            Hairline()
        }
    }

    private func recordRow(_ title: String, _ record: StatRecord?, unit: String, weightedBest: StatRecord? = nil) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                Spacer()
                Text(record.map { "\(Self.format($0.value, whole: title.contains("volume"))) \(unit)" } ?? "-")
                    .textStyle(Tokens.Typography.number)
                    .monospacedDigit()
                    .foregroundStyle(palette.foreground)
            }
            if let record {
                Text("\(record.detail), \(record.date.formatted(.dateTime.day().month(.abbreviated).year()))")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
            }
            if hasWeighting, let weightedBest {
                Text("\(Self.format(weightedBest.value, whole: true)) weighted, \(weightedBest.detail)")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundFaint)
            }
        }
        .padding(.vertical, Tokens.Space.m)
    }

    // MARK: History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("History")
            ForEach(stats.sessions.reversed()) { session in
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(session.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                        Spacer()
                        Text(session.workoutTitle)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    .padding(.bottom, Tokens.Space.xs)
                    ForEach(Array(session.sets.enumerated()), id: \.element.id) { index, set in
                        HStack(spacing: Tokens.Space.m) {
                            Text(session.sets.mark(at: index))
                                .foregroundStyle(set.type == .normal ? palette.foregroundFaint : palette.foregroundMuted)
                                .frame(width: Tokens.Size.setNumberColumn, alignment: .leading)
                                .accessibilityLabel(session.sets.spokenName(at: index))
                            Text(ExerciseStats.describe(set) + (set.rpe.map { " @\(PlainNumber.string($0))" } ?? ""))
                                .foregroundStyle(palette.foreground)
                            Text(([set.kind == .hold ? "Hold" : nil].compactMap { $0 } + session.exercise.labels(for: set.setup)).joined(separator: " · "))
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        .textStyle(Tokens.Typography.control)
                        .monospacedDigit()
                    }
                }
                .padding(.vertical, Tokens.Space.l)
                Hairline(soft: true)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .textStyle(Tokens.Typography.exerciseName)
            .foregroundStyle(palette.foreground)
            .padding(.top, Tokens.Space.xxxl)
            .padding(.bottom, Tokens.Space.s)
    }

    // MARK: Helpers

    /// A row of options that scrolls sideways when it doesn't fit, fading at the right edge.
    @ViewBuilder private func chips<Value: Equatable>(
        _ options: [(String, Value)], selected: Value, scrolls: Bool = true, onPick: @escaping (Value) -> Void
    ) -> some View {
        let row = HStack(spacing: Tokens.Space.s) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { onPick(option.1) } label: {
                    OptionLabel(title: option.0, isSelected: option.1 == selected)
                }
                .buttonStyle(.press)
            }
        }
        if scrolls {
            ScrollView(.horizontal, showsIndicators: false) { row.padding(.trailing, Tokens.Space.xxl) }
                .scrollClipDisabled()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
        } else {
            row
        }
    }

    /// Volumes and scores read as whole numbers. Weights keep a half kilo.
    static func format(_ value: Double, whole: Bool = false) -> String {
        value.formatted(.number.precision(.fractionLength(0...(whole ? 0 : 1))))
    }

    private func format(_ value: Double) -> String { Self.format(value, whole: metric.canBeWeighted) }
}
