import Foundation
import IOKit.pwr_mgt

/// Holds the same power assertions `caffeinate` uses, without spawning it.
///   -i  PreventUserIdleSystemSleep
///   -s  PreventSystemSleep (only honored on AC power)
///   -d  PreventUserIdleDisplaySleep
final class SleepGuard {
    private var assertionIDs: [IOPMAssertionID] = []
    private var current: (reason: String, keepDisplayOn: Bool)?

    var isHolding: Bool { !assertionIDs.isEmpty }

    func hold(reason: String, keepDisplayOn: Bool) {
        if let current, current.reason == reason, current.keepDisplayOn == keepDisplayOn { return }
        release()

        var types = ["PreventUserIdleSystemSleep", "PreventSystemSleep"]
        if keepDisplayOn { types.append("PreventUserIdleDisplaySleep") }

        for type in types {
            var id = IOPMAssertionID(0)
            let result = IOPMAssertionCreateWithName(
                type as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &id
            )
            if result == kIOReturnSuccess { assertionIDs.append(id) }
        }
        current = (reason, keepDisplayOn)
    }

    func release() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
        current = nil
    }
}
