import SwiftUI

/// Your account: name, email, how long you've been here, theme, sign out and delete.
struct ProfileScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.theme) private var theme
    @Environment(AuthStore.self) private var auth
    @AppStorage("weightUnit") private var weightUnit = "kg"
    @State private var name = ""
    @State private var renameError: String?
    @State private var deleting = false
    @FocusState private var editingName: Bool

    var body: some View {
        if let account = auth.account {
            content(account)
        }
    }

    private func content(_ account: Account) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        Text("Profile")
                            .textStyle(Tokens.Typography.title)
                            .foregroundStyle(palette.foreground)
                        Text("Lifting since \(account.createdAt.formatted(.dateTime.month(.wide).year()))")
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foregroundMuted)
                    }
                    Spacer()
                }
                .padding(.bottom, Tokens.Space.xxxl)

                VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
                    LineField(label: "Name", text: $name, kind: .name, isFocused: editingName)
                        .focused($editingName)
                        .submitLabel(.done)
                        .onSubmit(saveName)
                    VStack(alignment: .leading, spacing: Tokens.Space.s) {
                        Text("Email")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                        Text(account.email)
                            .textStyle(Tokens.Typography.exerciseName)
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(minHeight: Tokens.Size.control, alignment: .leading)
                        Hairline(soft: true)
                    }
                }
                if let renameError {
                    Text(renameError)
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.accent)
                        .padding(.top, Tokens.Space.m)
                }

                Text("Preferences")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.top, Tokens.Space.xxxl + Tokens.Space.l)
                    .padding(.bottom, Tokens.Space.s)
                Hairline()
                settingRow("Weight") {
                    choices(["kg", "lb"], selected: weightUnit) { weightUnit = $0 }
                }
                Hairline(soft: true)
                settingRow("Theme") {
                    Menu {
                        Picker("Theme", selection: Binding(get: { theme.theme }, set: theme.setTheme)) {
                            ForEach(Theme.choices, id: \.self) { Text($0.capitalized).tag($0) }
                        }
                    } label: {
                        OutlinedLabel(text: theme.theme.capitalized, showsChevron: true)
                    }
                }
                Hairline()

                Button { Task { await auth.signOut() } } label: {
                    rowLabel("Sign out", color: palette.foreground)
                }
                .buttonStyle(.pressRow)
                .padding(.top, Tokens.Space.xxxl)
                Hairline()
                Button { deleting = true } label: {
                    rowLabel("Delete account", color: palette.accent)
                }
                .buttonStyle(.pressRow)
                Hairline()
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.l)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .onAppear { name = account.name }
        .onChange(of: editingName) { _, editing in if !editing { saveName() } }
        .sheet(isPresented: $deleting) {
            DeleteAccountSheet()
                .environment(\.palette, palette)
        }
    }

    private func saveName() {
        Task {
            do {
                try await auth.rename(to: name)
                renameError = nil
            } catch {
                renameError = error.localizedDescription
                name = auth.account?.name ?? name
            }
        }
    }

    private func settingRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foreground)
            Spacer()
            control()
        }
        .frame(minHeight: Tokens.Size.setRow)
    }

    private func rowLabel(_ title: String, color: Color) -> some View {
        Text(title)
            .textStyle(Tokens.Typography.body)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.setRow - Tokens.Space.s, alignment: .leading)
            .contentShape(Rectangle())
    }

    private func choices(_ options: [String], selected: String, onPick: @escaping (String) -> Void) -> some View {
        HStack(spacing: Tokens.Space.s) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selected
                Button { onPick(option) } label: {
                    Text(option)
                        .textStyle(Tokens.Typography.control)
                        .foregroundStyle(isSelected ? palette.background : palette.foreground)
                        .frame(width: Tokens.Size.control + Tokens.Space.l, height: Tokens.Size.outlinedControl)
                        .background(isSelected ? palette.foreground : Color.clear, in: .rect(cornerRadius: Tokens.Radius.control))
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.control)
                                .strokeBorder(isSelected ? palette.foreground : palette.borderControl, lineWidth: Tokens.Size.line)
                        )
                        .animation(.quick, value: isSelected)
                }
                .buttonStyle(.press)
            }
        }
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Confirms deleting the account with the password, since it can't be undone.
private struct DeleteAccountSheet: View {
    @Environment(\.palette) private var palette
    @Environment(AuthStore.self) private var auth
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Delete account")
                .textStyle(Tokens.Typography.title)
                .foregroundStyle(palette.foreground)
                .padding(.top, Tokens.Space.xxl)
            Text("Your account and every workout in it are deleted for good. This can't be undone.")
                .textStyle(Tokens.Typography.body)
                .foregroundStyle(palette.foregroundMuted)
                .padding(.top, Tokens.Space.s)
                .padding(.bottom, Tokens.Space.xxl)

            LineField(label: "Password", text: $password, kind: .password, isFocused: focused)
                .focused($focused)
            if let error {
                Text(error)
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.accent)
                    .padding(.top, Tokens.Space.m)
            }

            Spacer(minLength: Tokens.Space.xxl)
            Button(action: delete) {
                Text(isWorking ? "Deleting" : "Delete my account")
                    .textStyle(Tokens.Typography.button)
                    .foregroundStyle(palette.background)
                    .frame(maxWidth: .infinity)
                    .frame(height: Tokens.Size.primaryButton)
                    .background(palette.accent, in: .rect(cornerRadius: Tokens.Radius.control))
            }
            .buttonStyle(.press)
            .opacity(password.isEmpty ? 0.4 : 1)
            .disabled(password.isEmpty || isWorking)
            .padding(.bottom, Tokens.Space.l)
        }
        .padding(.horizontal, Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.medium])
        .presentationBackground(palette.background)
        .onAppear { focused = true }
    }

    private func delete() {
        isWorking = true
        Task {
            do {
                try await auth.deleteAccount(password: password)
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }
}
