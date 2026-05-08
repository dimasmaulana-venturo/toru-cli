import Foundation

final class TabCompleter {
    private var pathCommands: [String] = []
    private var pathScanned = false
    private let scanQueue = DispatchQueue(label: "toru-cli.path-scan", qos: .utility)

    func warmUp() {
        scanQueue.async { [weak self] in
            self?.scanPath()
        }
    }

    /// Returns matches for the given token (last word of input).
    func complete(token: String, cwd: String) -> [String] {
        if !pathScanned { scanPath() }
        var results = Set<String>()

        for cmd in pathCommands where cmd.hasPrefix(token) {
            results.insert(cmd)
        }
        let fm = FileManager.default
        if let items = try? fm.contentsOfDirectory(atPath: cwd) {
            for item in items where item.hasPrefix(token) {
                results.insert(item)
            }
        }
        return results.sorted()
    }

    private func scanPath() {
        let env = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let dirs = env.split(separator: ":").map(String.init)
        var set = Set<String>()
        let fm = FileManager.default
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for item in items {
                let full = (dir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir),
                   !isDir.boolValue,
                   fm.isExecutableFile(atPath: full) {
                    set.insert(item)
                }
            }
        }
        pathCommands = Array(set).sorted()
        pathScanned = true
    }
}
