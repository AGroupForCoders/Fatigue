import SwiftUI

/// Asks for the email and sends a reset link. Opened from "Forgot password?" on the sign-in screen.
struct ForgotPasswordSheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @State var email: String
    @State private var error: String?
    @State private var isWorking = false
    @State private var sent = false
    @FocusState private var focused: Bool

    private var canSubmit: Bool { email.contains("@") && !isWorking }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sent ? "Check your email" : "Reset password")
                .textStyle(Tokens.Typography.title)
                .foregroundStyle(palette.foreground)
                .padding(.top, Tokens.Space.xxl)
                .contentTransition(.opacity)
            Text(sent
                 ? "If there's an account for \(email.trimmingCharacters(in: .whitespacesAndNewlines)), a link to set a new password is on its way. Open it on this phone."
                 : "Enter the email you signed up with and we'll send a link to set a new password.")
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foregroundMuted)
                .padding(.top, Tokens.Space.s)
                .padding(.bottom, Tokens.Space.xxl)
                .contentTransition(.opacity)

            if !sent {
                LineField(label: "Email", text: $email, kind: .email, isFocused: focused)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .transition(.opacity)
                if let error {
                    Text(error)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.accent)
                        .padding(.top, Tokens.Space.m)
                }
            }

            Spacer(minLength: Tokens.Space.xxl)
            if sent {
                PrimaryButton(title: "Done") { dismiss() }
                    .padding(.bottom, Tokens.Space.l)
            } else {
                PrimaryButton(title: isWorking ? "One moment" : "Send link", action: submit)
                    .opacity(canSubmit || isWorking ? 1 : 0.4)
                    .disabled(!canSubmit)
                    .padding(.bottom, Tokens.Space.l)
            }
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.medium])
        .presentationBackground(palette.background)
        .animation(.standard, value: sent)
        .onAppear { if email.isEmpty { focused = true } }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: sent) { _, new in new }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = false
        isWorking = true
        error = nil
        Task {
            do {
                try await auth.requestPasswordReset(email: email)
                sent = true
            } catch {
                withAnimation(.quick) { self.error = error.localizedDescription }
            }
            isWorking = false
        }
    }
}

#Preview {
    ThemeProvider { Color.clear.sheet(isPresented: .constant(true)) { ForgotPasswordSheet(email: "") } }
        .environment(AuthStore())
}
