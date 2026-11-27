import Foundation
import Combine

/// Dedicated high-frequency time observable state.
/// Decoupling currentTime and loadedDuration from PlayerController prevents
/// the entire UI tree (controls, menus, buttons) from re-evaluating every 100ms during playback.
@MainActor
public final class PlayerTimeState: ObservableObject {
    public static let shared = PlayerTimeState()

    @Published public var currentTime: Double = 0
    @Published public var duration: Double = 0
    @Published public var loadedDuration: Double = 0

    private init() {}

    public func reset() {
        currentTime = 0
        duration = 0
        loadedDuration = 0
    }
}
