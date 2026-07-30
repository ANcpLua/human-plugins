public struct DiskEntry: Sendable, Equatable, Codable {
    public let name: String
    public let bytes: UInt64
    public let isDirectory: Bool

    public init(name: String, bytes: UInt64, isDirectory: Bool) {
        self.name = name
        self.bytes = bytes
        self.isDirectory = isDirectory
    }
}

public struct DiskScan: Sendable, Equatable, Codable {
    public let root: String
    public let totalBytes: UInt64
    public let scannedFiles: UInt64
    public let unreadable: UInt64
    public let entries: [DiskEntry]

    public init(root: String, totalBytes: UInt64, scannedFiles: UInt64, unreadable: UInt64, entries: [DiskEntry]) {
        self.root = root
        self.totalBytes = totalBytes
        self.scannedFiles = scannedFiles
        self.unreadable = unreadable
        self.entries = entries
    }
}
