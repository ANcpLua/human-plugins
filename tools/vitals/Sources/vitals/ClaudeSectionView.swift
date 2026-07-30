import AppKit
import VitalsClaude

@MainActor
final class ClaudeSectionView: NSView {
    private let sectionLabel = NSTextField(labelWithString: "CLAUDE")
    private let statusBadge = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let rowViews = [
        MetricBarView(),
        MetricBarView(),
        MetricBarView()
    ]

    init(snapshot: ClaudeTelemetrySnapshot) {
        super.init(frame: NSRect(x: 0, y: 0, width: 352, height: 164))

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

        addSubview(sectionLabel)
        addSubview(statusBadge)
        addSubview(messageLabel)
        for row in rowViews {
            addSubview(row)
        }
        update(snapshot)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update(_ snapshot: ClaudeTelemetrySnapshot) {
        let color: NSColor
        switch snapshot.health.level {
        case .operational:
            color = Palette.mint
        case .degraded:
            color = Palette.amber
        case .outage:
            color = Palette.coral
        case .unavailable:
            color = Palette.secondary
        }

        statusBadge.stringValue = snapshot.health.label
        statusBadge.textColor = color
        statusBadge.backgroundColor = color.withAlphaComponent(0.13)
        statusBadge.toolTip = snapshot.health.detail

        let rows = snapshot.usage.rows
        for (index, view) in rowViews.enumerated() {
            guard rows.indices.contains(index) else {
                view.isHidden = true
                continue
            }
            let row = rows[index]
            view.isHidden = false
            view.update(
                title: row.label,
                detail: row.detail,
                fraction: row.fraction,
                color: Palette.usage(row.fraction)
            )
        }

        messageLabel.stringValue = snapshot.usage.unavailableMessage ?? ""
        messageLabel.isHidden = snapshot.usage.unavailableMessage == nil
    }

    override func layout() {
        super.layout()
        sectionLabel.frame = NSRect(x: 16, y: 141, width: bounds.width - 132, height: 14)
        statusBadge.frame = NSRect(x: bounds.width - 112, y: 137, width: 96, height: 17)
        rowViews[0].frame = NSRect(x: 16, y: 93, width: bounds.width - 32, height: 42)
        rowViews[1].frame = NSRect(x: 16, y: 49, width: bounds.width - 32, height: 42)
        rowViews[2].frame = NSRect(x: 16, y: 5, width: bounds.width - 32, height: 42)
        messageLabel.frame = NSRect(x: 16, y: 64, width: bounds.width - 32, height: 34)
    }
}
