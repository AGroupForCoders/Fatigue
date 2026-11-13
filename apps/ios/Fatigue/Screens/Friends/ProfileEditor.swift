import SwiftUI

/// Picks your handle the first time, and changes your handle, bio and who sees new workouts after that.
struct ProfileEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(SocialStore.self) private var social
    let current: MyProfile?

    @State private var handle: String
    @State private var bio: String
    @State private var visibility: PostVisibility
    @State private var error: String?
    @State private var saving = false
    @FocusState private var focus: Field?

    private enum Field { case handle, bio }

    init(current: MyProfile?) {
        self.current = current
        _handle = State(initialValue: current?.handle ?? "")
        _bio = State(initialValue: current?.bio ?? "")
        _visibility = State(initialValue: current?.defaultVisibility ?? .everyone)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.xxl) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: Tokens.Space.s) {
                    Text(current == nil ? "Pick a handle" : "Your profile")
                        .textStyle(Tokens.Typography.title)
                        .foregroundStyle(palette.foreground)
                    if current == nil {
                        Text("Friends find you by it. You can change it later.")
                            .textStyle(Tokens.Typography.body)
                            .foregroundStyle(palette.foregroundMuted)
                    }
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

            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                LineField(label: "Handle", text: $handle, kind: .handle, isFocused: focus == .handle)
                    .focused($focus, equals: .handle)
                    .onSubmit(save)
                Text(error ?? "3 to 20 letters, numbers, dots or underscores.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(error == nil ? palette.foregroundMuted : palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Bio")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                TextField("", text: $bio, prompt: Text("What you're training for").foregroundStyle(palette.foregroundFaint), axis: .vertical)
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .lineLimit(1...4)
                    .focused($focus, equals: .bio)
                    .onChange(of: bio) { _, text in if text.count > 160 { bio = String(text.prefix(160)) } }
                Hairline()
            }

            VStack(alignment: .leading, spacing: Tokens.Space.s) {
                Text("Who sees workouts you share")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                Menu {
                    Picker("Who sees workouts you share", selection: $visibility) {
                        ForEach(PostVisibility.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                } label: {
                    OutlinedLabel(systemImage: visibility.systemImage, text: visibility.title, showsChevron: true)
                }
                Text("Each workout can change it when you share.")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
            }

            Spacer()
            PrimaryButton(title: saving ? "Saving" : "Save", action: save)
                .disabled(saving)
        }
        .padding(Tokens.Space.xxl)
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .onAppear { if current == nil { focus = .handle } }
    }

    private func save() {
        guard !saving else { return }
        let text = handle.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { error = "Pick a handle first."; return }
        var changes = ProfileChanges(bio: bio.trimmingCharacters(in: .whitespacesAndNewlines))
        if text != current?.handle { changes.handle = text }
        if visibility != current?.defaultVisibility { changes.defaultVisibility = visibility }
        saving = true
        Task {
            defer { saving = false }
            do {
                try await social.save(changes)
                dismiss()
            } catch {
                withAnimation(.quick) { self.error = error.localizedDescription }
            }
        }
    }
}

extension PostVisibility {
    var systemImage: String {
        switch self {
        case .everyone: "globe"
        case .friends: "person.2"
        case .onlyMe: "lock"
        }
    }
}
