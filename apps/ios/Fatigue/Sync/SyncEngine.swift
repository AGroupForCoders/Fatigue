import Foundation
import Observation

/// Runs sync and says where it stands. The app asks for a sync whenever something might have changed;
/// this makes sure one runs at a time, tries again after a failure, and remembers the result for Settings.
@Observable
final class SyncEngine {
    enum Status: Equatable {
        /// Nothing running, and the last sync worked (or none has run yet).
        case idle
        case syncing
        /// The server couldn't be reached. The next sync is asked for when the connection comes back.
        case offline
        /// The session has ended. Nothing syncs until the app signs in again. The data stays on the phone.
        case signedOut
        /// The server answered with an error. Another try is already scheduled.
        case failed
    }

    private(set) var status: Status = .idle
    /// When a sync last finished.
    private(set) var lastSynced: Date?
    /// Items changed on this phone that the server doesn't have yet, as of the last sync.
    private(set) var waiting = 0
    /// Items the server refused. They stay on the phone and aren't lost.
    private(set) var refused = 0
    /// Whether the server turned an item down because a newer build wrote it last.
    private(set) var needsUpdate = false

    /// Called after a pull wrote something, so the stores can read the database again.
    var onPulled: (PullOutcome) -> Void = { _ in }
    /// Called when the server says the session has ended.
    var onSignedOut: () -> Void = {}

    private let database: AppDatabase
    private let api: any SyncAPI
    private let token: () -> String?
    private let retryDelays: [Duration]
    private let batchSize: Int
    private let now: () -> Date

    private var running = false
    private var askedAgain = false
    private var failures = 0
    private var scheduled: Task<Void, Never>?

    /// - Parameters:
    ///   - token: The session token, or nil when signed out.
    ///   - retryDelays: How long to wait after each failure in a row. The last one repeats.
    init(
        database: AppDatabase, api: any SyncAPI = LiveSyncAPI(), token: @escaping () -> String?,
        retryDelays: [Duration] = [.seconds(2), .seconds(8), .seconds(30), .seconds(120), .seconds(300)],
        batchSize: Int = 100, now: @escaping () -> Date = Date.init
    ) {
        self.database = database
        self.api = api
        self.token = token
        self.retryDelays = retryDelays
        self.batchSize = batchSize
        self.now = now
    }

    /// Asks for a sync after a moment, replacing any earlier ask that hasn't started. A short delay lets
    /// several edits in a row go up as one push.
    func request(after delay: Duration = .zero) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.sync()
        }
    }

    /// Pushes and pulls now. If a sync is already running, it runs once more when that one ends, so a
    /// change made halfway through isn't left behind.
    func sync() async {
        guard !running else {
            askedAgain = true
            return
        }
        guard let token = token() else {
            status = .signedOut
            return
        }
        running = true
        defer { running = false }
        repeat {
            askedAgain = false
            status = .syncing
            do {
                // Off the main actor: the scan reads the whole database.
                let (report, waiting, refused) = try await Task.detached { [database, api, batchSize] in
                    let report = try await SyncRun(database: database, api: api, token: token, batchSize: batchSize).run()
                    return (report, try database.pendingSyncItems().count, try database.syncFailures().count)
                }.value
                self.waiting = waiting
                self.refused = refused
                needsUpdate = report.needsUpdate
                failures = 0
                lastSynced = now()
                status = .idle
                if report.pulled.applied > 0 { onPulled(report.pulled) }
            } catch SyncAPIError.offline {
                status = .offline
            } catch SyncAPIError.signedOut {
                status = .signedOut
                onSignedOut()
            } catch {
                status = .failed
                let delay = retryDelays.isEmpty ? nil : retryDelays[min(failures, retryDelays.count - 1)]
                failures += 1
                if let delay { request(after: delay) }
            }
        } while askedAgain && status == .idle
    }
}
