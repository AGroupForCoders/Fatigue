import SwiftUI

/// A sheet for picking exercises from the library: search, tick as many as you like, add them in one go.
/// Ticked exercises are added in the order you ticked them.
struct ExercisePicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onAdd: ([String]) -> Void

    @State private var search = ""
    @State private var picked: [String] = []

    private var results: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? ExerciseLibrary.all : ExerciseLibrary.all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Tokens.Space.l) {
                HStack {
                    Text("Add exercises")
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
                HStack(spacing: Tokens.Space.s) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.foregroundMuted)
                    TextField("", text: $search, prompt: Text("Search").foregroundStyle(palette.foregroundFaint))
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, Tokens.Space.m)
                .frame(height: Tokens.Size.control)
                .background(palette.surface, in: .rect(cornerRadius: Tokens.Radius.control))
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.top, Tokens.Space.xxl)
            .padding(.bottom, Tokens.Space.m)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results, id: \.self) { name in
                        let isPicked = picked.contains(name)
                        Button {
                            if isPicked { picked.removeAll { $0 == name } } else { picked.append(name) }
                        } label: {
                            HStack {
                                Text(name)
                                    .textStyle(Tokens.Typography.body)
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                                TickMark(isOn: isPicked)
                            }
                            .frame(minHeight: Tokens.Size.primaryButton)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressRow)
                        Hairline(soft: true)
                    }
                    if results.isEmpty {
                        Text("No exercise called \u{201C}\(search)\u{201D} yet. Custom exercises come next.")
                            .textStyle(Tokens.Typography.caption)
                            .foregroundStyle(palette.foregroundMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Tokens.Space.l)
                    }
                }
                .padding(.horizontal, Tokens.Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: picked.isEmpty ? "Pick exercises" : "Add \(picked.count) exercise\(picked.count == 1 ? "" : "s")") {
                onAdd(picked)
                dismiss()
            }
            .opacity(picked.isEmpty ? 0.4 : 1)
            .disabled(picked.isEmpty)
            .animation(.quick, value: picked.isEmpty)
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .sensoryFeedback(.selection, trigger: picked)
    }
}

/// The round tick on a pickable row: an outline when off, filled with a check when on.
struct TickMark: View {
    @Environment(\.palette) private var palette
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? palette.foreground : Color.clear)
            .overlay(Circle().strokeBorder(isOn ? palette.foreground : palette.borderStrong, lineWidth: Tokens.Size.line))
            .overlay {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.background)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(width: Tokens.Size.tick, height: Tokens.Size.tick)
            .animation(.quick, value: isOn)
    }
}
