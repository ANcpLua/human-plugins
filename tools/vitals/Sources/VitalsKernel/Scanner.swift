import Darwin
import VitalsCore

public enum Scanner {
    public static func scan(root: String, top: Int) -> Result<DiskScan, MetricsError> {
        guard let rootCopy = strdup(root) else {
            return .failure(.syscall(name: "strdup", code: errno))
        }
        var argv: [UnsafeMutablePointer<CChar>?] = [rootCopy, nil]
        let handle = argv.withUnsafeMutableBufferPointer { buffer in
            fts_open(buffer.baseAddress, FTS_PHYSICAL | FTS_XDEV, nil)
        }
        free(rootCopy)
        guard let handle else {
            return .failure(.syscall(name: "fts_open(\(root))", code: errno))
        }
        defer { fts_close(handle) }

        var sizes: [String: UInt64] = [:]
        var directories: Set<String> = []
        var total: UInt64 = 0
        var files: UInt64 = 0
        var unreadable: UInt64 = 0
        var currentChild: String?

        while let pointer = fts_read(handle) {
            let entry = pointer.pointee
            let level = Int(entry.fts_level)
            let info = Int32(entry.fts_info)
            if level == 0 { continue }
            if info == FTS_DP {
                if level == 1 { currentChild = nil }
                continue
            }
            if info == FTS_DNR || info == FTS_ERR || info == FTS_NS {
                unreadable &+= 1
                continue
            }
            let blocks = entry.fts_statp.pointee.st_blocks
            let size = blocks > 0 ? UInt64(blocks) * 512 : 0
            files &+= 1
            total &+= size
            if level == 1 {
                guard let pathPointer = entry.fts_path else {
                    unreadable &+= 1
                    continue
                }
                let raw = UnsafeRawBufferPointer(start: pathPointer, count: Int(entry.fts_pathlen))
                let full = String(decoding: raw, as: UTF8.self)
                let name = full.lastIndex(of: "/").map { String(full[full.index(after: $0)...]) } ?? full
                sizes[name, default: 0] &+= size
                if info == FTS_D {
                    directories.insert(name)
                    currentChild = name
                }
            } else if let child = currentChild {
                sizes[child, default: 0] &+= size
            }
        }

        let ranked = sizes
            .map { DiskEntry(name: $0.key, bytes: $0.value, isDirectory: directories.contains($0.key)) }
            .sorted { $0.bytes > $1.bytes }
        let trimmed = top > 0 ? Array(ranked.prefix(top)) : ranked
        return .success(DiskScan(root: root, totalBytes: total, scannedFiles: files, unreadable: unreadable, entries: trimmed))
    }
}
