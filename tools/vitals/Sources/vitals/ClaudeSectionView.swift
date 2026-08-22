import AppKit
import VitalsClaude

/// Everything the Claude section renders. Built from the network snapshot
/// (status + usage, refreshed every 60s) and the local session registry
/// (refreshed with the 2s system tick). Add future `.claude` data here.
struct ClaudeSectionModel: Equatable {
    let telemetry: ClaudeTelemetrySnapshot
    let sessions: ClaudeSessionsSnapshot
    let now: Date

    static let usageRowHeight = 44.0
    static let messageHeight = 34.0
    static let headerHeight = 30.0
    static let sessionsHeaderHeight = 22.0
    static let sessionRowHeight = 22.0
    static let bottomPadding = 6.0
    static let maxSessionRows = 6

    var visibleSessions: [ClaudeSession] {
        Array(sessions.sessions.prefix(Self.maxSessionRows))
    }

    var hiddenSessionCount: Int {
        max(0, sessions.sessions.count - Self.maxSessionRows)
    }

    /// Menu item views cannot resize while the menu is open, so the controller
    /// re-renders when this changes.
    var layoutSignature: String {
        "\(telemetry.usage.rows.count)/\(visibleSessions.count)/\(hiddenSessionCount > 0)"
    }

    var height: CGFloat {
        var height = Self.headerHeight
        let usageRows = telemetry.usage.rows.count
        height += usageRows > 0
            ? Double(usageRows) * Self.usageRowHeight
            : Self.messageHeight
        height += Self.sessionsHeaderHeight
        height += Double(visibleSessions.count) * Self.sessionRowHeight
        if hiddenSessionCount > 0 {
            height += Self.sessionRowHeight
        }
        height += Self.bottomPadding
        return height
    }
}

@MainActor
final class ClaudeSectionView: NSView {
    private let sectionLabel = NSTextField(labelWithString: "CLAUDE")
    private let statusBadge = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let sessionsLabel = NSTextField(labelWithString: "SESSIONS")
    private let sessionsDetail = NSTextField(labelWithString: "")
    private let moreLabel = NSTextField(labelWithString: "")
    private var usageRows: [MetricBarView] = []
    private var sessionRows: [ClaudeSessionRowView] = []
    private var model: ClaudeSectionModel

