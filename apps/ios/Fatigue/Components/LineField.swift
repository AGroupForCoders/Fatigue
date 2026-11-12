import SwiftUI

/// A form field drawn as a label above the text and a hairline under it, with no box.
/// The line darkens while the field has the cursor.
struct LineField: View {
    enum Kind { case name, email, password, newPassword }

    @Environment(\.palette) private var palette
    let label: String
    @Binding var text: String
    var kind: Kind = .name
    var isFocused = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s) {
            Text(label)
                .textStyle(Tokens.Typography.caption)
                .foregroundStyle(palette.foregroundMuted)
            field
                .textStyle(Tokens.Typography.exerciseName)
                .foregroundStyle(palette.foreground)
                .frame(minHeight: Tokens.Size.control)
            Rectangle()
                .fill(isFocused ? palette.foreground : palette.border)
                .frame(height: Tokens.Size.line)
                .animation(.quick, value: isFocused)
        }
    }

    @ViewBuilder private var field: some View {
        switch kind {
        case .name:
            TextField("", text: $text)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
        case .email:
            TextField("", text: $text)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        case .password, .newPassword:
            SecureField("", text: $text)
                .textContentType(kind == .password ? .password : .newPassword)
        }
    }
}
