import Foundation

/// `pmset -a disablesleep` — keeps the Mac awake with the lid closed, even on battery.
/// Needs admin rights, so each change asks for the password.
enum LidGuard {
    static var isEnabled: Bool {
        // The SleepDisabled line only appears in `pmset -g` once it has been set.
        for line in runCommand("/usr/bin/pmset", ["-g"]).split(separator: "\n") where line.contains("SleepDisabled") {
            return line.split(whereSeparator: \.isWhitespace).last == "1"
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ on: Bool) -> Bool {
        let prompt = on
            ? "OwlMac이 뚜껑을 닫아도 잠들지 않게 하려고 해요."
            : "OwlMac이 뚜껑 닫힘 잠자기 설정을 원래대로 되돌리려고 해요."
        let source = """
        do shell script "/usr/bin/pmset -a disablesleep \(on ? 1 : 0)" with prompt "\(prompt)" with administrator privileges
        """
        var error: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil
    }
}
