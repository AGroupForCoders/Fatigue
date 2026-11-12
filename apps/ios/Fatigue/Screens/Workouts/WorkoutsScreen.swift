import SwiftUI

/// The Workout tab: start an empty workout, start one of your prebuilt workouts, or build a new one.
struct WorkoutsScreen: View {
    @Environment(\.palette) private var palette
    @Environment(WorkoutStore.self) private var store
    @State private var creating = false
    @State private var editing: Routine?
    /// The routine waiting to start while you decide what to do with the workout already running.
    @State private var pendingStart: PendingStart?

    private enum PendingStart: Identifiable {
        case empty
        case routine(Routine)
        var id: String { if case .routine(let routine) = self { routine.id.uuidString } else { "empty" } }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Workout")
                    .textStyle(Tokens.Typography.title)
                    .foregroundStyle(palette.foreground)
                    .padding(.top, Tokens.Space.l)
                    .padding(.bottom, Tokens.Space.xxl)

                PrimaryButton(title: "Start an empty workout") { start(.empty) }

                Text("Your workouts")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .padding(.top, Tokens.Space.xxxl)
                    .padding(.bottom, Tokens.Space.s)
                Hairline()

                ForEach(store.routines) { routine in
                    SwipeToDelete(accessibilityName: routine.name) {
                        store.delete(routine.id)
                    } content: {
                        Button { start(.routine(routine)) } label: { row(routine) }
                            .buttonStyle(.pressRow)
                            .contextMenu {
                                Button("Edit workout", systemImage: "pencil") { editing = routine }
                                Button("Start workout", systemImage: "play") { start(.routine(routine)) }
                                Button("Delete workout", systemImage: "trash", role: .destructive) {
                                    withAnimation(.standard) { store.delete(routine.id) }
                                }
                            }
                    }
                    Hairline(soft: true)
                }

                Button { creating = true } label: {
                    HStack {
                        Text("Create new workout")
                        Spacer()
                        Image(systemName: "plus")
                    }
                    .textStyle(Tokens.Typography.body)
                    .foregroundStyle(palette.foreground)
                    .frame(minHeight: Tokens.Size.setRow)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressRow)
                Hairline()
            }
            .padding(.horizontal, Tokens.Space.xxl)
            .padding(.bottom, Tokens.Space.xxxl)
        }
        .background(palette.background)
        .sheet(isPresented: $creating) {
            RoutineEditor { store.add($0) }
                .environment(\.palette, palette)
        }
        .onAppear {
            // Debug builds open the first prebuilt workout in the editor with `-editRoutine`, for screenshots.
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-editRoutine"), editing == nil { editing = store.routines.first }
            #endif
        }
        .sheet(item: $editing) { routine in
            RoutineEditor(editing: routine) { store.update($0) }
                .environment(\.palette, palette)
        }
        .alert(
            "\(store.active?.title ?? "A workout") is still running",
            isPresented: Binding(get: { pendingStart != nil }, set: { if !$0 { pendingStart = nil } }),
            presenting: pendingStart
        ) { pending in
            Button("Resume it") { store.isShowingActive = true }
            Button("Discard it and start", role: .destructive) { begin(pending) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Only one workout runs at a time.")
        }
    }

    private func row(_ routine: Routine) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: Tokens.Space.xs) {
                Text(routine.name)
                    .textStyle(Tokens.Typography.exerciseName)
                    .foregroundStyle(palette.foreground)
                Text(routine.exercises.map(\.name).joined(separator: ", "))
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundMuted)
                    .lineLimit(1)
                Text("\(routine.exercises.count) exercises · \(routine.setCount) sets")
                    .textStyle(Tokens.Typography.caption)
                    .foregroundStyle(palette.foregroundFaint)
            }
            Spacer(minLength: Tokens.Space.l)
            Image(systemName: "play")
                .imageScale(.small)
                .foregroundStyle(palette.foreground)
                .frame(width: Tokens.Size.outlinedControl, height: Tokens.Size.outlinedControl)
                .overlay(Circle().strokeBorder(palette.borderControl, lineWidth: Tokens.Size.line))
                .accessibilityHidden(true)
        }
        .padding(.vertical, Tokens.Space.l)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Starts this workout. Press and hold to edit it.")
    }

    private func start(_ pending: PendingStart) {
        if store.active != nil { pendingStart = pending } else { begin(pending) }
    }

    private func begin(_ pending: PendingStart) {
        switch pending {
        case .empty: store.startEmpty()
        case .routine(let routine): store.start(routine)
        }
    }
}
