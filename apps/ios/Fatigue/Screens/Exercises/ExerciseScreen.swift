import Charts
import SwiftUI

/// One exercise across every workout, on one brand at a time: a graph of a metric, its records, and
/// every past set. Opens from an exercise's name, mid-workout or in history. See "Scores and stats" in the docs.
struct ExerciseScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutStore.self) private var store
    @Environment(ExerciseCatalog.self) private var catalog
    let name: String
    let history: [FinishedWorkout]

    @State private var brand: String?
    @State private var metric: StatMetric = .setVolume
    @State private var weighted = true
    /// The setting the graph is split by. Remembered per exercise.
    @State private var splitBy: String?
    /// Other settings pinned to one line, such as ["Dead stop": "Dead stop"] for notch lines with the dead stop on.
    @State private var pinned: [String: String] = [:]
    /// Where on the graph's x axis a finger is, from tapping or dragging. Snapped to the nearest workout.
    @State private var selection: Date?

    /// Opens on `brand`, the one you're on now, or the one you've used most if you've never done it there.
    init(name: String, brand: String?, history: [FinishedWorkout]) {
        self.name = name
        self.history = history
        let brands = ExerciseStats.brands(for: name, in: history)
        _brand = State(initialValue: brands.contains(brand) || brands.isEmpty ? brand : brands[0])
        _splitBy = State(initialValue: ExerciseSplit.remembered(for: name))
    }

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

    /// The pins that apply: on settings this brand has, other than the split.
    private var pins: [String: String] {
        let filterable = stats.filterableSettings(splitBy: split)
        return pinned.filter { filterable.contains($0.key) }
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
        .animation(.standard, value: pins)
        .animation(.standard, value: selectedDate)
        .onChange(of: splitBy) { _, split in
            ExerciseSplit.remember(split, for: name)
            if let split { pinned[split] = nil }
        }
        .onChange(of: brand) { selection = nil }
        .onChange(of: metric) { selection = nil }
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

    private var points: [StatPoint] { stats.points(metric, weighted: isWeighted, splitBy: split, pinned: pins) }

    private var lines: [String] { stats.seriesNames(splitBy: split, pinned: pins) }

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

            if split != nil { filterRows }

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

            if let selectedDate {
                pointDetails(at: selectedDate)
                    .padding(.top, Tokens.Space.l)
                    .transition(.opacity)
            } else if Set(points.map(\.date)).count > 1 {
                Text("Tap a point to see its sum.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundFaint)
                    .padding(.top, Tokens.Space.m)
            }
        }
    }

    /// One row per setting other than the split, to pin it to one line: "Any", "Dead stop", "No dead stop".
    private var filterRows: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            ForEach(stats.filterableSettings(splitBy: split), id: \.self) { setting in
                HStack(spacing: Tokens.Space.m) {
                    Text(setting)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .lineLimit(1)
                        .layoutPriority(1)
                    chips([("Any", String?.none)] + stats.seriesNames(splitBy: setting).map { ($0, String?.some($0)) }, selected: pins[setting]) { line in
                        pinned[setting] = line
                        selection = nil
                    }
                }
            }
        }
        .padding(.top, Tokens.Space.m)
    }

    /// The latest value on each line, under its name.
    private var latest: some View {
        let names = split == nil ? [""] : lines
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

    /// The workout nearest to where the graph was tapped, if it was.
    private var selectedDate: Date? {
        guard let selection else { return nil }
        return points.map(\.date).min { abs($0.timeIntervalSince(selection)) < abs($1.timeIntervalSince(selection)) }
    }

    @ViewBuilder private var chart: some View {
        let names = lines
        let base = Chart {
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                    .foregroundStyle(by: .value("Line", point.series))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", point.date), y: .value(metric.title, point.value))
                    .foregroundStyle(by: .value("Line", point.series))
                    .symbolSize(point.date == selectedDate ? 64 : 24)
            }
            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(palette.borderSoft)
                    .lineStyle(StrokeStyle(lineWidth: Tokens.Size.line))
            }
        }
        .chartXSelection(value: $selection)
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

    // MARK: Point detail

    /// The sum behind each line's point on one day, such as "460 × 1.78 × 1.5 = 1,227", with the yes/no
    /// factors in it to adjust. Changing one re-scores every past set on this exercise and brand.
    private func pointDetails(at date: Date) -> some View {
        let details = (split == nil ? [""] : lines).compactMap { series in
            stats.detail(of: metric, weighted: isWeighted, at: date, series: series, splitBy: split, pinned: pins)
        }
        return VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .firstTextBaseline) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                Spacer()
                Button { selection = nil } label: {
                    Image(systemName: "xmark")
                        .imageScale(.small)
                        .foregroundStyle(palette.foregroundMuted)
                        .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                }
                .buttonStyle(.press)
                .accessibilityLabel("Hide the sum")
            }
            .padding(.top, Tokens.Space.s)
            ForEach(details, id: \.series) { detail in
                VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.xs) {
                        if !detail.series.isEmpty {
                            Text(detail.series)
                                .textStyle(Tokens.Typography.caption)
                                .foregroundStyle(palette.foregroundMuted)
                            Spacer()
                        }
                        Text(format(detail.value))
                            .textStyle(Tokens.Typography.number)
                            .monospacedDigit()
                            .foregroundStyle(palette.foreground)
                        Text(unit)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    ForEach(Array(detail.breakdowns.enumerated()), id: \.offset) { _, sum in
                        HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.m) {
                            Text(sum.set)
                                .foregroundStyle(palette.foreground)
                            Text(isWeighted ? sum.text : "\(Self.format(sum.load, whole: metric.canBeWeighted)) kg")
                                .foregroundStyle(palette.foregroundMuted)
                        }
                        .textStyle(Tokens.Typography.control)
                        .monospacedDigit()
                    }
                }
                .padding(.vertical, Tokens.Space.m)
            }
            if metric.canBeWeighted {
                factorControls(for: details)
            }
            Hairline()
        }
    }

    /// Chips to change each yes/no setting's factor in the sum. A number setting's factor comes from its range, so it's only named.
    @ViewBuilder private func factorControls(for details: [PointDetail]) -> some View {
        let terms = isWeighted ? details.flatMap(\.breakdowns).flatMap(\.terms) : []
        let numbers = terms.filter { $0.kind == .number }.reduce(into: [ScoreBreakdown.Term]()) { kept, term in
            if !kept.contains(where: { $0.label == term.label }) { kept.append(term) }
        }
        let adjustable = details.flatMap(\.adjustable).reduce(into: [ExerciseSetting]()) { kept, setting in
            if !kept.contains(where: { $0.name == setting.name }) { kept.append(setting) }
        }
        if !numbers.isEmpty || !adjustable.isEmpty {
            Hairline(soft: true)
            VStack(alignment: .leading, spacing: Tokens.Space.m) {
                ForEach(numbers, id: \.label) { term in
                    Text("\(term.label) is ×\(ScoreBreakdown.format(factor: term.factor)), from where it sits in its range.")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundFaint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(adjustable) { setting in
                    HStack(spacing: Tokens.Space.m) {
                        Text(setting.name)
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .lineLimit(1)
                            .layoutPriority(1)
                        chips(Self.factorOptions(current: setting.factor), selected: setting.factor) { factor in
                            store.setFactor(factor, ofSetting: setting.name, exercise: name, brand: brand)
                            catalog.setFactor(factor, ofSetting: setting.name, for: name, brand: brand)
                        }
                    }
                }
                if !adjustable.isEmpty {
                    Text("Changing a factor re-scores every set on this brand.")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundFaint)
                }
            }
            .padding(.vertical, Tokens.Space.m)
        }
    }

    /// Doesn't count, ×1.25, ×1.5, ×1.75 and ×2, plus the factor it has now if that's a number you typed.
    static func factorOptions(current: Double?) -> [(String, Double?)] {
        var factors: [Double] = [1.25, 1.5, 1.75, 2]
        if let current, !factors.contains(current) { factors.append(current) }
        return [("Doesn't count", nil)] + factors.sorted().map { ("×\(PlainNumber.string($0))", $0) }
    }

    // MARK: Records

    /// The four records, once per line when the graph is split. Pinned settings count only the sets on their line.
    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionTitle("Records")
            if let split {
                ForEach(lines, id: \.self) { series in
                    Text(series)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.top, Tokens.Space.l)
                        .padding(.bottom, Tokens.Space.xs)
                    records(stats.records(splitBy: split, series: series, pinned: pins))
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
                            Text("\(index + 1)")
                                .foregroundStyle(palette.foregroundFaint)
                                .frame(width: Tokens.Size.setNumberColumn, alignment: .leading)
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
