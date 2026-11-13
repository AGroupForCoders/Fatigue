import Foundation
import GRDB
import Network
import Observation

/// Keeps the phone's data and the server's in step: pushes what changed, then pulls what's new.
/// The rules are on the Sync docs page; the database side is in `SyncStore.swift`.
///
/// One sync runs at a time. Asking for one while it runs queues one more for afterwards, so nothing
/// asked for is lost and requests never pile up.
@Observable
@MainActor
final class SyncEngine {
    /// Bump with any phone migration that adds or changes a synced column, after the API has it too.
    /// The server refuses an item from a build older than the one that last wrote it.
    static let schema = 1
    /// The most items one push sends, the same as the API takes.
    static let pageSize = 100
    /// How long after a change the push waits, so several edits go up as one.
    static let changeDelay: Duration = .seconds(2)
    /// Waits between tries after a server error or timeout. After the last, it keeps trying every five minutes.
    static let retryDelays: [Duration] = [.seconds(2), .seconds(8), .seconds(30), .seconds(120)]
    static let retryForever: Duration = .seconds(300)

    enum Status: Equatable {
        /// Nothing running and nothing wrong.
        case idle
        case syncing
        /// No connection. Starts again when it comes back.
        case offline
        /// The session expired. Waits for you to sign in again; nothing on the phone is lost.
        case needsSignIn
        /// The phone's data belongs to a different account than the one signed in, so nothing syncs.
        case otherAccount
        /// The server didn't answer. Tries again at this time.
        case retrying(at: Date)
    }

    private(set) var status: Status = .idle
    /// When the last sync finished without a problem.
    private(set) var lastSynced: Date?
    /// Some items were last written by a newer build. They wait until this app is updated.
    private(set) var updateNeeded = false
    /// What's waiting to go up, counted after each sync, for Settings.
    private(set) var waiting: (items: Int, workouts: Int) = (0, 0)
    /// Items the server refused, for Settings.
    private(set) var failedCount = 0
    /// When the phone's data belongs to another account: what of theirs would be lost by taking over.
    private(set) var otherAccountUnsaved = UnsavedOnPhone()

    /// The signed-in account, set by the app. Nil while signed out, when nothing syncs.
    var account: String? {
        didSet {
            guard account != oldValue else { return }
            if account == nil { status = .idle } else { sync() }
        }
    }

    /// Called after a pull wrote something, so the app can reload what it shows.
    var onPulled: (PullOutcome) -> Void = { _ in }
    /// Called after the phone was wiped, so the app can forget what it holds in memory.
    var onWiped: () -> Void = {}

    private enum Mode: Comparable {
        /// Only push, and only if something is waiting. What a change asks for.
        case push
        /// Push, then pull everything new.
        case full
    }

    private let database: AppDatabase?
    private let api: any SyncAPI
    private let token: @Sendable () -> String?
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: () -> Date

    @ObservationIgnored private var requested: Mode?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var retry: Task<Void, Never>?
    @ObservationIgnored private var retryAttempt = 0
    @ObservationIgnored private var changeTimer: Task<Void, Never>?
    @ObservationIgnored private var observation: AnyDatabaseCancellable?
    @ObservationIgnored private var monitor: NWPathMonitor?

