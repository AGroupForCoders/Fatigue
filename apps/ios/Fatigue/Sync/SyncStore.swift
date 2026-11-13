import Foundation
import Network
import Observation

/// Decides when to sync and shows how it's going. The engine does the work; this schedules it.
///
/// Sync runs on launch, when the app comes to the front, after a workout finishes, when the phone gets
/// back online, and a couple of seconds after any local change. Only one round runs at a time: a request
/// that arrives mid-round makes the engine go again when it's done, so nothing is skipped and nothing
/// overlaps. A failed round retries with a growing wait, unless the phone is offline (the network monitor
/// restarts it) or the app is too old to sync (nothing helps but an update).
@Observable
final class SyncStore {
    enum Status: Equatable {
        case signedOut
        case idle
        case syncing
        case synced(Date)
        case offline
        case failed(String)
        case outdated
    }

    enum Reason: Sendable {
        case launch, foreground, workoutFinished, backOnline, localChange, manual
    }

    private(set) var status: Status = .signedOut
    /// Rows waiting to be pushed.
    private(set) var pendingCount = 0

    private let database: AppDatabase?
    private let engine: SyncEngine?
    private let token: () -> String?
    private let accountId: () -> String?
    /// Called when a pull changed local rows, so the stores can read them back.
    var onApplied: (() -> Void)?

    private var debounce: Task<Void, Never>?
    private var retry: Task<Void, Never>?
    private var running = false
    private var runAgain = false
    private var failures = 0
    private let monitor = NWPathMonitor()
    private var wasOnline = true

    static let debounceDelay: Duration = .seconds(2)
    static let firstRetry: Duration = .seconds(30)
    static let longestRetry: Duration = .seconds(600)

    init(database: AppDatabase?, api: any SyncAPI = LiveSyncAPI(), token: @escaping () -> String?, accountId: @escaping () -> String?) {
        self.database = database
        self.engine = database.map { SyncEngine(database: $0, api: api) }
        self.token = token
        self.accountId = accountId
        if let last = try? database?.lastSyncedAt() { status = .synced(last) }
        refreshPendingCount()
        watchNetwork()
    }

    /// A store that never syncs, for when the database on the phone couldn't be opened.
    static let unavailable = SyncStore(database: nil, token: { nil }, accountId: { nil })

    // MARK: Triggers

    /// Asks for a round. Local changes wait a moment and fold together; everything else goes now.
    func requestSync(_ reason: Reason) {
        guard token() != nil else { return }
        debounce?.cancel()
        if reason == .localChange {
            refreshPendingCount()
            debounce = Task { [weak self] in
                try? await Task.sleep(for: Self.debounceDelay)
                guard !Task.isCancelled else { return }
                await self?.run()
            }
        } else {
            Task { await run() }
        }
    }

    /// The account signed in (or out). Data from another account is wiped before this one's comes down.
    /// Signing out keeps the rows, the outbox and the cursor: signing back into the same account carries
    /// on where it left off, and the stored account id is what tells a different account apart.
    func accountChanged() {
        retry?.cancel()
        debounce?.cancel()
        guard let accountId = accountId() else {
            status = .signedOut
            return
        }
        if let previous = try? database?.syncAccountId(), previous != accountId {
            try? database?.wipeSyncedData()
            onApplied?()
        }
        try? database?.setSyncAccountId(accountId)
        status = (try? database?.lastSyncedAt()).map(Status.synced) ?? .idle
        requestSync(.launch)
    }

    /// Forgets everything synced on this phone and downloads the server's copy again.
    func resetAndRedownload() async {
        retry?.cancel()
        debounce?.cancel()
        try? database?.wipeSyncedData()
        if let accountId = accountId() { try? database?.setSyncAccountId(accountId) }
        refreshPendingCount()
        onApplied?()
        await run()
    }

    /// Clears local sync state after the account was deleted: the server's rows are gone, so the outbox and cursor mean nothing.
    func accountDeleted() {
        retry?.cancel()
        debounce?.cancel()
        try? database?.wipeSyncedData()
        status = .signedOut
        refreshPendingCount()
        onApplied?()
    }

    // MARK: Running

    private func run() async {
        if running { runAgain = true; return }
        running = true
        repeat {
            runAgain = false
            await runOnce()
        } while runAgain
        running = false
    }

    private func runOnce() async {
        guard let token = token(), let engine else { return }
        retry?.cancel()
        status = .syncing
        do {
            let changed = try await engine.sync(token: token)
            failures = 0
            status = .synced(.now)
            refreshPendingCount()
            if changed { onApplied?() }
        } catch SyncError.offline {
            status = .offline
            refreshPendingCount()
        } catch SyncError.outdated {
            status = .outdated
        } catch SyncError.unauthorized {
            status = .failed("Sign in again to sync.")
        } catch {
            failures += 1
            status = .failed("Couldn't sync. Retrying…")
            refreshPendingCount()
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        let wait = min(Self.firstRetry * (1 << min(failures - 1, 10)), Self.longestRetry)
        retry = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            await self?.run()
        }
    }

    private func refreshPendingCount() {
        pendingCount = (try? database?.pendingCount()) ?? 0
    }

    private func watchNetwork() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cameBack = online && !wasOnline
                wasOnline = online
                if cameBack { requestSync(.backOnline) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "sync.network"))
    }

    // MARK: Showing it

    /// One line for Settings, such as "Synced 3 min ago" or "Offline · 4 changes waiting".
    var statusText: String {
        switch status {
        case .signedOut: "Sign in to sync"
        case .idle: "Not synced yet"
        case .syncing: "Syncing…"
        case .synced(let date):
            let ago = Date.now.timeIntervalSince(date)
            if ago < 60 { return "Synced just now" }
            return "Synced \(Self.relative.localizedString(for: date, relativeTo: .now))"
        case .offline: pendingCount == 0 ? "Offline" : "Offline · \(pendingCount) \(pendingCount == 1 ? "change" : "changes") waiting"
        case .failed(let message): message
        case .outdated: "Update the app to sync"
        }
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
