import AppKit
import VitalsClaude
import VitalsCore
import VitalsKernel

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let claudeTelemetry = ClaudeTelemetryClient()
    private let claudeKeychainAuthorization = ClaudeKeychainAuthorization()
    private var alarmState = AlarmState()
    private var claudeAlertState = ClaudeAlertState()
    private var processCPUSmoother = ProcessCPUSmoother()
    private var previous: Frame?
    private var lastSnapshot: Snapshot?
    private var claudeSnapshot: ClaudeTelemetrySnapshot?
    private var menuIsOpen = false
    private var claudeRefreshInFlight = false
    private var dashboardView: VitalsDashboardView?
    private var claudeView: ClaudeSectionView?
    private var groupRows: [(pid: Int32, name: String, item: NSMenuItem)] = []
    private var memberRows: [(pid: Int32, name: String, item: NSMenuItem)] = []
    private let thresholds = Thresholds(
        diskFreeBytes: 10 * 1_073_741_824,
        diskRecoverBytes: 12 * 1_073_741_824
    )

    func start() {
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
        statusItem.button?.title = " Vitals"
        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform.path.ecg",
            accessibilityDescription: "Vitals"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.imagePosition = .imageLeading
        menu.appearance = NSAppearance(named: .darkAqua)
        menu.minimumWidth = 352
        statusItem.menu = menu
        menu.delegate = self
        menu.addItem(quitItem())
        refresh()
        refreshClaude()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.refresh()
            }
        }
        Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
                guard let self else { return }
                self.refreshClaude()
            }
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        if let snapshot = lastSnapshot {
            render(snapshot)
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        Task { @MainActor [weak self] in
            guard let self, !self.menuIsOpen else { return }
            self.menu.removeAllItems()
            self.dashboardView = nil
            self.claudeView = nil
            self.groupRows = []
            self.memberRows = []
            self.menu.addItem(self.quitItem())
        }
    }

    private func refresh() {
        let last = previous
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.sample(previous: last)
            await MainActor.run { self?.apply(result) }
        }
    }

    nonisolated private static func sample(previous: Frame?) -> Result<(Frame, Snapshot), MetricsError> {
        if let previous {
            return Sampler.capture().map { ($0, Derive.snapshot(previous: previous, current: $0)) }
        }
        return Sampler.capture().flatMap { first in
            usleep(300_000)
            return Sampler.capture().map { ($0, Derive.snapshot(previous: first, current: $0)) }
        }
    }

    private func apply(_ result: Result<(Frame, Snapshot), MetricsError>) {
        switch result {
        case let .success((frame, snapshot)):
            previous = frame
            let processes = processCPUSmoother.smooth(snapshot.processes)
            let displaySnapshot = Snapshot(
                cpuPercent: snapshot.cpuPercent,
                attributedCpuPercent: processes.reduce(0) {
                    $0 + ($1.cpuPercent ?? 0)
                },
                cores: snapshot.cores,
                memory: snapshot.memory,
                disk: snapshot.disk,
                processes: processes
            )
            lastSnapshot = displaySnapshot
            updateTitle(displaySnapshot)
            if menuIsOpen {
                updateLive(displaySnapshot)
            }
            let decision = Derive.evaluateAlarms(snapshot: snapshot, thresholds: thresholds, previous: alarmState)
            alarmState = decision.state
            for kind in decision.triggered { Notifier.deliver(kind, snapshot: snapshot) }
        case let .failure(error):
            statusItem.button?.title = "err"
            lastSnapshot = nil
            guard !menuIsOpen else { return }
            menu.removeAllItems()
            dashboardView = nil
            claudeView = nil
            groupRows = []
            memberRows = []
            menu.addItem(label(Printer.describe(error), color: Palette.coral))
            menu.addItem(.separator())
            menu.addItem(quitItem())
        }
    }

    private func render(_ snapshot: Snapshot) {
        menu.removeAllItems()
        dashboardView = nil
        claudeView = nil
        groupRows = []
        memberRows = []

        menu.addItem(viewItem(VitalsHeaderView()))
        menu.addItem(.separator())

        let dashboard = VitalsDashboardView(snapshot: snapshot)
        dashboardView = dashboard
        menu.addItem(viewItem(dashboard))
        menu.addItem(.separator())

        if let claudeSnapshot {
            let view = ClaudeSectionView(snapshot: claudeSnapshot)
            claudeView = view
            menu.addItem(viewItem(view))
            if claudeSnapshot.usage.requiresAuthorization {
                menu.addItem(viewItem(HintActionView(
                    title: "Enable Claude usage",
                    hint: "Keychain",
                    action: { [weak self] in
                        self?.refreshClaude(requestKeychainAuthorization: true)
                        self?.menu.cancelTracking()
                    }
                )))
            }
            menu.addItem(.separator())
        }

        menu.addItem(viewItem(ProcessHeaderView()))
        let processLimit = claudeSnapshot == nil ? 12 : 8
        for group in Derive.groups(snapshot.processes).prefix(processLimit) {
            menu.addItem(groupItem(group))
        }

        menu.addItem(.separator())
        menu.addItem(viewItem(HintActionView(
            title: "Refresh",
            hint: "Updated just now",
            action: { [weak self] in
                self?.refresh()
                self?.refreshClaude()
                self?.menu.cancelTracking()
            }
        )))
        menu.addItem(.separator())
        menu.addItem(quitItem())
    }

    private func updateLive(_ snapshot: Snapshot) {
        dashboardView?.update(snapshot)
        let groups = Dictionary(
            Derive.groups(snapshot.processes).map { ($0.root.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in groupRows {
            if let group = groups[row.pid] {
                setRowText(row.item, cpu: group.cpuPercent, mem: group.footprintBytes, name: groupName(group))
            } else {
                setRowText(row.item, cpu: nil, mem: nil, name: "\(row.name)  exited")
            }
        }
        let views = Dictionary(
            snapshot.processes.map { ($0.pid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for row in memberRows {
            if let view = views[row.pid] {
                setRowText(row.item, cpu: view.cpuPercent, mem: view.footprintBytes, name: memberName(view))
            } else {
                setRowText(row.item, cpu: nil, mem: nil, name: "\(row.name)  [\(row.pid)]  exited")
            }
        }
    }

    private func refreshClaude(
        requestKeychainAuthorization: Bool = false
    ) {
        guard !claudeRefreshInFlight else { return }
        claudeRefreshInFlight = true
        let credentialAccess: ClaudeCredentialAccess
        if requestKeychainAuthorization {
            credentialAccess = .interactive
        } else if claudeKeychainAuthorization.permitsBackgroundAccess {
            credentialAccess = .nonInteractive
        } else {
            credentialAccess = .disabled
        }

        Task { [weak self] in
            guard let self else { return }
            let snapshot = await self.claudeTelemetry.fetch(
                credentialAccess: credentialAccess
            )
            if requestKeychainAuthorization,
               case .available = snapshot.usage {
                self.claudeKeychainAuthorization.grant()
            } else if credentialAccess == .nonInteractive,
                      snapshot.usage.requiresAuthorization {
                self.claudeKeychainAuthorization.revoke()
            }
            self.claudeRefreshInFlight = false
            self.applyClaude(snapshot)
        }
    }

    private func applyClaude(_ snapshot: ClaudeTelemetrySnapshot) {
        let decision = ClaudeAlerts.evaluate(snapshot: snapshot, previous: claudeAlertState)
        claudeAlertState = decision.state
        claudeSnapshot = snapshot
        for alert in decision.triggered {
            Notifier.deliver(alert)
        }
        if let claudeView {
            claudeView.update(snapshot)
        } else if menuIsOpen, let lastSnapshot {
            render(lastSnapshot)
        }
    }

    private func updateTitle(_ snapshot: Snapshot) {
        let cpuFraction = normalizedCPU(snapshot)
        let availGiB = Double(snapshot.memory.available) / 1_073_741_824.0
        let diskFreeGiB = Double(snapshot.disk.free) / 1_073_741_824.0
        let ramState = switch snapshot.memory.pressure {
        case .green: "RAM OK"
        case .yellow: "RAM WARN"
        case .red: "RAM CRIT"
        }
        let diskFree = diskFreeGiB >= 10
            ? String(format: "%.0fG", diskFreeGiB)
            : String(format: "%.1fG", diskFreeGiB)
        let diskUsedFraction = snapshot.disk.total == 0
            ? 0
            : 1 - Double(snapshot.disk.free) / Double(snapshot.disk.total)
        let font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .medium)
        let title = NSMutableAttributedString(
            string: String(format: " %.0f%%", cpuFraction * 100),
            attributes: [.foregroundColor: Palette.usage(cpuFraction), .font: font]
        )
        title.append(NSAttributedString(
            string: "  ",
            attributes: [.foregroundColor: Palette.secondary, .font: font]
        ))
        title.append(NSAttributedString(
            string: ramState,
            attributes: [.foregroundColor: Palette.pressure(snapshot.memory.pressure), .font: font]
        ))
        title.append(NSAttributedString(
            string: "  ",
            attributes: [.foregroundColor: Palette.secondary, .font: font]
        ))
        title.append(NSAttributedString(
            string: "SSD \(diskFree)",
            attributes: [.foregroundColor: Palette.usage(diskUsedFraction), .font: font]
        ))
        statusItem.button?.attributedTitle = title
        statusItem.button?.toolTip = String(
            format: "CPU %.0f%% · RAM pressure %@ · %.1f GB available · %.1f GB SSD free",
            cpuFraction * 100,
            snapshot.memory.pressure.rawValue,
            availGiB,
            diskFreeGiB
        )
    }

    private func normalizedCPU(_ snapshot: Snapshot) -> Double {
        let capacity = Double(max(snapshot.cores, 1)) * 100
        return clamped((snapshot.cpuPercent ?? 0) / capacity)
    }

    private func groupName(_ group: ProcessGroup) -> String {
        group.members.count > 1 ? "\(group.root.name)  ×\(group.members.count)" : group.root.name
    }

    private func memberName(_ process: ProcessView) -> String {
        "\(process.name)  [\(process.pid)]"
    }

    private func groupItem(_ group: ProcessGroup) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        setRowText(item, cpu: group.cpuPercent, mem: group.footprintBytes, name: groupName(group))
        groupRows.append((pid: group.root.pid, name: group.root.name, item: item))
        if group.members.count == 1 {
            item.submenu = actionMenu(for: group.root.pid)
        } else {
            let submenu = NSMenu()
            for member in group.members.prefix(20) {
                submenu.addItem(memberItem(member))
            }
            if group.members.count > 20 {
                submenu.addItem(label("… \(group.members.count - 20) more"))
            }
            item.submenu = submenu
        }
        return item
    }

    private func memberItem(_ process: ProcessView) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        setRowText(item, cpu: process.cpuPercent, mem: process.footprintBytes, name: memberName(process))
        memberRows.append((pid: process.pid, name: process.name, item: item))
        item.submenu = actionMenu(for: process.pid)
        return item
    }

    private func setRowText(_ item: NSMenuItem, cpu: Double?, mem: UInt64?, name: String) {
        let cpuText = cpu.map { String(format: "%.0f%%", $0) } ?? "--"
        let memText = mem.map(compactBytes) ?? "--"
        let title = "\(pad(cpuText, 5))  \(pad(memText, 6))  \(name)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributed = NSMutableAttributedString(
            string: pad(cpuText, 5),
            attributes: [
                .font: font,
                .foregroundColor: cpu.map(Palette.processCPU) ?? Palette.secondary
            ]
        )
        attributed.append(NSAttributedString(
            string: "  \(pad(memText, 6))  ",
            attributes: [.font: font, .foregroundColor: mem == nil ? Palette.secondary : Palette.mint]
        ))
        attributed.append(NSAttributedString(
            string: name,
            attributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .medium),
                .foregroundColor: name.hasSuffix("exited") ? Palette.coral : Palette.primary
            ]
        ))
        item.title = title
        item.attributedTitle = attributed
    }

    private func actionMenu(for pid: Int32) -> NSMenu {
        let submenu = NSMenu()
        submenu.appearance = NSAppearance(named: .darkAqua)
        submenu.addItem(action("Stop (freeze, keep RAM)", #selector(stop(_:)), pid, color: Palette.amber))
        submenu.addItem(action("Resume", #selector(resume(_:)), pid, color: Palette.mint))
        submenu.addItem(.separator())
        submenu.addItem(action("Interrupt (graceful)", #selector(interrupt(_:)), pid, color: Palette.blue))
        submenu.addItem(action("Kill (force)", #selector(force(_:)), pid, color: Palette.coral))
        return submenu
    }

    private func action(_ title: String, _ selector: Selector, _ pid: Int32, color: NSColor) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = NSNumber(value: pid)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: color]
        )
        return item
    }

    private func label(_ text: String, color: NSColor = Palette.secondary) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: color]
        )
        item.isEnabled = false
        return item
    }

    private func viewItem(_ view: NSView) -> NSMenuItem {
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : String(repeating: " ", count: width - text.count) + text
    }

    private func quitItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Quit Vitals", action: #selector(quit), keyEquivalent: "q")
        item.target = self
        item.attributedTitle = NSAttributedString(
            string: "Quit Vitals",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: Palette.primary
            ]
        )
        return item
    }

    @objc private func stop(_ sender: NSMenuItem) { fire(Signals.stop, sender) }
    @objc private func resume(_ sender: NSMenuItem) { fire(Signals.resume, sender) }
    @objc private func interrupt(_ sender: NSMenuItem) { fire(Signals.interrupt, sender) }
    @objc private func force(_ sender: NSMenuItem) { fire(Signals.force, sender) }

    private func fire(_ signal: Int32, _ sender: NSMenuItem) {
        guard let value = sender.representedObject as? NSNumber else { return }
        _ = Signals.send(signal, to: value.int32Value)
        refresh()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

private struct UsageRowModel {
    let label: String
    let fraction: Double
    let detail: String
}

private struct UsageMenuModel {
    let pressure: Pressure
    let rows: [UsageRowModel]

    init(snapshot: Snapshot) {
        let cpuFraction = clamped(
            (snapshot.cpuPercent ?? 0) / (Double(max(snapshot.cores, 1)) * 100)
        )
        let memoryFraction = fraction(snapshot.memory.used, of: snapshot.memory.total)
        let diskUsed = snapshot.disk.total >= snapshot.disk.free
            ? snapshot.disk.total - snapshot.disk.free
            : 0

        pressure = snapshot.memory.pressure
        rows = [
            UsageRowModel(
                label: "CPU",
                fraction: cpuFraction,
                detail: String(
                    format: "%.0f%% · %.0f%% aggregate",
                    cpuFraction * 100,
                    snapshot.cpuPercent ?? 0
                )
            ),
            UsageRowModel(
                label: "Memory",
                fraction: memoryFraction,
                detail: "\(compactBytes(snapshot.memory.used)) used · \(compactBytes(snapshot.memory.available)) available"
            ),
            UsageRowModel(
                label: "Disk",
                fraction: fraction(diskUsed, of: snapshot.disk.total),
                detail: "\(compactBytes(snapshot.disk.free)) free · \(compactBytes(snapshot.disk.total)) total"
            )
        ]
    }
}

@MainActor
private final class VitalsHeaderView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Vitals")
    private let subtitleLabel = NSTextField(labelWithString: "System telemetry | updates every 2s")
    private let liveBadge = NSTextField(labelWithString: "LIVE")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: 58))

        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = Palette.primary
        subtitleLabel.font = NSFont.systemFont(ofSize: 10.5, weight: .medium)
        subtitleLabel.textColor = Palette.secondary

        liveBadge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        liveBadge.textColor = Palette.mint
        liveBadge.alignment = .center
        liveBadge.drawsBackground = true
        liveBadge.backgroundColor = Palette.mint.withAlphaComponent(0.13)
        liveBadge.wantsLayer = true
        liveBadge.layer?.cornerRadius = 9
        liveBadge.layer?.masksToBounds = true

        addSubview(titleLabel)
        addSubview(subtitleLabel)
        addSubview(liveBadge)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: 30, width: bounds.width - 100, height: 18)
        subtitleLabel.frame = NSRect(x: 16, y: 13, width: bounds.width - 32, height: 15)
        liveBadge.frame = NSRect(x: bounds.width - 66, y: 27, width: 50, height: 18)
    }
}

