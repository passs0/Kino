import SwiftUI
import AppKit

/// Apple Native AppKit NSSlider wrapped for SwiftUI.
/// Uses macOS system controls with genuine white capsule thumb and trackFillColor.
/// Fully immune to window-background dragging (`mouseDownCanMoveWindow = false`).
public struct NativeSlider: NSViewRepresentable {
    @Binding public var value: Double
    public var range: ClosedRange<Double> = 0.0...1.0
    public var trackFillColor: NSColor = .white
    public var onEditingChanged: ((Bool) -> Void)?

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0.0...1.0,
        trackFillColor: NSColor = .white,
        onEditingChanged: ((Bool) -> Void)? = nil
    ) {
        self._value = value
        self.range = range
        self.trackFillColor = trackFillColor
        self.onEditingChanged = onEditingChanged
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NativeAppKitSlider {
        let slider = NativeAppKitSlider(
            value: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        slider.isContinuous = true
        slider.focusRingType = .none
        slider.controlSize = .small
        slider.onEditingChanged = onEditingChanged
        if #available(macOS 14.0, *) {
            slider.trackFillColor = trackFillColor
        }
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return slider
    }

    public func updateNSView(_ nsView: NativeAppKitSlider, context: Context) {
        context.coordinator.parent = self
        nsView.onEditingChanged = onEditingChanged

        if range.upperBound > range.lowerBound {
            if range.upperBound > nsView.maxValue {
                nsView.maxValue = range.upperBound
                nsView.minValue = range.lowerBound
            } else {
                nsView.minValue = range.lowerBound
                nsView.maxValue = range.upperBound
            }
        }

        if !nsView.isTrackingMouse {
            let clamped = max(nsView.minValue, min(nsView.maxValue, value))
            if abs(nsView.doubleValue - clamped) > 0.005 {
                nsView.doubleValue = clamped
            }
        }

        if #available(macOS 14.0, *) {
            if nsView.trackFillColor != trackFillColor {
                nsView.trackFillColor = trackFillColor
            }
        }
    }

    public final class Coordinator: NSObject {
        var parent: NativeSlider

        init(_ parent: NativeSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: NSSlider) {
            parent.value = sender.doubleValue
        }
    }
}

/// Native AppKit NSSlider subclass configured for responsive media playback control.
public final class NativeAppKitSlider: NSSlider {
    public var onEditingChanged: ((Bool) -> Void)?
    public private(set) var isTrackingMouse = false

    // Prevent macOS window-background dragging from intercepting slider interactions
    public override var mouseDownCanMoveWindow: Bool { false }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    public override func mouseDown(with event: NSEvent) {
        isTrackingMouse = true
        onEditingChanged?(true)
        super.mouseDown(with: event)
        isTrackingMouse = false
        onEditingChanged?(false)
    }
}
