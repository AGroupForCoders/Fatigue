import SwiftUI

/// Builds a new prebuilt workout: a name, then exercises from the library.
/// Each exercise starts with three empty rep sets, which you fill in the first time you do it.
struct RoutineEditor: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let onSave: (Routine) -> Void

    @State private var name = ""
    @State private var exercises: [RoutineExercise] = []
    @State private var picking = false
    @FocusState private var editingName: Bool

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty && !exercises.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text("New workout")
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

                    LineField(label: "Name", text: $name, kind: .name, isFocused: editingName)
                        .focused($editingName)
                        .submitLabel(.done)

                    Text("Exercises")
                        .textStyle(Tokens.Typography.caption)
                        .foregroundStyle(palette.foregroundMuted)
                        .padding(.top, Tokens.Space.xxxl)
                        .padding(.bottom, Tokens.Space.s)
                    Hairline()

                    ForEach(exercises) { exercise in
                        SwipeToDelete(accessibilityName: exercise.name) {
                            exercises.removeAll { $0.id == exercise.id }
                        } content: {
                            HStack {
                                Text(exercise.name)
                                    .textStyle(Tokens.Typography.body)
                                    .foregroundStyle(palette.foreground)
                                Spacer()
                                Text("\(exercise.sets.count) sets")
                                    .textStyle(Tokens.Typography.caption)
                                    .foregroundStyle(palette.foregroundMuted)
                            }
                            .frame(minHeight: Tokens.Size.primaryButton)
                        }
                        .transition(.opacity)
                        Hairline(soft: true)
                    }

                    Button { picking = true } label: {
                        HStack {
                            Text("Add exercises")
                            Spacer()
                            Image(systemName: "plus")
                        }
                        .textStyle(Tokens.Typography.body)
                        .foregroundStyle(palette.foreground)
                        .frame(minHeight: Tokens.Size.primaryButton)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressRow)
                    Hairline()
                }
                .padding(.horizontal, Tokens.Space.xxl)
                .padding(.top, Tokens.Space.xxl)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: "Save workout") {
                onSave(Routine(name: name.trimmingCharacters(in: .whitespaces), exercises: exercises))
                dismiss()
            }
            .opacity(canSave ? 1 : 0.4)
            .disabled(!canSave)
            .animation(.quick, value: canSave)
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.vertical, Tokens.Space.l)
        }
        .background(palette.background)
        .presentationDetents([.large])
        .presentationBackground(palette.background)
        .onAppear { editingName = true }
        .sheet(isPresented: $picking) {
            ExercisePicker { names in
                withAnimation(.standard) { exercises += names.map(RoutineExercise.new(named:)) }
            }
            .environment(\.palette, palette)
        }
    }
}
