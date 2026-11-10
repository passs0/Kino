import SwiftUI
import AppKit
import AVKit
import AVFoundation

/// Click-through NSHostingView so Picture-in-Picture native controls and window dragging remain fully interactive.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

/// Subtitle overlay rendered directly inside the floating macOS Picture-in-Picture window.
private struct PiPSubtitleOverlayView: View {
    @ObservedObject private var subtitleManager = SubtitleManager.shared
    @ObservedObject private var captionAppearance = CaptionAppearanceManager.shared

    var body: some View {
        GeometryReader { geo in
            if let cueText = subtitleManager.currentCueText, !cueText.isEmpty {
                let h = geo.size.height > 0 ? geo.size.height : 240
                let dynamicBaseSize = max(10.0, min(h * 0.056, 24.0))
                let effectiveFontSize = dynamicBaseSize * captionAppearance.fontScale
                let padH = max(6.0, dynamicBaseSize * 0.45)
                let padV = max(3.0, dynamicBaseSize * 0.22)
                let edgeMargin = max(8.0, h * 0.06)

                VStack {
                    if subtitleManager.currentCuePosition != .top {
                        Spacer()
                    }

                    Text(cueText)
                        .font(.system(size: effectiveFontSize, weight: .medium, design: .default))
                        .foregroundColor(captionAppearance.textColor)
                        .shadow(
                            color: captionAppearance.hasShadow ? captionAppearance.shadowColor : Color.clear,
                            radius: captionAppearance.hasShadow ? 1.5 : 0,
                            x: 0,
                            y: 1.0
                        )
                        .multilineTextAlignment(.center)
                        .lineSpacing(max(1.5, dynamicBaseSize * 0.14))
                        .padding(.horizontal, padH)
                        .padding(.vertical, padV)
                        .background(
                            RoundedRectangle(cornerRadius: max(4, captionAppearance.cornerRadius * 0.7), style: .continuous)
                                .fill(captionAppearance.backgroundColor)
                        )
                        .padding(.horizontal, 12)
                        .padding(.top, subtitleManager.currentCuePosition == .top ? edgeMargin : 0)
                        .padding(.bottom, subtitleManager.currentCuePosition == .bottom ? edgeMargin : 0)

                    if subtitleManager.currentCuePosition != .bottom {
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Custom AppKit view combining AVPlayerLayer with macOS drag-and-drop support and native PiP.
public final class KinoPlayerNSView: NSView, AVPictureInPictureControllerDelegate {
    public let playerLayer = AVPlayerLayer()
    public var pipController: AVPictureInPictureController?
    public var onFileDropped: ((URL) -> Void)?
    private var pipSubtitleHostingView: NSView?

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
        layer?.cornerRadius = 26
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        playerLayer.cornerRadius = 26
        playerLayer.cornerCurve = .continuous
        playerLayer.masksToBounds = true
        playerLayer.videoGravity = PlayerController.shared.isLetterboxed ? .resizeAspect : .resizeAspectFill
        layer?.addSublayer(playerLayer)

        if AVPictureInPictureController.isPictureInPictureSupported() {
            pipController = AVPictureInPictureController(playerLayer: playerLayer)
            pipController?.delegate = self
        }

        registerForDraggedTypes([.fileURL, .URL])
        PlayerController.shared.activePlayerNSView = self
        VideoEnhancer.shared.register(playerLayer: playerLayer)
    }

    public override func layout() {
        super.layout()
        playerLayer.frame = bounds
        updateCornerRadius()
    }

    public func updateCornerRadius() {
        guard !WindowManager.shared.isTransitioningFullScreen else { return }
        let isFS = window?.styleMask.contains(.fullScreen) ?? false
        let radius: CGFloat = isFS ? 0 : 26
        playerLayer.cornerRadius = radius
        layer?.cornerRadius = radius
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let win = window else {
            NotificationCenter.default.removeObserver(self)
            if PlayerController.shared.activePlayerNSView === self {
                PlayerController.shared.activePlayerNSView = nil
            }
            return
        }
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = true
        win.isMovableByWindowBackground = false
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .visible
        PlayerController.shared.activePlayerNSView = self
        updateCornerRadius()

        NotificationCenter.default.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFullScreenChange), name: NSWindow.didEnterFullScreenNotification, object: win)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFullScreenChange), name: NSWindow.didExitFullScreenNotification, object: win)
    }

    @objc private func handleFullScreenChange() {
        updateCornerRadius()
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

    // MARK: - AVPictureInPictureControllerDelegate (PiP Subtitle Injection)

    public func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            PlayerController.shared.isPictureInPictureActive = true
            self?.attachPiPSubtitleOverlay(to: pictureInPictureController)
        }
    }

