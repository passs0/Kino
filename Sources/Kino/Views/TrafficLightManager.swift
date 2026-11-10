import AppKit

/// Standard macOS window buttons (traffic lights) manager.
/// Following QuickTime Player and native Apple media players, we preserve AppKit's
/// native titlebar geometry without private view layout swizzling, ensuring 100%
/// reliable full-screen transitions and perfect titlebar alignment.
public final class TrafficLightManager: @unchecked Sendable {
    public static let shared = TrafficLightManager()

    private init() {}

    @MainActor
    public func install() {
        // AppKit manages titlebar layout natively.
    }

    @MainActor
    public func repositionTrafficLights(for window: NSWindow) {
        // Native AppKit positioning.
    }
}
