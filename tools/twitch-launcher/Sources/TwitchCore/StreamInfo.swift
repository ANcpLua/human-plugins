import Foundation

public struct StreamInfo: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let displayName: String
    public let isOnline: Bool
    public let viewerCount: Int
    public let gameName: String
    public let title: String

    public init(
        name: String,
        displayName: String? = nil,
        isOnline: Bool = false,
        viewerCount: Int = 0,
        gameName: String = "",
        title: String = ""
    ) {
        id = name.lowercased()
        self.name = name
        self.displayName = displayName ?? name
        self.isOnline = isOnline
        self.viewerCount = viewerCount
        self.gameName = gameName
        self.title = title
    }

    public var formattedViewers: String {
        switch viewerCount {
        case 1_000_000...:
            return String(format: "%.1fM", Double(viewerCount) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(viewerCount) / 1_000)
        default:
            return String(viewerCount)
        }
    }
}
