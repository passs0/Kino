import SwiftUI
import AppKit
import AVKit
import AVFoundation

/// Custom AppKit view combining AVPlayerLayer with macOS drag-and-drop support and native PiP.
public final class SereinPlayerNSView: NSView, AVPictureInPictureControllerDelegate {
    public let playerLayer = AVPlayerLayer()
    public var pipController: AVPictureInPictureController?
    public var onFileDropped: ((URL) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        playerLayer.videoGravity = PlayerController.shared.isLetterboxed ? .resizeAspect : .resizeAspectFill
        layer?.addSublayer(playerLayer)

        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.delegate = self
        }

        registerForDraggedTypes([.fileURL, .URL])
        PlayerController.shared.activePlayerNSView = self
    }

    public override func layout() {
        super.layout()
        playerLayer.frame = bounds
        repositionTrafficLights()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let win = window else { return }
        win.isOpaque = true
        win.backgroundColor = .windowBackgroundColor
        win.hasShadow = true
        win.isMovableByWindowBackground = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        repositionTrafficLights()
        PlayerController.shared.activePlayerNSView = self
    }

    @discardableResult
    public func ensurePiPController() -> AVPictureInPictureController? {
        if pipController == nil && AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.delegate = self
        }
        return pipController
    }

    /// Toggles Picture-in-Picture safely.
    public func togglePiP() {
        guard let pip = ensurePiPController() else {
            print("[PiP] Picture-in-Picture is not supported on this platform.")
            return
        }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    public func repositionTrafficLights() {
        guard let win = window else { return }
        let xOffset: CGFloat = 18
        let yOffset: CGFloat = 16
        let spacing: CGFloat = 8

        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        var currentX = xOffset
        for type in buttonTypes {
            if let btn = win.standardWindowButton(type), let superview = btn.superview {
                btn.translatesAutoresizingMaskIntoConstraints = true
                let btnY = superview.bounds.height - btn.frame.height - yOffset
                btn.setFrameOrigin(NSPoint(x: currentX, y: btnY))
                currentX += btn.frame.width + spacing
            }
        }
    }

    // MARK: - Drag and Drop

    public override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pboard = sender.draggingPasteboard
        if let types = pboard.types, types.contains(.fileURL) || types.contains(.URL) {
            return .copy
        }
        return []
    }

    public override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pboard = sender.draggingPasteboard
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL], let first = urls.first {
            onFileDropped?(first)
            return true
        }
        return false
    }
}

/// SwiftUI wrapper for native AppKit video rendering.
public struct NativePlayerView: NSViewRepresentable {
    public let player: AVPlayer
    public var onFileDropped: ((URL) -> Void)?

    public init(player: AVPlayer, onFileDropped: ((URL) -> Void)? = nil) {
        self.player = player
        self.onFileDropped = onFileDropped
    }

    public func makeNSView(context: Context) -> SereinPlayerNSView {
        let view = SereinPlayerNSView()
        view.playerLayer.player = player
        view.onFileDropped = onFileDropped
        PlayerController.shared.activePlayerNSView = view
        return view
    }

    public func updateNSView(_ nsView: SereinPlayerNSView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        let targetGravity: AVLayerVideoGravity = PlayerController.shared.isLetterboxed ? .resizeAspect : .resizeAspectFill
        if nsView.playerLayer.videoGravity != targetGravity {
            nsView.playerLayer.videoGravity = targetGravity
        }
        nsView.onFileDropped = onFileDropped
        PlayerController.shared.activePlayerNSView = nsView
    }
}

/// Native macOS AirPlay Route Picker wrapped for SwiftUI.
public struct AirPlayRoutePicker: NSViewRepresentable {
    public let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }

    public func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.player = player
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(.white, for: .normal)
        picker.setRoutePickerButtonColor(NSColor.controlAccentColor, for: .activeHighlighted)
        return picker
    }

    public func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
