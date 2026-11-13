import SwiftUI
import UniformTypeIdentifiers

/// Everything about your account and the app, opened from the gear on the profile:
/// name and email, weight unit, theme, backup, importing from Hevy, sign out and delete account.
struct SettingsScreen: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(AuthStore.self) private var auth
    @Environment(WorkoutStore.self) private var store
    @Environment(ExerciseCatalog.self) private var catalog
    @Environment(SyncEngine.self) private var sync
    @AppStorage(WeightUnit.storageKey) private var weightUnit: WeightUnit = .kg
    @State private var name = ""
    @State private var renameError: String?
    @State private var deleting = false
    @State private var verificationSent = false
    @State private var verificationError: String?
    @State private var pickingHevyFile = false
    @State private var importResult: HevyImportResult?
    @State private var showingImportResult = false
    @State private var importError: String?
    @State private var signingOut = false
    /// What's still waiting when you sign out, for the warning. Non-nil shows it.
    @State private var unsent: SignOutWarning?
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
                    Text("Settings")
                        .textStyle(Tokens.Typography.title)
                        .foregroundStyle(palette.foreground)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(palette.foreground)
                            .frame(width: Tokens.Size.control, height: Tokens.Size.control)
                    }
                    .buttonStyle(.press)
                    .accessibilityLabel("Close")
                }
                .padding(.bottom, Tokens.Space.xxl)

                Text("Account")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.bottom, Tokens.Space.l)

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
                        verification(account)
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
                    choices(WeightUnit.allCases.map(\.rawValue), selected: weightUnit.rawValue) {
                        weightUnit = WeightUnit(rawValue: $0) ?? .kg
                        sync.saveWeightUnit(weightUnit.rawValue)
                    }
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

                Text("Data")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.top, Tokens.Space.xxxl + Tokens.Space.l)
                    .padding(.bottom, Tokens.Space.s)
                Hairline()
                settingRow("Backup") {
                    SyncStatusLine()
                }
                Hairline(soft: true)
                Button { pickingHevyFile = true } label: {
                    rowLabel("Import from Hevy", color: palette.foreground)
                }
                .buttonStyle(.pressRow)
                Hairline()
                Text(importError ?? "Pick the CSV from Hevy's Export Data. Workouts already imported are skipped.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(importError == nil ? palette.foregroundMuted : palette.accent)
                    .padding(.top, Tokens.Space.m)

                Button(action: signOut) {
                    rowLabel(signingOut ? "Backing up…" : "Sign out", color: palette.foreground)
                }
                .buttonStyle(.pressRow)
                .disabled(signingOut)
                .padding(.top, Tokens.Space.xxxl)
                Hairline()
                Button { deleting = true } label: {
                    rowLabel("Delete account", color: palette.accent)
                }
                .buttonStyle(.pressRow)
                Hairline()
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.xxl)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .onAppear {
            name = account.name
            sync.refreshCounts()
        }
        .confirmationDialog(unsent?.title ?? "", isPresented: Binding(get: { unsent != nil }, set: { if !$0 { unsent = nil } }), titleVisibility: .visible) {
            Button("Sign out and lose them", role: .destructive) {
                sync.wipe()
                Task { await auth.signOut() }
            }
            Button("Stay signed in", role: .cancel) {}
        } message: {
            Text(unsent?.message ?? "")
        }
        .task {
            // The link in the verification email may have been opened on another device.
            if !account.emailVerified { await auth.restore() }
        }
        .onChange(of: editingName) { _, editing in if !editing { saveName() } }
        .sheet(isPresented: $deleting) {
            DeleteAccountSheet()
                .environment(\.palette, palette)
                .environment(sync)
        }
        .fileImporter(isPresented: $pickingHevyFile, allowedContentTypes: [.commaSeparatedText, .plainText]) { picked in
            switch picked {
            case .success(let url): importHevy(from: url)
            case .failure(let error): importError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showingImportResult) {
            if let importResult {
                HevyImportResultSheet(result: importResult)
                    .environment(\.palette, palette)
            }
        }
    }

    /// Backs up what's waiting, then signs out and empties the phone. Asks first if something couldn't go up.
    private func signOut() {
        signingOut = true
        // The running workout is saved a moment after each change. Save it now so it's counted.
        store.saveActive()
        Task {
            let unsaved = await sync.prepareSignOut()
            signingOut = false
            if unsaved.isEmpty {
                sync.wipe()
                await auth.signOut()
            } else {
                unsent = SignOutWarning(unsaved: unsaved)
            }
        }
    }

    /// Reads the picked file and imports it. The file sits outside the app's sandbox, so it's opened with its permission first.
    private func importHevy(from url: URL) {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let csv = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            importResult = try store.importHevy(csv: csv, catalog: catalog)
            importError = nil
            showingImportResult = true
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Whether the email has been verified, with a way to get the email again if not.
    private func verification(_ account: Account) -> some View {
        HStack(spacing: Tokens.Space.m) {
            if account.emailVerified {
                Image(systemName: "checkmark")
                    .imageScale(.small)
                Text("Email verified")
            } else {
                Text(verificationError ?? (verificationSent ? "Verification email sent. Check your inbox." : "Email not verified"))
                    .foregroundStyle(verificationError == nil ? palette.foregroundMuted : palette.accent)
            }
            Spacer(minLength: 0)
            if !account.emailVerified && !verificationSent {
                Button(action: sendVerification) {
                    Text("Resend")
                        .foregroundStyle(palette.foreground)
                        .frame(minHeight: Tokens.Space.xxl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressRow)
            }
        }
        .textStyle(Tokens.Typography.caption)
        .foregroundStyle(palette.foregroundMuted)
        .frame(minHeight: Tokens.Space.xxl, alignment: .leading)
        .animation(.quick, value: account.emailVerified)
        .animation(.quick, value: verificationSent)
    }

    private func sendVerification() {
        Task {
            do {
                try await auth.sendVerificationEmail()
                verificationError = nil
                verificationSent = true
            } catch {
                verificationError = error.localizedDescription
            }
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
    @Environment(SyncEngine.self) private var sync
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
                // The server's copy is gone with the account, so the phone's goes too, without asking.
                sync.wipe()
            } catch {
                self.error = error.localizedDescription
            }
            isWorking = false
        }
    }
}
