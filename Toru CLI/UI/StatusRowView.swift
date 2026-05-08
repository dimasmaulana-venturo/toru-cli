import SwiftUI
import AppKit
import Darwin

/// Slim chip strip rendered above the input bar:
///   [runtime version]  [path]  [git branch]
///
/// - **Runtime**: detected from project marker files in cwd (package.json
///   → node, Cargo.toml → rust, go.mod → go, mix.exs → elixir,
///   composer.json → php, requirements.txt / pyproject.toml → python,
///   Gemfile → ruby). Falls back to `node --version` when nothing matches.
/// - **Path**: full pretty path from $HOME → `~/...`.
/// - **Git branch**: shown when cwd is inside a git repo, else hidden.
///
/// Polls cwd of the shell PID every 0.6s via `proc_pidinfo`.
struct StatusRowView: View {
    @ObservedObject var tab: TabState
    @StateObject private var probe = StatusProbe()

    var body: some View {
        HStack(spacing: 10) {
            chip(probe.runtimeLabel, color: Color.teal)
            chip(prettyPath(probe.cwd), color: Color(nsColor: .labelColor).opacity(0.85))
            if !probe.branch.isEmpty {
                chip("git:(\(probe.branch)\(probe.dirty ? " ●" : ""))",
                     color: Color.purple.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .frame(height: 24)
        .background(Color.white.opacity(0.02))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
        .onAppear { probe.attach(tab: tab) }
        .onDisappear { probe.detach() }
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func prettyPath(_ path: String) -> String {
        guard !path.isEmpty else { return "~" }
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }
}

/// Polls `tcgetpgrp + proc_pidinfo` for the live cwd of the foreground
/// process group, then async-detects runtime / git branch from that path.
@MainActor
final class StatusProbe: ObservableObject {
    @Published var cwd: String = NSHomeDirectory()
    @Published var runtimeLabel: String = "node"
    @Published var branch: String = ""
    @Published var dirty: Bool = false

    private weak var tab: TabState?
    private var timer: Timer?
    private var lastCwd: String = ""
    private var inflight: Task<Void, Never>?

    func attach(tab: TabState) {
        self.tab = tab
        startTimer()
        tick()
    }

    func detach() {
        timer?.invalidate()
        timer = nil
        inflight?.cancel()
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.6, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let tab else { return }
        let proc = tab.host.terminal.process
        guard let proc, proc.shellPid > 0 else { return }

        // Foreground pgrp on the master pty. If shell is at prompt,
        // tcgetpgrp == shellPid → use shellPid for cwd lookup.
        let fg = tcgetpgrp(proc.childfd)
        let pid = (fg > 0) ? fg : proc.shellPid

        guard let path = Self.processCwd(pid: pid) else { return }
        if path == lastCwd { return }
        lastCwd = path
        cwd = path
        triggerDetect(path: path)
    }

    private func triggerDetect(path: String) {
        inflight?.cancel()
        inflight = Task { [weak self] in
            let label = await Self.detectRuntime(cwd: path)
            let (br, drty) = await Self.detectGit(cwd: path)
            if Task.isCancelled { return }
            await MainActor.run {
                self?.runtimeLabel = label
                self?.branch = br
                self?.dirty = drty
            }
        }
    }

    // MARK: - libproc cwd

    private static func processCwd(pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.stride
        let bytes = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(size))
        guard bytes == Int32(size) else { return nil }
        let pathTuple = info.pvi_cdir.vip_path
        return withUnsafeBytes(of: pathTuple) { raw -> String? in
            guard let base = raw.baseAddress else { return nil }
            let cstr = base.assumingMemoryBound(to: CChar.self)
            let s = String(cString: cstr)
            return s.isEmpty ? nil : s
        }
    }

    // MARK: - Runtime / git probes (zsh -lc)

    private static func detectRuntime(cwd: String) async -> String {
        let fm = FileManager.default
        let exists: (String) -> Bool = { fm.fileExists(atPath: "\(cwd)/\($0)") }
        if exists("package.json") || exists("node_modules") {
            if let v = await run("node --version", cwd: cwd) { return formatNode(v) }
        } else if exists("go.mod") {
            if let v = await run("go version", cwd: cwd) { return formatGo(v) }
        } else if exists("Cargo.toml") {
            if let v = await run("rustc --version", cwd: cwd) { return formatRust(v) }
        } else if exists("requirements.txt") || exists("pyproject.toml") {
            if let v = await run("python3 --version", cwd: cwd) { return formatPython(v) }
        } else if exists("Gemfile") {
            if let v = await run("ruby --version", cwd: cwd) { return formatRuby(v) }
        } else if exists("composer.json") {
            if let v = await run("php --version", cwd: cwd) { return formatPHP(v) }
        } else if exists("mix.exs") {
            if let v = await run("elixir --version", cwd: cwd) { return formatElixir(v) }
        }
        if let v = await run("node --version", cwd: cwd) { return formatNode(v) }
        return "node"
    }

    private static func detectGit(cwd: String) async -> (String, Bool) {
        let branch = (await run("git branch --show-current", cwd: cwd)) ?? ""
        let porcelain = (await run("git status --porcelain", cwd: cwd)) ?? ""
        return (branch, !porcelain.isEmpty)
    }

    private static func run(_ command: String, cwd: String) async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-lc", command]
            proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
            let outPipe = Pipe(); let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            do { try proc.run() } catch { return nil }
            proc.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            guard let s = String(data: data, encoding: .utf8) else { return nil }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.value
    }

    // MARK: - Format

    private static func formatNode(_ s: String) -> String {
        let v = s.hasPrefix("v") ? String(s.dropFirst()) : s
        return "node \(v)"
    }
    private static func formatGo(_ s: String) -> String {
        let parts = s.split(separator: " ")
        guard parts.count >= 3 else { return "go" }
        let v = parts[2].hasPrefix("go") ? String(parts[2].dropFirst(2)) : String(parts[2])
        return "go \(v)"
    }
    private static func formatRust(_ s: String) -> String {
        let parts = s.split(separator: " ")
        guard parts.count >= 2 else { return "rust" }
        return "rust \(parts[1])"
    }
    private static func formatPython(_ s: String) -> String {
        let parts = s.split(separator: " ")
        guard parts.count >= 2 else { return "py" }
        return "py \(parts[1])"
    }
    private static func formatRuby(_ s: String) -> String {
        let parts = s.split(separator: " ")
        guard parts.count >= 2 else { return "ruby" }
        return "ruby \(parts[1])"
    }
    private static func formatPHP(_ s: String) -> String {
        let firstLine = s.split(separator: "\n").first.map(String.init) ?? s
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return "php" }
        return "php \(parts[1])"
    }
    private static func formatElixir(_ s: String) -> String {
        // "Erlang/OTP 26 ... \nElixir 1.16.0 (...)"
        for line in s.split(separator: "\n") {
            if line.hasPrefix("Elixir") {
                let parts = line.split(separator: " ")
                if parts.count >= 2 { return "elixir \(parts[1])" }
            }
        }
        return "elixir"
    }
}