@MainActor
private final class VitalsDashboardView: NSView {
    private let sectionLabel = NSTextField(labelWithString: "SYSTEM HEALTH")
    private let pressureBadge = NSTextField(labelWithString: "")
    private let cpuRow = MetricBarView()
    private let memoryRow = MetricBarView()
    private let diskRow = MetricBarView()

    init(snapshot: Snapshot) {
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: 164))

        sectionLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        sectionLabel.textColor = Palette.secondary

        pressureBadge.font = NSFont.systemFont(ofSize: 9.5, weight: .bold)
        pressureBadge.alignment = .center
        pressureBadge.drawsBackground = true
        pressureBadge.wantsLayer = true
        pressureBadge.layer?.cornerRadius = 8
        pressureBadge.layer?.masksToBounds = true

        addSubview(sectionLabel)
        addSubview(pressureBadge)
        addSubview(cpuRow)
        addSubview(memoryRow)
        addSubview(diskRow)
        update(snapshot)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(_ snapshot: Snapshot) {
        let model = UsageMenuModel(snapshot: snapshot)
        for (view, row) in zip([cpuRow, memoryRow, diskRow], model.rows) {
            view.update(
                title: row.label,
                detail: row.detail,
                fraction: row.fraction,
                color: Palette.usage(row.fraction)
            )
        }

        let pressureColor = Palette.pressure(model.pressure)
        pressureBadge.stringValue = model.pressure.rawValue.uppercased()
        pressureBadge.textColor = pressureColor
        pressureBadge.backgroundColor = pressureColor.withAlphaComponent(0.13)
    }

    override func layout() {
        super.layout()
        sectionLabel.frame = NSRect(x: 16, y: 141, width: bounds.width - 110, height: 14)
        pressureBadge.frame = NSRect(x: bounds.width - 76, y: 137, width: 60, height: 17)
        cpuRow.frame = NSRect(x: 16, y: 93, width: bounds.width - 32, height: 42)
        memoryRow.frame = NSRect(x: 16, y: 49, width: bounds.width - 32, height: 42)
        diskRow.frame = NSRect(x: 16, y: 5, width: bounds.width - 32, height: 42)
    }
}