    init(
        database: AppDatabase?,
        account: String? = nil,
        api: any SyncAPI = LiveSyncAPI(),
        token: @escaping @Sendable () -> String? = { TokenStore().read() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.account = account
        self.api = api
        self.token = token
        self.sleep = sleep
        self.now = now
    }

    // MARK: Asking for a sync

    /// Pushes what's waiting, then pulls what's new. For sign-in, launch, the foreground and a connection
    /// coming back.
    func sync() {
        request(.full)
    }

    /// Pushes a moment after a change, so several edits go up together.
    func changed() {
        changeTimer?.cancel()
        let sleep = sleep
        changeTimer = Task { [weak self] in
            guard (try? await sleep(Self.changeDelay)) != nil else { return }
            self?.request(.push)
        }
    }

    /// Syncs and waits for it, such as in the short time iOS gives an app going to the background.
    func syncNow() async {
        request(.full)
        await running?.value
    }

    /// Pushes what's waiting and waits for it.
    func pushNow() async {
        request(.push)
        await running?.value
    }

    private func request(_ mode: Mode) {
        requested = max(requested ?? mode, mode)
        guard running == nil else { return }
        running = Task { [weak self] in
            await self?.drain()
            self?.running = nil
        }
    }

    private func drain() async {
        while let mode = requested {
            requested = nil
            await perform(mode)
        }
    }

    // MARK: Watching

    /// Starts pushing after each change to a synced table, and syncing when the connection comes back.
    func startWatching() {
        if let database, observation == nil {
            let observation = DatabaseRegionObservation(tracking: AppDatabase.syncedTables.map { Table($0) })
            self.observation = try? observation.start(in: database.writer, onError: { _ in }, onChange: { [weak self] _ in
                Task { @MainActor in self?.changed() }
            })
        }
        if monitor == nil {
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in
                    guard let self, self.status == .offline else { return }
                    self.sync()
                }
            }
            monitor.start(queue: DispatchQueue(label: "sync.path"))
            self.monitor = monitor
        }
    }

    // MARK: A sync

    private func perform(_ mode: Mode) async {
        guard let database, let account, let token = token() else { return }

        // The data on this phone belongs to whoever first synced it. The first run adopts the signed-in account.
        // Another account gets the phone once nothing of the first one's would be lost; otherwise it asks first.
        do {
            if let owner = try database.syncOwner(), owner != account {
                let unsaved = try database.unsavedOnPhone()
                guard unsaved.isEmpty else {
                    otherAccountUnsaved = unsaved
                    status = .otherAccount
                    return
                }
                wipe()
                try database.setSyncOwner(account)
            } else if try database.syncOwner() == nil {
                try database.setSyncOwner(account)
            }
        } catch {
            return
        }

        let waiting = (try? database.pendingSyncItems()) ?? []
        if mode == .push, waiting.isEmpty { return }

        status = .syncing
        do throws(SyncFailure) {
            try await push(waiting, to: database, token: token)
            if mode == .full { try await pull(into: database, token: token) }
            status = .idle
            lastSynced = now()
            refreshCounts()
            retryAttempt = 0
            retry?.cancel()
            retry = nil
        } catch {
            switch error {
            case .offline: status = .offline
            case .unauthorized: status = .needsSignIn
            case .server: scheduleRetry()
            }
        }
    }

    // MARK: Signing out and wiping

    /// Pushes what's waiting, then says what a wipe would still lose, for the sign-out warning. Nothing
    /// means it's safe to wipe without asking.
    ///
    /// On top of what's waiting, that's items the server refused, a running workout and photos and videos,
    /// none of which the server has.
    func prepareSignOut() async -> UnsavedOnPhone {
        await pushNow()
        refreshCounts()
        guard let database else { return UnsavedOnPhone() }
        // If the count can't be read, assume the worst rather than wipe without asking.
        return (try? database.unsavedOnPhone()) ?? UnsavedOnPhone(items: max(waiting.items, 1))
    }

    /// Empties the phone's data and forgets what sync knew. For signing out, deleting the account, and
    /// another account taking over this phone.
    func wipe() {
        changeTimer?.cancel()
        retry?.cancel()
        try? database?.wipe()
        lastSynced = nil
        updateNeeded = false
        waiting = (0, 0)
        failedCount = 0
        otherAccountUnsaved = UnsavedOnPhone()
        if status == .otherAccount { status = .idle }
        onWiped()
    }

    /// Lets the signed-in account take over a phone holding another account's unsent data: wipes it, then
    /// syncs the signed-in account down.
    func takeOver() {
        guard let database, let account else { return }
        wipe()
        try? database.setSyncOwner(account)
        sync()
    }

    /// Saves a weight unit you picked to the account's settings, so your other phones switch too.
    func saveWeightUnit(_ unit: String) {
        guard let database, let account else { return }
        try? database.saveWeightUnit(unit, accountId: account)
    }

    /// Counts what's waiting and what failed again.
    func refreshCounts() {
        guard let database else { return }
        if let counts = try? database.waitingCounts() { waiting = counts }
        failedCount = (try? database.syncFailures().count) ?? 0
    }

    private func push(_ waiting: [LocalSyncItem], to database: AppDatabase, token: String) async throws(SyncFailure) {
        var start = 0
        while start < waiting.count {
            let page = Array(waiting[start..<min(start + Self.pageSize, waiting.count)])
            start += page.count
            let results = try await api.push(page.map(\.item), schema: Self.schema, token: token)
            var pushed: [LocalSyncItem] = []
            for (local, result) in zip(page, results) {
                switch result.status {
                case .saved, .older:
                    pushed.append(local)
                case .tooOld:
                    updateNeeded = true
                    try? database.markFailed(local, error: "too_old")
                case .invalid:
                    // One bad item mustn't hold up the rest.
                    try? database.markFailed(local, error: result.message ?? "The server refused it.")
                }
            }
            try? database.markSynced(pushed)
        }
    }

    private func pull(into database: AppDatabase, token: String) async throws(SyncFailure) {
        let start = (try? database.syncCursor()) ?? 0
        var cursor = start
        var items: [SyncItem] = []
        while true {
            let page = try await api.pull(after: cursor, token: token)
            items += page.items
            cursor = page.cursor
            if !page.more { break }
        }
        guard cursor != start || !items.isEmpty else { return }
        // Every page in one transaction, not one each. Pages come in the order items last changed, so a
        // workout can be pages ahead of a brand it uses that was edited later. Written page by page, that
        // workout's page would point at a brand the phone doesn't have yet, fail its foreign key check, and
        // be asked for again forever. If this fails nothing is written, and the next sync asks from the old cursor.
        guard let outcome = try? database.applyPulled(items, cursor: cursor) else {
            throw .server("Couldn't save what the server sent.")
        }
        if outcome.applied > 0 || outcome.weightUnit != nil { onPulled(outcome) }
    }

    private func scheduleRetry() {
        let delay = retryAttempt < Self.retryDelays.count ? Self.retryDelays[retryAttempt] : Self.retryForever
        retryAttempt += 1
        status = .retrying(at: now().addingTimeInterval(TimeInterval(delay.components.seconds)))
        retry?.cancel()
        let sleep = sleep
        retry = Task { [weak self] in
            guard (try? await sleep(delay)) != nil else { return }
            self?.sync()
        }
    }
}
