import ActivityKit
import SwiftUI
import WidgetKit

/// The rest countdown on the Lock Screen and in the Dynamic Island, with the exercise you're
/// resting from and Skip and +15 s, the same controls as the rest bar in the app.
///
/// It can't read the app's theme choice, so it follows the system appearance with the default
/// light and dark palettes. Once the timer runs out it says "Rest done" until the app ends it.
struct RestWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            LockScreenRest(context: context)
        } dynamicIsland: { context in
            let palette = Palette.defaultDark
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                        Text(context.isStale ? "Rest done" : "Rest")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                        Text(RestWidgetLiveActivity.exerciseName(context.state))
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foreground)
                            .lineLimit(1)
                    }
                    .padding(.leading, Tokens.Space.s)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RestCountdown(state: context.state, isStale: context.isStale, style: Tokens.Typography.timer)
                        .foregroundStyle(palette.foreground)
                        .padding(.trailing, Tokens.Space.s)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: Tokens.Space.m) {
                        RestProgress(state: context.state, palette: palette)
                        RestButtons(palette: palette)
                    }
                    .padding(.horizontal, Tokens.Space.s)
                    .padding(.top, Tokens.Space.s)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(palette.accent)
            } compactTrailing: {
                RestCountdown(state: context.state, isStale: context.isStale, style: Tokens.Typography.control)
                    .foregroundStyle(palette.foreground)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(palette.accent)
            }
            .keylineTint(palette.accent)
        }
    }

    /// What to call the exercise when a set had none, so the line is never empty.
    static func exerciseName(_ state: RestActivityAttributes.ContentState) -> String {
        state.exerciseName.isEmpty ? "Next set" : state.exerciseName
    }
}

/// The Lock Screen banner: the exercise, the countdown, Skip and +15 s, and a progress line.
private struct LockScreenRest: View {
    @Environment(\.colorScheme) private var colorScheme
    let context: ActivityViewContext<RestActivityAttributes>

    private var palette: Palette { colorScheme == .dark ? .defaultDark : .defaultLight }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.m) {
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Space.s) {
                RestCountdown(state: context.state, isStale: context.isStale, style: Tokens.Typography.timer)
                    .foregroundStyle(palette.foreground)
                Text(context.isStale ? "Rest done" : "Rest")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                Spacer(minLength: Tokens.Space.s)
                RestButtons(palette: palette)
            }
            Text(RestWidgetLiveActivity.exerciseName(context.state))
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foregroundMuted)
                .lineLimit(1)
            RestProgress(state: context.state, palette: palette)
        }
        .padding(.horizontal, Tokens.Space.xl)
        .padding(.vertical, Tokens.Space.l)
        .activityBackgroundTint(palette.background)
        .activitySystemActionForegroundColor(palette.foreground)
    }
}

/// The time left, counting down by itself so the activity needs no updates while it runs.
/// Shows 0:00 once the timer is over.
private struct RestCountdown: View {
    let state: RestActivityAttributes.ContentState
    let isStale: Bool
    let style: TextStyle

    var body: some View {
        Group {
            if isStale {
                Text("0:00")
            } else {
                Text(timerInterval: state.startedAt...state.endsAt, countsDown: true, showsHours: false)
            }
        }
        .textStyle(style)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

/// The thin line that fills as rest goes by, like the one across the top of the app's rest bar.
private struct RestProgress: View {
    let state: RestActivityAttributes.ContentState
    let palette: Palette

    var body: some View {
        ProgressView(timerInterval: state.startedAt...state.endsAt, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(palette.foreground)
    }
}

/// +15 s and Skip. Each runs an App Intent in the app, which moves or ends the timer and updates
/// the activity. They look like the outlined controls in the app.
private struct RestButtons: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            Button(intent: ExtendRestIntent()) { label("+15") }
            Button(intent: SkipRestIntent()) { label("Skip") }
        }
        .buttonStyle(.plain)
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .textStyle(Tokens.Typography.control)
            .foregroundStyle(palette.foreground)
            .padding(.horizontal, Tokens.Space.m)
            .frame(height: Tokens.Size.outlinedControl)
            .overlay(
                RoundedRectangle(cornerRadius: Tokens.Radius.control)
                    .strokeBorder(palette.borderControl, lineWidth: Tokens.Size.line)
            )
            .contentShape(Rectangle())
    }
}