@MainActor
final class MetricBarView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let track = NSView()
    private let fill = NSView()
    private var progress = 0.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = Palette.primary
        titleLabel.lineBreakMode = .byTruncatingTail
        detailLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        detailLabel.textColor = Palette.secondary
        detailLabel.alignment = .right
        detailLabel.lineBreakMode = .byTruncatingHead

        track.wantsLayer = true
        track.layer?.backgroundColor = Palette.track.cgColor
        track.layer?.cornerRadius = 4
        track.layer?.masksToBounds = true
        fill.wantsLayer = true
        fill.layer?.cornerRadius = 4
        fill.layer?.masksToBounds = true

        track.addSubview(fill)
        addSubview(titleLabel)
        addSubview(detailLabel)
        addSubview(track)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(title: String, detail: String, fraction: Double, color: NSColor) {
        titleLabel.stringValue = title
        detailLabel.stringValue = detail
        progress = clamped(fraction)
        fill.layer?.backgroundColor = color.cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let gap = 8.0
        let minimumTitleWidth = 72.0
        let measuredDetailWidth = (detailLabel.stringValue as NSString).size(
            withAttributes: [.font: detailLabel.font as Any]
        ).width + 12
        let detailWidth = min(
            ceil(measuredDetailWidth),
            max(0, bounds.width - minimumTitleWidth - gap)
        )
        let titleWidth = max(0, bounds.width - detailWidth - gap)
        titleLabel.frame = NSRect(x: 0, y: 22, width: titleWidth, height: 17)
        detailLabel.frame = NSRect(
            x: titleWidth + gap,
            y: 22,
            width: detailWidth,
            height: 16
        )
        track.frame = NSRect(x: 0, y: 6, width: bounds.width, height: 8)
        fill.frame = NSRect(x: 0, y: 0, width: track.bounds.width * progress, height: track.bounds.height)
    }
}

