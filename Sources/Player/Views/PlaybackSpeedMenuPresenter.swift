import AppKit
import Foundation

/// Presents a native macOS NSMenu for playback speed selection.
/// Native NSMenu guarantees zero SwiftUI layout/render invalidations, robust hover tracking,
/// Apple design vibrancy, and instant responsiveness.
@MainActor
public final class PlaybackSpeedMenuPresenter: NSObject {
    public static let shared = PlaybackSpeedMenuPresenter()

    public static let availableRates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    private override init() {
        super.init()
    }

    public func show(from event: NSEvent? = nil, in view: NSView? = nil) {
        let menu = NSMenu(title: "Playback Speed")
        menu.autoenablesItems = false

        let headerItem = NSMenuItem(title: "Playback Speed", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        let currentRate = PlayerController.shared.playbackRate

        for rate in Self.availableRates {
            let title = rate == 1.0 ? "1× (Normal)" : "\(Self.formatRate(rate))×"
            let item = NSMenuItem(title: title, action: #selector(handleSelectRate(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = NSNumber(value: rate)
            item.state = (abs(currentRate - rate) < 0.01) ? .on : .off
            menu.addItem(item)
        }

        if let ev = event, (ev.type == .rightMouseDown || ev.type == .leftMouseDown), let win = NSApp.keyWindow ?? NSApp.windows.first {
            let targetView = view ?? win.contentView ?? NSView()
            NSMenu.popUpContextMenu(menu, with: ev, for: targetView)
        } else if let win = NSApp.keyWindow ?? NSApp.windows.first, let cv = view ?? win.contentView {
            let mousePt = cv.convert(win.mouseLocationOutsideOfEventStream, from: nil)
            // Position above HUD bar
            let pt = NSPoint(x: mousePt.x, y: mousePt.y + 26)
            menu.popUp(positioning: menu.items.first(where: { $0.state == .on }) ?? menu.items.first, at: pt, in: cv)
        }
    }

    @objc private func handleSelectRate(_ sender: NSMenuItem) {
        guard let num = sender.representedObject as? NSNumber else { return }
        let rate = num.floatValue
        PlayerController.shared.playbackRate = rate
        let label = rate == 1.0 ? "1× (Normal)" : "\(Self.formatRate(rate))×"
        PlayerController.shared.showHUD(message: "Playback Speed: \(label)", iconName: "gauge.with.dots.needle.50percent")
    }

    public static func formatRate(_ rate: Float) -> String {
        let rounded = (rate * 100).rounded() / 100
        if rounded.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(rounded))"
        } else {
            return String(format: "%.2g", rounded)
        }
    }
}
