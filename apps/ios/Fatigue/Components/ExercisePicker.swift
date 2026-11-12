import SwiftUI

/// A sheet for picking exercises from the library: search, tick as many as you like, add them in one go.
/// Ticked exercises are added in the order you ticked them. Create exercise makes a custom one and ticks it.
struct ExercisePicker: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseCatalog.self) private var catalog
    let onAdd: ([String]) -> Void

    @State private var search = ""
    @State private var picked: [String] = []
    @State private var creating = false

    private var results: [String] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? catalog.names : catalog.names.filter { $0.localizedCaseInsensitiveContains(query) }
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
                    Button { creating = true } label: {
                        HStack {
                            Text(search.isEmpty ? "Create exercise" : "Create \u{201C}\(search.trimmingCharacters(in: .whitespaces))\u{201D}")
                                .textStyle(Tokens.Typography.body)
                                .foregroundStyle(palette.foreground)
                            Spacer()
                            Image(systemName: "plus").foregroundStyle(palette.foreground)
                        }
                        .frame(minHeight: Tokens.Size.primaryButton)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressRow)
                    Hairline()
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
        .sheet(isPresented: $creating) {
            ExerciseEditor(newNamed: search.trimmingCharacters(in: .whitespaces), existingNames: catalog.names) { edit in
                catalog.save(edit.info, brand: nil, setup: edit.setup)
                picked.append(edit.info.name)
                search = ""
            }
            .environment(\.palette, palette)
        }
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