@MainActor
private final class HintActionView: NSView {
    private let titleLabel: NSTextField
    private let hintLabel: NSTextField
    private let action: @MainActor () -> Void
    private var tracking: NSTrackingArea?

    init(title: String, hint: String, action: @escaping @MainActor () -> Void) {
        titleLabel = NSTextField(labelWithString: title)
        hintLabel = NSTextField(labelWithString: hint)
        self.action = action
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: 34))

        wantsLayer = true
        layer?.cornerRadius = 6

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = Palette.primary

        hintLabel.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        hintLabel.textColor = Palette.secondary
        hintLabel.alignment = .center
        hintLabel.drawsBackground = true
        hintLabel.backgroundColor = Palette.track
        hintLabel.wantsLayer = true
        hintLabel.layer?.cornerRadius = 9
        hintLabel.layer?.masksToBounds = true

        addSubview(titleLabel)
        addSubview(hintLabel)
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(performAction)))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        titleLabel.frame = NSRect(x: 16, y: 8, width: 150, height: 18)
        hintLabel.frame = NSRect(x: bounds.width - 120, y: 8, width: 104, height: 18)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking {
            removeTrackingArea(tracking)
        }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self
        )
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = Palette.primary.withAlphaComponent(0.08).cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @objc private func performAction() {
        action()
    }
}

