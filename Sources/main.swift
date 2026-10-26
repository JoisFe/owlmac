import AppKit

// `OwlMac --render-iconset <dir>` draws the app icon PNGs (used by scripts/build.sh).
let args = CommandLine.arguments
if let flag = args.firstIndex(of: "--render-iconset"), flag + 1 < args.count {
    do {
        try OwlIcon.writeIconset(to: URL(fileURLWithPath: args[flag + 1]))
        exit(0)
    } catch {
        FileHandle.standardError.write("iconset render failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
