import SwiftUI

/// A thin full-width line between rows.
struct Hairline: View {
    @Environment(\.palette) private var palette
    var soft = false

    var body: some View {
        Rectangle()
            .fill(soft ? palette.borderSoft : palette.border)
            .frame(height: Tokens.Size.line)
            .accessibilityHidden(true)
    }
}

/// The main action on a screen, such as Start workout or Finish. Use at most one per screen.
struct PrimaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .textStyle(Tokens.Typography.button)
                .foregroundStyle(palette.background)
                .padding(.horizontal, Tokens.Space.xl)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(height: compact ? Tokens.Size.control : Tokens.Size.primaryButton)
                .background(palette.foreground, in: .rect(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(.plain)
    }
}

/// The look of the small outlined controls under an exercise name: rest, note and brand.
/// It is only a label, so it can sit inside a `Button` or a `Menu`.
struct OutlinedLabel: View {
    @Environment(\.palette) private var palette
    var systemImage: String?
    let text: String
    var showsChevron = false
    var isMuted = false

    var body: some View {
        HStack(spacing: Tokens.Space.s) {
            if let systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .foregroundStyle(palette.foregroundMuted)
            }
            Text(text)
                .lineLimit(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .foregroundStyle(palette.foregroundMuted)
            }
        }
        .textStyle(Tokens.Typography.control)
        .foregroundStyle(isMuted ? palette.foregroundMuted : palette.foreground)
        .padding(.horizontal, Tokens.Space.m)
        .frame(height: Tokens.Size.outlinedControl)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                .strokeBorder(palette.borderControl, lineWidth: Tokens.Size.line)
        )
        .contentShape(Rectangle())
    }
}

/// One editable number in a set row, such as weight or reps, in a soft filled cell.
struct NumberCell: View {
    @Environment(\.palette) private var palette
    @Binding var text: String
    var suffix = ""
    var isDone: Bool
    var accessibilityName: String

    var body: some View {
        HStack(spacing: 0) {
            TextField("", text: $text, prompt: Text("-").foregroundStyle(palette.foregroundFaint))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .fixedSize()
            if !suffix.isEmpty, !text.isEmpty {
                Text(suffix)
            }
        }
        .textStyle(Tokens.Typography.number)
        .monospacedDigit()
        .foregroundStyle(isDone ? palette.foreground : palette.foregroundFaint)
        .frame(maxWidth: .infinity)
        .frame(height: Tokens.Size.cell)
        .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityName)
    }
}

/// The RPE for a set, picked from 6 to 10 in half steps.
struct RPECell: View {
    @Environment(\.palette) private var palette
    @Binding var rpe: Double?
    var isDone: Bool

    private static let scale = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    var body: some View {
        Menu {
            Picker("RPE", selection: $rpe) {
                Text("None").tag(Double?.none)
                ForEach(Self.scale, id: \.self) { value in
                    Text(Self.format(value)).tag(Double?.some(value))
                }
            }
        } label: {
            Text(rpe.map(Self.format) ?? "-")
                .textStyle(Tokens.Typography.number)
                .monospacedDigit()
                .foregroundStyle(rpe != nil && isDone ? palette.foreground : palette.foregroundFaint)
                .frame(maxWidth: .infinity)
                .frame(height: Tokens.Size.cell)
                .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
        }
        .accessibilityLabel("RPE")
    }

    static func format(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }
}

/// The box you tick when a set is done. Gives a light haptic when ticked.
struct TickBox: View {
    @Environment(\.palette) private var palette
    let isDone: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Tokens.Radius.tick)
                .fill(isDone ? palette.foreground : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: Tokens.Radius.tick)
                        .strokeBorder(isDone ? palette.foreground : palette.borderStrong, lineWidth: Tokens.Size.line)
                )
                .overlay {
                    if isDone {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.background)
                    }
                }
                .frame(width: Tokens.Size.tick, height: Tokens.Size.tick)
                .frame(width: Tokens.Size.tickColumn, height: Tokens.Size.control, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: isDone) { _, done in done }
        .accessibilityLabel(isDone ? "Set done" : "Mark set done")
    }
}