@MainActor
private final class ProcessHeaderView: NSView {
    private let cpuLabel = NSTextField(labelWithString: "CPU")
    private let memoryLabel = NSTextField(labelWithString: "MEMORY")
    private let processLabel = NSTextField(labelWithString: "TOP PROCESSES")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: 28))

        cpuLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        memoryLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold)
        processLabel.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        cpuLabel.textColor = Palette.secondary
        memoryLabel.textColor = Palette.secondary
        processLabel.textColor = Palette.secondary
        cpuLabel.alignment = .right
        memoryLabel.alignment = .right

        addSubview(cpuLabel)
        addSubview(memoryLabel)
        addSubview(processLabel)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override func layout() {
        super.layout()
        cpuLabel.frame = NSRect(x: 16, y: 6, width: 36, height: 14)
        memoryLabel.frame = NSRect(x: 60, y: 6, width: 52, height: 14)
        processLabel.frame = NSRect(
            x: 124,
            y: 6,
            width: bounds.width - 140,
            height: 14
        )
    }
}

@MainActor
enum Palette {
    static let primary = NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1)
    static let secondary = NSColor(srgbRed: 0.61, green: 0.63, blue: 0.68, alpha: 1)
    static let track = NSColor.white.withAlphaComponent(0.10)
    static let blue = NSColor(srgbRed: 0.16, green: 0.53, blue: 1.00, alpha: 1)
    static let amber = NSColor(srgbRed: 1.00, green: 0.67, blue: 0.08, alpha: 1)
    static let mint = NSColor(srgbRed: 0.20, green: 0.82, blue: 0.62, alpha: 1)
    static let coral = NSColor(srgbRed: 1.00, green: 0.35, blue: 0.38, alpha: 1)

    static func usage(_ fraction: Double) -> NSColor {
        if fraction >= 0.90 { return coral }
        if fraction >= 0.70 { return amber }
        return blue
    }

    static func pressure(_ pressure: Pressure) -> NSColor {
        switch pressure {
        case .green: mint
        case .yellow: amber
        case .red: coral
        }
    }

    static func processCPU(_ percent: Double) -> NSColor {
        if percent >= 100 { return coral }
        if percent >= 50 { return amber }
        return blue
    }
}

private func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
}

private func fraction(_ numerator: UInt64, of denominator: UInt64) -> Double {
    guard denominator > 0 else { return 0 }
    return clamped(Double(numerator) / Double(denominator))
}

private func compactBytes(_ bytes: UInt64) -> String {
    let gib = Double(bytes) / 1_073_741_824.0
    if gib >= 10 { return String(format: "%.1fG", gib) }
    if gib >= 1 { return String(format: "%.2fG", gib) }
    return String(format: "%.0fM", Double(bytes) / 1_048_576.0)
}
