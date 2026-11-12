import SwiftUI

/// The first screen when nobody is signed in: sign in, or switch to creating an account.
struct SignInScreen: View {
    enum Field: Hashable { case name, email, password }

    @Environment(\.palette) private var palette
    @Environment(AuthStore.self) private var auth
    @State private var isCreating = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focused: Field?

    private var canSubmit: Bool {
        !email.isEmpty && password.count >= 8 && (!isCreating || !name.trimmingCharacters(in: .whitespaces).isEmpty) && !isWorking
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Tokens.Space.m) {
                    Text("Fatigue")
                        .textStyle(Tokens.Typography.numberLarge)
                        .foregroundStyle(palette.foreground)
                    Text(isCreating ? "Make an account to keep your history safe and on every phone you use." : "Every set, on every machine.")
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foregroundMuted)
                        .contentTransition(.opacity)
                }
                .padding(.top, Tokens.Space.xxxl * 2)
                .padding(.bottom, Tokens.Space.xxxl + Tokens.Space.l)

                VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
                    if isCreating {
                        LineField(label: "Name", text: $name, kind: .name, isFocused: focused == .name)
                            .focused($focused, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focused = .email }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    LineField(label: "Email", text: $email, kind: .email, isFocused: focused == .email)
                        .focused($focused, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focused = .password }
                    LineField(label: "Password", text: $password, kind: isCreating ? .newPassword : .password, isFocused: focused == .password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                }

                Group {
                    if let error {
                        Text(error)
                            .foregroundStyle(palette.accent)
                    } else if isCreating {
                        Text("At least 8 characters.")
                            .foregroundStyle(palette.foregroundMuted)
                    }
                }
                .textStyle(Tokens.Typography.caption)
                .padding(.top, Tokens.Space.m)
                .frame(minHeight: Tokens.Space.xxl, alignment: .top)
            }
            .padding(.horizontal, Tokens.Space.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: Tokens.Space.m) {
                PrimaryButton(title: isWorking ? "One moment" : (isCreating ? "Create account" : "Sign in"), action: submit)
                    .opacity(canSubmit || isWorking ? 1 : 0.4)
                    .disabled(!canSubmit)
                Button {
                    withAnimation(.standard) {
                        isCreating.toggle()
                        error = nil
                    }
                    focused = isCreating ? .name : .email
                } label: {
                    Text(isCreating ? "I have an account" : "Create an account")
                        .textStyle(Tokens.Typography.control)
                        .foregroundStyle(palette.foreground)
                        .frame(maxWidth: .infinity, minHeight: Tokens.Size.control)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressRow)
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
            .background(palette.background)
        }
        .background(palette.background)
        .overlay { GrainOverlay() }
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
    }

    private func submit() {
        guard canSubmit else { return }
        focused = nil
        isWorking = true
        error = nil
        Task {
            do {
                if isCreating {
                    try await auth.signUp(name: name, email: email, password: password)
                } else {
                    try await auth.signIn(email: email, password: password)
                }
            } catch {
                withAnimation(.quick) { self.error = error.localizedDescription }
            }
            isWorking = false
        }
    }
}

#Preview {
    ThemeProvider { SignInScreen() }
        .environment(AuthStore())
}
