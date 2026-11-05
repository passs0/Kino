import SwiftUI
import AppKit

/// Apple's Official macOS 26+ Liquid Glass System Integration
/// Uses native SwiftUI `Glass.regular` and `.glassEffect(Glass.regular, in: shape)`.
/// Seamlessly uses macOS System Settings Appearance Accent Color.

// MARK: - Apple Control Center Style Pill Slider

/// Apple macOS / visionOS Liquid Glass Pill Slider
/// True Apple Liquid Glass implementation matching the official design specification:
/// - Oblong 3D Liquid Glass pill thumb with real-time optical refraction (`Glass.regular`) and specular crescent highlight.
/// - The continuous background rail runs across the slider width.
/// - The active track enters the glass thumb and terminates smoothly at the thumb's center with a rounded capsule cap,
///   allowing the inactive track to pass through the right half of the glass lens.
/// - Fluid spring physics with tactile interaction response on hover and drag.
public struct PillSlider: View {
    @Binding var value: Double // Range 0.0 ... 1.0
    var trackHeight: CGFloat = 4.5
    var idleThumbWidth: CGFloat = 16
    var idleThumbHeight: CGFloat = 11
    var activeThumbWidth: CGFloat = 36
    var activeThumbHeight: CGFloat = 22
    var activeColor: Color = .white
    var onActivity: (() -> Void)?

    @State private var isDragging = false
    @State private var isHovering = false

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 4.5,
        idleThumbWidth: CGFloat = 16,
        idleThumbHeight: CGFloat = 11,
        activeThumbWidth: CGFloat = 36,
        activeThumbHeight: CGFloat = 22,
        activeColor: Color = .white,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.idleThumbWidth = idleThumbWidth
        self.idleThumbHeight = idleThumbHeight
        self.activeThumbWidth = activeThumbWidth
        self.activeThumbHeight = activeThumbHeight
        self.activeColor = activeColor
        self.onActivity = onActivity
    }

    public init(
        value: Binding<Double>,
        trackHeight: CGFloat = 4.5,
        thumbWidth: CGFloat = 36,
        thumbHeight: CGFloat = 22,
        onActivity: (() -> Void)? = nil
    ) {
        self._value = value
        self.trackHeight = trackHeight
        self.idleThumbWidth = 16
        self.idleThumbHeight = 11
        self.activeThumbWidth = thumbWidth
        self.activeThumbHeight = thumbHeight
        self.activeColor = .white
        self.onActivity = onActivity
    }

    private var isInteracting: Bool {
        isDragging || isHovering
    }

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clampedVal = max(0.0, min(1.0, value))

            let currentThumbWidth: CGFloat = isInteracting ? activeThumbWidth : idleThumbWidth
            let thumbCenterX = currentThumbWidth / 2 + clampedVal * (width - currentThumbWidth)

            ZStack(alignment: .leading) {
                // 1. Continuous Inactive Background Rail (full width)
                Capsule()
                    .fill(Color.white.opacity(0.20))
                    .frame(width: width, height: trackHeight)

                // 2. Active Filled Track (extends seamlessly to thumb center)
                Capsule()
                    .fill(activeColor)
                    .frame(width: max(trackHeight, thumbCenterX), height: trackHeight)

                // 3. Apple Liquid Glass Pill Thumb:
                // When idle: completely solid opaque white pill. NOT glass.
                // When interacting (hover/drag): morphs into true optical Liquid Glass material.
                Group {
                    if isInteracting {
                        GlassEffectContainer {
                            ZStack {
                                // Volumetric Glass Lens with Frosted Backdrop Blur & Apple Optical Refraction
                                Capsule()
                                    .fill(Color.white.opacity(0.06))
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .glassEffect(Glass.regular, in: Capsule())

                                // 3D Specular Rim with multi-stop refraction gradient
                                Capsule()
                                    .strokeBorder(
                                        LinearGradient(
                                            stops: [
                                                .init(color: Color.white.opacity(0.80), location: 0.0),
                                                .init(color: Color.white.opacity(0.18), location: 0.35),
                                                .init(color: Color.black.opacity(0.40), location: 0.75),
                                                .init(color: Color.white.opacity(0.20), location: 1.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 0.75
                                    )

                                // Upper Crescent Specular Glint (Light Reflection)
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.35),
                                                Color.white.opacity(0.0)
                                            ],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                                    .frame(width: max(4, activeThumbWidth - 3), height: activeThumbHeight * 0.45)
                                    .offset(y: -activeThumbHeight * 0.22)
                                    .blur(radius: 0.4)
                                    .mask(Capsule().stroke(lineWidth: 1.0))
                            }
                            .frame(width: activeThumbWidth, height: activeThumbHeight)
                            .shadow(color: Color.black.opacity(0.40), radius: 6, x: 0, y: 3)
                        }
                        .transition(.opacity)
                    } else {
                        // Completely solid opaque white capsule pill (Apple HIG Control Center Default). NOT glass.
                        Capsule()
                            .fill(Color.white)
                            .frame(width: idleThumbWidth, height: idleThumbHeight)
                            .shadow(color: Color.black.opacity(0.30), radius: 2.5, x: 0, y: 1)
                            .transition(.opacity)
                    }
                }
                .position(x: thumbCenterX, y: geo.size.height / 2)
                .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isInteracting)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let fraction = max(0.0, min(1.0, gesture.location.x / width))
                        value = fraction
                        onActivity?()
                    }
                    .onEnded { gesture in
                        isDragging = false
                        let fraction = max(0.0, min(1.0, gesture.location.x / width))
                        value = fraction
                        onActivity?()
                    }
            )
            .onHover { h in
                isHovering = h
            }
        }
        .frame(height: max(idleThumbHeight, activeThumbHeight) + 6)
    }
}

// MARK: - Circular Liquid Glass Transport Button

public struct LiquidCircleButton: View {
    var icon: String
    var size: CGFloat
    var iconSize: CGFloat
    var isBold: Bool
    var action: () -> Void

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
        .glassEffect(Glass.regular, in: Circle())
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
            .glassEffect(Glass.regular, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.02 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isHovering)
            .animation(.spring(response: 0.12, dampingFraction: 0.8), value: configuration.isPressed)
            .onHover { h in isHovering = h }
    }
}
