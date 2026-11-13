import SwiftUI

/// Opened by the link in a reset email. Takes the new password and saves it with the link's token.
struct ResetPasswordScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var saved = false
    @FocusState private var focused: Bool

    private var canSubmit: Bool { password.count >= 8 && !isWorking }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(saved ? "Password changed" : "Set a new password")
                .textStyle(Tokens.Typography.title)
                .foregroundStyle(palette.foreground)
                .padding(.top, Tokens.Space.xxl)
                .contentTransition(.opacity)
            Text(saved
                 ? "You're signed out everywhere. Sign in with your new password."
                 : "Pick a new password for your account. Every other phone signed in to it will be signed out.")
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foregroundMuted)
                .padding(.top, Tokens.Space.s)
                .padding(.bottom, Tokens.Space.xxl)
                .contentTransition(.opacity)

            if !saved {
                LineField(label: "New password", text: $password, kind: .newPassword, isFocused: focused)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit(submit)
                    .transition(.opacity)
                Text(error ?? "At least 8 characters.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(error == nil ? palette.foregroundMuted : palette.accent)
                    .padding(.top, Tokens.Space.m)
            }

            Spacer(minLength: Tokens.Space.xxl)
            if saved {
                PrimaryButton(title: "Sign in") { dismiss() }
                    .padding(.bottom, Tokens.Space.l)
            } else {
                PrimaryButton(title: isWorking ? "One moment" : "Save password", action: submit)
                    .opacity(canSubmit || isWorking ? 1 : 0.4)
                    .disabled(!canSubmit)
                    .padding(.bottom, Tokens.Space.l)
            }
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.medium])
        .presentationBackground(palette.background)
        .interactiveDismissDisabled(isWorking)
        .animation(.standard, value: saved)
        .onAppear { focused = true }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .sensoryFeedback(.success, trigger: saved) { _, new in new }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        isWorking = true
        error = nil
        Task {
            do {
                try await auth.resetPassword(newPassword: password)
                saved = true
            } catch {
                withAnimation(.quick) { self.error = error.localizedDescription }
            }
            isWorking = false
        }
    }
}

#Preview {
    ThemeProvider { Color.clear.sheet(isPresented: .constant(true)) { ResetPasswordScreen() } }
        .environment(AuthStore())
}
