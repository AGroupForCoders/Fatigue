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

/// What the sign-out warning says: what would be lost, most important first.
struct SignOutWarning: Equatable {
    let unsaved: UnsavedOnPhone

    /// The first thing that would be lost.
    var title: String {
        lines.first ?? "Some of this phone's data isn't backed up"
    }

    /// Everything that would be lost, one sentence each.
    var lines: [String] {
        var lines: [String] = []
        let u = unsaved
        if u.workouts > 0 {
            lines.append(u.workouts == 1 ? "1 workout isn't backed up yet" : "\(u.workouts) workouts aren't backed up yet")
        } else if u.items > 0 {
            lines.append(u.items == 1 ? "1 change isn't backed up yet" : "\(u.items) changes aren't backed up yet")
        }
        if u.running { lines.append("A workout is still running") }
        if u.refused > 0 { lines.append(u.refused == 1 ? "1 change couldn't be backed up" : "\(u.refused) changes couldn't be backed up") }
        if u.media > 0 { lines.append(u.media == 1 ? "1 photo or video is only on this phone" : "\(u.media) photos and videos are only on this phone") }
        return lines
    }

    /// The rest after the title, for the dialog's message.
    var message: String {
        let rest = lines.dropFirst().map { $0 + "." }
        return (rest + ["Signing out removes them from this phone for good. Everything else comes back when you sign in again."]).joined(separator: " ")
    }

    /// What the alert says when another account's data on this phone would be lost by taking it over.
    var otherAccountMessage: String {
        let all = lines.map { $0 + "." }.joined(separator: " ")
        return "From the account signed in before: \(all) Remove them to back up and sync your own account here."
    }
}
