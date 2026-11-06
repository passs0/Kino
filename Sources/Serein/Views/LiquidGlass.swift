import SwiftUI
import AppKit

/// Dynamic system manager for Apple's macOS Liquid Glass Appearance Setting.
/// Observes System Settings > Appearance > Liquid Glass (`NSGlassTintAmount`),
/// allowing all liquid glass materials across the app to adjust in real-time between
/// Clear (maximum transparency & refraction) and Tinted (increased opacity & contrast).
@MainActor
public final class LiquidGlassSettings: ObservableObject {
    public static let shared = LiquidGlassSettings()

    /// System setting value from 0.0 (Clear: maximum transparency & refraction) to 1.0 (Tinted: increased opacity & contrast)
    @Published public private(set) var tintAmount: Double = 0.0
    @Published public private(set) var isReduceTransparencyActive: Bool = false

    private var pollTimer: Timer?

    private init() {
        refresh()

        let distCenter = DistributedNotificationCenter.default()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let notifCenter = NotificationCenter.default

        // Observe system appearance, tint, and color changes
        distCenter.addObserver(forName: NSNotification.Name("AppleColorPreferencesChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        distCenter.addObserver(forName: NSNotification.Name("NSGlassSettingsChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        notifCenter.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        notifCenter.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        workspaceCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }

        // Lightweight periodic polling to guarantee immediate sync if adjusted via System Settings slider
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    public func refresh() {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let rawVal = CFPreferencesCopyAppValue("NSGlassTintAmount" as CFString, kCFPreferencesAnyApplication)
        let newTint: Double
        if let num = rawVal as? NSNumber {
            newTint = max(0.0, min(1.0, num.doubleValue))
        } else if let str = rawVal as? String, let d = Double(str) {
            newTint = max(0.0, min(1.0, d))
        } else {
            newTint = 0.0
        }

        let newReduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

        if abs(newTint - tintAmount) > 0.001 || newReduce != isReduceTransparencyActive {
            self.tintAmount = newTint
            self.isReduceTransparencyActive = newReduce
        }
    }

    /// Dynamic Glass material tuned to the macOS Liquid Glass appearance setting
    public var glass: Glass {
        if isReduceTransparencyActive {
            return Glass.regular.tint(Color.white.opacity(0.35))
        }
        if tintAmount <= 0.02 {
            // Clear end: ultra transparent with maximum optical refraction
            return Glass.clear
        } else {
            // Tinted end: dynamically scales opacity & frost up to system level
            let tintAlpha = 0.08 + (tintAmount * 0.28)
            return Glass.regular.tint(Color.white.opacity(tintAlpha))
        }
    }

    /// Dynamic backdrop fill opacity adjusted by the System Settings slider
    public func backdropOpacity(base: Double = 0.12) -> Double {
        if isReduceTransparencyActive {
            return 0.45
        }
        // At Clear (0.0): uses base opacity
        // At Tinted (1.0): scales up opacity for higher contrast
        return base + (tintAmount * 0.18)
    }
}

// MARK: - Apple Minimalist Thumbless Track Slider

/// Apple-style minimalist thumbless track slider.
/// Features a continuous liquid progress/volume bar with zero thumb clutter.
/// Smoothly expands its track height on hover and interaction for enhanced scrubbing precision.
public struct PillSlider: View {
    @Binding var value: Double // Range 0.0 ... 1.0
    var trackHeight: CGFloat = 5.0
    var interactiveTrackHeight: CGFloat = 7.0
    var onActivity: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.0,
        interactiveTrackHeight: CGFloat = 7.0,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.interactiveTrackHeight = interactiveTrackHeight
        self.onActivity = onActivity
    }

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.0,
        idleThumbWidth: CGFloat = 0,
        idleThumbHeight: CGFloat = 0,
        activeThumbWidth: CGFloat = 0,
        activeThumbHeight: CGFloat = 0,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.interactiveTrackHeight = max(trackHeight + 2.0, 7.0)
        self.onActivity = onActivity
    }

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 5.0,
        thumbWidth: CGFloat = 0,
        thumbHeight: CGFloat = 0,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.interactiveTrackHeight = max(trackHeight + 2.0, 7.0)
        self.onActivity = onActivity
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clampedVal = max(0.0, min(1.0, value))
            let isInteracting = isDragging || isHovering
            let currentHeight = isInteracting ? interactiveTrackHeight : trackHeight
            let activeWidth = width * clampedVal

            ZStack(alignment: .leading) {
                // 1. Continuous Inactive Background Rail (full width)
                Capsule()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: width, height: currentHeight)

                // 2. Active Filled Track (smooth continuous liquid level)
                if activeWidth > 0 {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(currentHeight, activeWidth), height: currentHeight)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .animation(.spring(response: 0.22, dampingFraction: 0.80), value: isInteracting)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let fraction = width > 0 ? max(0.0, min(1.0, gesture.location.x / width)) : 0.0
                        value = fraction
                        onActivity?()
                    }
                    .onEnded { gesture in
                        isDragging = false
                        let fraction = width > 0 ? max(0.0, min(1.0, gesture.location.x / width)) : 0.0
                        value = fraction
                        onActivity?()
                    }
            )
            .onHover { h in
                isHovering = h
            }
        }
        .frame(height: max(trackHeight, interactiveTrackHeight) + 4)
    }
}

// MARK: - Circular Liquid Glass Transport Button

public struct LiquidCircleButton: View {
    var icon: String
    var size: CGFloat
    var iconSize: CGFloat
    var isBold: Bool
    var action: () -> Void

    @ObservedObject private var settings = LiquidGlassSettings.shared
    @State private var isHovering = false

    public init(
        icon: String,
        size: CGFloat = 56,
        iconSize: CGFloat = 22,
        isBold: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.size = size
        self.iconSize = iconSize
        self.isBold = isBold
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: isBold ? .bold : .semibold))
                .foregroundColor(.white)
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(settings.glass, in: Circle())
        .scaleEffect(isHovering ? 1.06 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.72), value: isHovering)
        .onHover { h in isHovering = h }
    }
}

// MARK: - Glass Helpers

/// 1px Vertical Glass Separator
public struct GlassDivider: View {
    var height: CGFloat = 16

    public init(height: CGFloat = 16) {
        self.height = height
    }

    public var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.18))
            .frame(width: 1, height: height)
    }
}

/// Liquid Glass Capsule Button Style for Dialogs and Actions
public struct LiquidCapsuleButtonStyle: ButtonStyle {
    var isProminent: Bool = false
    @ObservedObject private var settings = LiquidGlassSettings.shared
    @State private var isHovering = false

    public init(isProminent: Bool = false) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(isProminent ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isProminent ? Color.accentColor : Color.clear)
            )
            .glassEffect(settings.glass, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovering)
            .animation(.spring(response: 0.12, dampingFraction: 0.8), value: configuration.isPressed)
            .onHover { h in isHovering = h }
    }
}
