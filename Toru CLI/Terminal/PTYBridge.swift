import Foundation

enum PTYBridge {
    /// Determines the shell to launch. Honors `$SHELL`, falls back to `/bin/zsh`.
    static func resolveShell() -> String {
        if let env = ProcessInfo.processInfo.environment["SHELL"], !env.isEmpty,
           FileManager.default.isExecutableFile(atPath: env) {
            return env
        }
        return "/bin/zsh"
    }

    static func resolveHomeDirectory() -> String {
        NSHomeDirectory()
    }

    /// Build a typical login-shell environment.
    static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        return env
    }

    static func envArray() -> [String] {
        buildEnvironment().map { "\($0.key)=\($0.value)" }
    }
}
