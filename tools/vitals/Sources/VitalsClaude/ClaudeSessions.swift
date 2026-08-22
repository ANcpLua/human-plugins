import Foundation

/// A running local Claude Code process, as registered in
/// `~/.claude/sessions/<pid>.json`.
public struct ClaudeSession: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Equatable {
        case busy
        case idle
        case unknown
    }

    public let pid: Int32
    public let sessionId: String
    public let name: String
    public let status: Status
    public let cwd: String
    public let startedAt: Date
    public let updatedAt: Date
    public let version: String?

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        sessionId: String,
        name: String,
        status: Status,
        cwd: String,
        startedAt: Date,
        updatedAt: Date,
        version: String?
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.name = name
        self.status = status
        self.cwd = cwd
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.version = version
    }

    /// `~/repo-playground/customer-desk` for display.
    public func abbreviatedCwd(
        homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) -> String {
        if cwd == homeDirectory { return "~" }
        if cwd.hasPrefix(homeDirectory + "/") {
            return "~" + cwd.dropFirst(homeDirectory.count)
        }
        return cwd
    }
}

public struct ClaudeSessionsSnapshot: Sendable, Equatable {
    public let sessions: [ClaudeSession]
    public let capturedAt: Date

    public init(sessions: [ClaudeSession], capturedAt: Date) {
        self.sessions = sessions
        self.capturedAt = capturedAt
    }

    public static let empty = ClaudeSessionsSnapshot(
        sessions: [],
        capturedAt: .distantPast
    )

    public var busyCount: Int {
        sessions.filter { $0.status == .busy }.count
    }
}

public enum ClaudeSessionParser {
    /// Decodes a single `sessions/<pid>.json` registry file. Cloud sessions
    /// never appear on disk; anything with an explicit non-local `kind` is
    /// skipped so a future registry schema cannot surface them by accident.
    public static func parse(_ data: Data) throws -> ClaudeSession? {
        let payload = try JSONDecoder().decode(SessionPayload.self, from: data)
        if let kind = payload.kind, kind != "interactive", kind != "local" {
            return nil
        }
        if let entrypoint = payload.entrypoint, entrypoint == "cloud" {
            return nil
        }
        let started = Date(timeIntervalSince1970: Double(payload.startedAt) / 1_000)
        let updated = payload.updatedAt.map {
            Date(timeIntervalSince1970: Double($0) / 1_000)
        } ?? started
        return ClaudeSession(
            pid: payload.pid,
            sessionId: payload.sessionId,
            name: payload.name ?? "claude-\(payload.pid)",
            status: payload.status.flatMap(ClaudeSession.Status.init(rawValue:))
                ?? .unknown,
            cwd: payload.cwd,
            startedAt: started,
            updatedAt: updated,
            version: payload.version
        )
    }

    /// Busy sessions first, then newest first.
    public static func sorted(_ sessions: [ClaudeSession]) -> [ClaudeSession] {
        sessions.sorted {
            if $0.status != $1.status {
                return $0.status == .busy
            }
            return $0.startedAt > $1.startedAt
        }
    }
}

public enum ClaudeSessionStore {
    /// Registry files whose process has exited are ignored. A file older than
    /// `staleAfter` is also ignored even if its pid is alive, which covers pid
    /// reuse after a crash.
    public static func load(
        home: ClaudeHome = ClaudeHome(),
        now: Date = Date(),
        staleAfter: TimeInterval = 86_400,
        isAlive: (Int32) -> Bool = processIsAlive
    ) -> ClaudeSessionsSnapshot {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: home.sessionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var sessions: [ClaudeSession] = []
        for file in files where file.pathExtension == "json" {
            guard Int32(file.deletingPathExtension().lastPathComponent) != nil,
                  let data = try? Data(contentsOf: file),
                  case .some(.some(let session)) = (try? ClaudeSessionParser.parse(data)),
                  isAlive(session.pid),
                  now.timeIntervalSince(session.updatedAt) < staleAfter
            else { continue }
            sessions.append(session)
        }
        return ClaudeSessionsSnapshot(
            sessions: ClaudeSessionParser.sorted(sessions),
            capturedAt: now
        )
    }

    public static func processIsAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }
}

private struct SessionPayload: Decodable {
    let pid: Int32
    let sessionId: String
    let cwd: String
    let startedAt: Int64
    let updatedAt: Int64?
    let name: String?
    let status: String?
    let kind: String?
    let entrypoint: String?
    let version: String?
}
