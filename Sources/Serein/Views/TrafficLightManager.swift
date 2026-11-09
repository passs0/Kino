import AppKit

/// Ensures standard macOS window titlebar and traffic light positioning.
/// Allows AppKit to place buttons in their native pixel-perfect positions
/// while supporting seamless titlebar visibility transitions.
public final class TrafficLightManager: @unchecked Sendable {
    public static let shared = TrafficLightManager()

    private var isInstalled = false

    private init() {}

    @MainActor
    public func install() {
        guard !isInstalled else { return }
        isInstalled = true
    }

    @MainActor
    public func repositionTrafficLights(for window: NSWindow) {
        // AppKit naturally handles standard traffic light positions
    }
}
