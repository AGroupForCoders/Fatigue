import SwiftUI

/// Where backing up stands, as one line in Settings: "Backed up just now", "3 workouts waiting", and so on.
/// Nothing about sync shows on the main screens.
struct SyncStatusLine: View {
    @Environment(\.palette) private var palette
    @Environment(SyncEngine.self) private var sync

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.text(for: sync, now: context.date))
                .textStyle(Tokens.Typography.control)
                .foregroundStyle(isProblem ? palette.accent : palette.foregroundMuted)
                .multilineTextAlignment(.trailing)
        }
    }

    private var isProblem: Bool {
        sync.updateNeeded || sync.failedCount > 0 || sync.status == .needsSignIn || sync.status == .otherAccount
    }

    /// The line, most pressing first.
    static func text(for sync: SyncEngine, now: Date) -> String {
        if sync.updateNeeded { return "Update the app to keep syncing" }
        switch sync.status {
        case .needsSignIn: return "Sign in again to back up"
        case .otherAccount: return "Another account's data is on this phone"
        case .syncing: return "Backing up…"
        default: break
        }
        if sync.failedCount > 0 { return sync.failedCount == 1 ? "1 item couldn't back up" : "\(sync.failedCount) items couldn't back up" }
        let waiting = waitingText(items: sync.waiting.items, workouts: sync.waiting.workouts)
        switch sync.status {
        case .offline: return waiting.map { "Offline · \($0)" } ?? "Offline"
        case .retrying: return waiting ?? "Trying again soon"
        default: break
        }
        if let waiting { return waiting }
        guard let last = sync.lastSynced else { return "Not backed up yet" }
        if now.timeIntervalSince(last) < 60 { return "Backed up just now" }
        return "Backed up \(last.formatted(.relative(presentation: .named)))"
    }

    private static func waitingText(items: Int, workouts: Int) -> String? {
        if workouts > 0 { return workouts == 1 ? "1 workout waiting to back up" : "\(workouts) workouts waiting to back up" }
        if items > 0 { return items == 1 ? "1 change waiting to back up" : "\(items) changes waiting to back up" }
        return nil
    }
}

/// What the sign-out warning says: how much would be lost.
struct SignOutWarning: Equatable {
    let items: Int
    let workouts: Int

    var title: String {
        switch workouts {
        case 0: items == 1 ? "1 change isn't backed up yet" : "\(items) changes aren't backed up yet"
        case 1: "1 workout isn't backed up yet"
        default: "\(workouts) workouts aren't backed up yet"
        }
    }
}
