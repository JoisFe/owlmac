import Foundation

/// Polls the process list and reports which watched commands are running.
final class ProcessWatcher {
    static let defaultNames = [
        "claude", "codex", "gemini", "aider",
        "npm", "pnpm", "yarn", "bun", "deno",
        "cargo", "gradle", "xcodebuild",
    ]

    /// Scripts run through these show up as `node /path/to/npm ...`, so argv[1] is checked too.
    private static let interpreters: Set<String> = ["node", "bun", "deno", "python", "python3", "ruby"]

    var names: [String] = defaultNames
    var onChange: (() -> Void)?
    private(set) var found: [String] = []
    private var timer: Timer?

    func start(interval: TimeInterval = 10) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.scan() }
        scan()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if !found.isEmpty {
            found = []
            onChange?()
        }
    }

    func scan() {
        let wanted = Set(names)
        DispatchQueue.global(qos: .utility).async {
            let hits = Self.running(matching: wanted)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.timer != nil, hits != self.found else { return }
                self.found = hits
                self.onChange?()
            }
        }
    }

    private static func running(matching wanted: Set<String>) -> [String] {
        guard !wanted.isEmpty else { return [] }
        let output = runCommand("/bin/ps", ["-axwwo", "args="])
        var hits = Set<String>()
        for line in output.split(separator: "\n") {
            // MCP servers (`npm exec some-mcp`, ...) idle in the background for as long as an AI
            // tool is open. They aren't work, and counting them would keep the Mac up forever.
            if line.range(of: "mcp", options: .caseInsensitive) != nil { continue }
            let argv = line.split(separator: " ", maxSplits: 2).map { basename($0) }
            guard let first = argv.first else { continue }
            if wanted.contains(first) {
                hits.insert(first)
            } else if argv.count > 1, interpreters.contains(first), wanted.contains(argv[1]) {
                hits.insert(argv[1])
            }
        }
        return hits.sorted()
    }

    private static func basename(_ arg: Substring) -> String {
        String(arg.split(separator: "/").last ?? arg)
    }
}