    init(model: ClaudeSectionModel) {
        self.model = model
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: model.height))

        sectionLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        sectionLabel.textColor = Palette.secondary

        statusBadge.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        statusBadge.alignment = .center
        statusBadge.drawsBackground = true
        statusBadge.wantsLayer = true
        statusBadge.layer?.cornerRadius = 8
        statusBadge.layer?.masksToBounds = true

        messageLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        messageLabel.textColor = Palette.secondary
        messageLabel.alignment = .center

        sessionsLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        sessionsLabel.textColor = Palette.secondary
        sessionsDetail.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        sessionsDetail.textColor = Palette.secondary
        sessionsDetail.alignment = .right

        moreLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        moreLabel.textColor = Palette.secondary

        addSubview(sectionLabel)
        addSubview(statusBadge)
        addSubview(messageLabel)
        addSubview(sessionsLabel)
        addSubview(sessionsDetail)
        addSubview(moreLabel)
        rebuildRows()
        apply()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// Returns `false` when the new model needs a different number of rows;
    /// the caller must then rebuild the menu item.
    @discardableResult
    func update(_ model: ClaudeSectionModel) -> Bool {
        let sameShape = model.layoutSignature == self.model.layoutSignature
        self.model = model
        guard sameShape else { return false }
        apply()
        return true
    }

    private func rebuildRows() {
        usageRows.forEach { $0.removeFromSuperview() }
        sessionRows.forEach { $0.removeFromSuperview() }
        usageRows = model.telemetry.usage.rows.map { _ in MetricBarView() }
        sessionRows = model.visibleSessions.map { _ in ClaudeSessionRowView() }
        usageRows.forEach(addSubview)
        sessionRows.forEach(addSubview)
    }

    private func apply() {
        let health = model.telemetry.health
        let color: NSColor
        switch health.level {
        case .operational: color = Palette.mint
        case .degraded: color = Palette.amber
        case .outage: color = Palette.coral
        case .unavailable: color = Palette.secondary
        }
        statusBadge.stringValue = health.label
        statusBadge.textColor = color
        statusBadge.backgroundColor = color.withAlphaComponent(0.13)
        statusBadge.toolTip = health.detail

        for (view, row) in zip(usageRows, model.telemetry.usage.rows) {
            view.update(
                title: row.label,
                detail: row.detail,
                fraction: row.fraction,
                color: Palette.usage(row.fraction)
            )
        }
        messageLabel.stringValue = model.telemetry.usage.unavailableMessage ?? ""
        messageLabel.isHidden = model.telemetry.usage.unavailableMessage == nil

        let sessions = model.sessions
        let busy = sessions.busyCount
        sessionsDetail.stringValue = sessions.sessions.isEmpty
            ? "none running"
            : "\(busy) busy · \(sessions.sessions.count - busy) idle"
        sessionsDetail.textColor = busy > 0 ? Palette.blue : Palette.secondary
        for (view, session) in zip(sessionRows, model.visibleSessions) {
            view.update(session, now: model.now)
        }
        moreLabel.stringValue = model.hiddenSessionCount > 0
            ? "… \(model.hiddenSessionCount) more"
            : ""
        moreLabel.isHidden = model.hiddenSessionCount == 0
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let inset = 16.0
        let contentWidth = width - inset * 2
        var y = bounds.height - ClaudeSectionModel.headerHeight

        sectionLabel.frame = NSRect(x: inset, y: y + 8, width: contentWidth - 116, height: 14)
        statusBadge.frame = NSRect(x: width - 112, y: y + 4, width: 96, height: 17)

        if usageRows.isEmpty {
            y -= ClaudeSectionModel.messageHeight
            messageLabel.frame = NSRect(x: inset, y: y, width: contentWidth, height: 34)
        } else {
            for row in usageRows {
                y -= ClaudeSectionModel.usageRowHeight
                row.frame = NSRect(x: inset, y: y + 2, width: contentWidth, height: 42)
            }
        }

        y -= ClaudeSectionModel.sessionsHeaderHeight
        sessionsLabel.frame = NSRect(x: inset, y: y + 2, width: 100, height: 14)
        sessionsDetail.frame = NSRect(x: inset + 100, y: y + 2, width: contentWidth - 100, height: 14)

        for row in sessionRows {
            y -= ClaudeSectionModel.sessionRowHeight
            row.frame = NSRect(x: inset, y: y, width: contentWidth, height: ClaudeSectionModel.sessionRowHeight)
        }
        if model.hiddenSessionCount > 0 {
            y -= ClaudeSectionModel.sessionRowHeight
            moreLabel.frame = NSRect(x: inset + 16, y: y + 3, width: contentWidth - 16, height: 15)
        }
    }
}

@MainActor
final class ClaudeSessionRowView: NSView {
    private let dot = NSView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let cwdLabel = NSTextField(labelWithString: "")
    private let ageLabel = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 22))

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5

        nameLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .semibold)
        nameLabel.textColor = Palette.primary
        nameLabel.lineBreakMode = .byTruncatingTail

        cwdLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        cwdLabel.textColor = Palette.secondary
        cwdLabel.lineBreakMode = .byTruncatingHead

        ageLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        ageLabel.textColor = Palette.secondary
        ageLabel.alignment = .right

        addSubview(dot)
        addSubview(nameLabel)
        addSubview(cwdLabel)
        addSubview(ageLabel)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(_ session: ClaudeSession, now: Date) {
        let color: NSColor
        switch session.status {
        case .busy: color = Palette.blue
        case .idle: color = Palette.mint
        case .unknown: color = Palette.secondary
        }
        dot.layer?.backgroundColor = color.cgColor
        nameLabel.stringValue = session.name
        cwdLabel.stringValue = session.abbreviatedCwd()
        ageLabel.stringValue = "\(session.status.rawValue) · \(Format.age(since: session.startedAt, now: now))"
        ageLabel.textColor = session.status == .busy ? Palette.blue : Palette.secondary
        toolTip = "pid \(session.pid) · \(session.cwd)\nsession \(session.sessionId)"
            + (session.version.map { "\nClaude Code \($0)" } ?? "")
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = bounds.width
        let ageWidth = 82.0
        let nameWidth = min(
            ceil((nameLabel.stringValue as NSString).size(
                withAttributes: [.font: nameLabel.font as Any]
            ).width) + 4,
            140
        )
        dot.frame = NSRect(x: 0, y: 7.5, width: 7, height: 7)
        nameLabel.frame = NSRect(x: 13, y: 3, width: nameWidth, height: 16)
        let cwdX = 13 + nameWidth + 8
        cwdLabel.frame = NSRect(
            x: cwdX,
            y: 3.5,
            width: max(0, width - cwdX - ageWidth - 8),
            height: 15
        )
        ageLabel.frame = NSRect(x: width - ageWidth, y: 3.5, width: ageWidth, height: 15)
    }
}
