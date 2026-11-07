import Foundation
import AppKit
import SafariServices

public final class SafariExtensionManager {
    public static let shared = SafariExtensionManager()

    private init() {}

    /// Opens Safari Extensions settings. Attempts Apple SafariServices API first, falling back to direct UI navigation.
    public func openSafariExtensionsPreferences() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: "com.serein.player.safari-extension") { error in
            if error != nil {
                DispatchQueue.main.async {
                    self.openExtensionsPreferencesViaScript()
                }
            }
        }
    }

    /// Direct AppleScript UI launcher to open Safari's Extensions tab immediately.
    public func openExtensionsPreferencesViaScript() {
        let script = """
        tell application "Safari" to activate
        tell application "System Events"
            tell process "Safari"
                if not (exists window "Extensions") then
                    click menu item "Settings…" of menu "Safari" of menu bar 1
                    delay 0.3
                    try
                        tell front window
                            click (first UI element whose name is "Extensions")
                        end tell
                    end try
                else
                    perform action "AXRaise" of window "Extensions"
                end if
            end tell
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var err: NSDictionary?
            appleScript.executeAndReturnError(&err)
        }
    }

    /// Opens Safari's Developer Settings where 'Allow unsigned extensions' is located.
    public func openSafariDeveloperSettings() {
        let script = """
        tell application "Safari" to activate
        tell application "System Events"
            tell process "Safari"
                try
                    click menu item "Developer Settings…" of menu "Develop" of menu bar 1
                on error
                    try
                        click menu item "Allow Unsigned Extensions" of menu "Develop" of menu bar 1
                    on error
                        click menu item "Settings…" of menu "Safari" of menu bar 1
                        delay 0.3
                        try
                            tell front window
                                click (first UI element whose name is "Advanced")
                            end tell
                        end try
                    end try
                end try
            end tell
        end tell
        """
        if let appleScript = NSAppleScript(source: script) {
            var err: NSDictionary?
            appleScript.executeAndReturnError(&err)
        }
    }
}