    public func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            PlayerController.shared.isPictureInPictureActive = true
            self?.attachPiPSubtitleOverlay(to: pictureInPictureController)
        }
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            PlayerController.shared.isPictureInPictureActive = false
            self?.detachPiPSubtitleOverlay()
        }
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        Task { @MainActor [weak self] in
            PlayerController.shared.isPictureInPictureActive = false
            self?.detachPiPSubtitleOverlay()
        }
    }

    @MainActor
    private func attachPiPSubtitleOverlay(to controller: AVPictureInPictureController) {
        guard let pipVC = controller.value(forKey: "pictureInPictureViewController") as? NSViewController else {
            return
        }
        let containerView = pipVC.view
        if let existing = pipSubtitleHostingView, existing.superview === containerView {
            return
        }
        pipSubtitleHostingView?.removeFromSuperview()

        let overlay = PassthroughHostingView(rootView: PiPSubtitleOverlayView())
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.clear.cgColor
        overlay.layer?.zPosition = 999

        containerView.addSubview(overlay, positioned: .above, relativeTo: nil)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        pipSubtitleHostingView = overlay
    }

    @MainActor
    private func detachPiPSubtitleOverlay() {
        pipSubtitleHostingView?.removeFromSuperview()
        pipSubtitleHostingView = nil
    }

    public func repositionTrafficLights() {}

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

    public func makeNSView(context: Context) -> KinoPlayerNSView {
        let view = KinoPlayerNSView()
        view.playerLayer.player = player
        view.onFileDropped = onFileDropped
        PlayerController.shared.activePlayerNSView = view
        return view
    }

    public func updateNSView(_ nsView: KinoPlayerNSView, context: Context) {
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

    public static func dismantleNSView(_ nsView: KinoPlayerNSView, coordinator: ()) {
        if let pip = nsView.pipController, pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        }
        nsView.playerLayer.player = nil
        if PlayerController.shared.activePlayerNSView === nsView {
            PlayerController.shared.activePlayerNSView = nil
        }
    }
}

/// Native macOS AirPlay Route Picker wrapped for SwiftUI supporting both Video and Audio targeting.
public struct AirPlayRoutePicker: NSViewRepresentable {
    public enum Mode {
        case video
        case audio
    }

    public let player: AVPlayer
    public var mode: Mode

    public init(player: AVPlayer, mode: Mode = .video) {
        self.player = player
        self.mode = mode
    }

    public func makeNSView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.player = player
        picker.isRoutePickerButtonBordered = false
        picker.setValue(mode == .video, forKey: "prioritizesVideoDevices")
        picker.appearance = NSAppearance(named: .darkAqua)
        picker.setRoutePickerButtonColor(.white, for: .normal)
        picker.setRoutePickerButtonColor(NSColor.controlAccentColor, for: .activeHighlighted)
        return picker
    }

    public func updateNSView(_ nsView: AVRoutePickerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
        let shouldPrioritize = (mode == .video)
        if (nsView.value(forKey: "prioritizesVideoDevices") as? Bool) != shouldPrioritize {
            nsView.setValue(shouldPrioritize, forKey: "prioritizesVideoDevices")
        }
        nsView.appearance = NSAppearance(named: .darkAqua)
        nsView.setRoutePickerButtonColor(.white, for: .normal)
        nsView.setRoutePickerButtonColor(NSColor.controlAccentColor, for: .activeHighlighted)
    }
}
