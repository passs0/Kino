import Foundation
import IOKit.pwr_mgt

/// Prevents display sleep and system idle sleep while video media is actively playing.
@MainActor
public final class SleepPreventionManager {
    public static let shared = SleepPreventionManager()

    private var assertionID: IOPMAssertionID = 0
    private var activityToken: NSObjectProtocol?

    private init() {}

    /// Enables or disables display sleep prevention.
    public func setSleepDisabled(_ disabled: Bool, reason: String = "Kino Video Playback") {
        if disabled {
            if assertionID == 0 {
                let success = IOPMAssertionCreateWithName(
                    kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                    reason as CFString,
                    &assertionID
                )
                if success != kIOReturnSuccess {
                    assertionID = 0
                }
            }

            if activityToken == nil {
                activityToken = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated],
                    reason: reason
                )
            }
        } else {
            if assertionID != 0 {
                IOPMAssertionRelease(assertionID)
                assertionID = 0
            }

            if let token = activityToken {
                ProcessInfo.processInfo.endActivity(token)
                activityToken = nil
            }
        }
    }

    deinit {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
        }
    }
}
