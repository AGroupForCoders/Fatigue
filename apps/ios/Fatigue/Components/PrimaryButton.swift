import SwiftUI

/// The main action on a screen, such as Start workout or Finish.
/// There should be at most one of these on screen at a time.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Tokens.Typography.button)
                .foregroundStyle(Tokens.Colors.background)
                .frame(maxWidth: .infinity, minHeight: Tokens.Size.control)
                .background(Tokens.Colors.text, in: .rect(cornerRadius: Tokens.Radius.control))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PrimaryButton(title: "Start workout") {}
        .padding(Tokens.Space.xl)
        .background(Tokens.Colors.background)
}
