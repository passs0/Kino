import SwiftUI
import AppKit
import MediaAccessibility

/// Observes and provides caption style settings from macOS System Settings (Accessibility > Captions).
/// Automatically updates in real time whenever the user modifies caption appearance in macOS System Settings.
@MainActor
public final class CaptionAppearanceManager: ObservableObject {
    public static let shared = CaptionAppearanceManager()

    @Published public private(set) var textColor: Color = .white
    @Published public private(set) var backgroundColor: Color = Color.black.opacity(0.5)
    @Published public private(set) var cornerRadius: CGFloat = 8
    @Published public private(set) var fontScale: CGFloat = 1.0
    @Published public private(set) var hasShadow: Bool = true
    @Published public private(set) var shadowColor: Color = Color.black.opacity(0.85)

    private var observer: NSObjectProtocol?

    private init() {
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(kMACaptionAppearanceSettingsChangedNotification as String),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    public func refresh() {
        let domain: MACaptionAppearanceDomain = .user
        var b1 = MACaptionAppearanceBehavior.useValue
        var b2 = MACaptionAppearanceBehavior.useValue
        var b3 = MACaptionAppearanceBehavior.useValue
        var b4 = MACaptionAppearanceBehavior.useValue
        var b5 = MACaptionAppearanceBehavior.useValue
        var b6 = MACaptionAppearanceBehavior.useValue
        var b7 = MACaptionAppearanceBehavior.useValue
        var b8 = MACaptionAppearanceBehavior.useValue

        // Foreground / Text Color & Opacity
        let fgColorRef = MACaptionAppearanceCopyForegroundColor(domain, &b1).takeRetainedValue()
        let fgOpacity = MACaptionAppearanceGetForegroundOpacity(domain, &b2)
        if let nsFg = NSColor(cgColor: fgColorRef) {
            textColor = Color(nsFg.withAlphaComponent(fgOpacity))
        } else {
            textColor = .white
        }

        // Window / Pill Color & Opacity (macOS System Settings uses Window Color for caption box)
        let winColorRef = MACaptionAppearanceCopyWindowColor(domain, &b3).takeRetainedValue()
        let winOpacity = MACaptionAppearanceGetWindowOpacity(domain, &b4)
        let bgColorRef = MACaptionAppearanceCopyBackgroundColor(domain, &b5).takeRetainedValue()
        let bgOpacity = MACaptionAppearanceGetBackgroundOpacity(domain, &b6)

        if winOpacity > 0, let nsWin = NSColor(cgColor: winColorRef) {
            backgroundColor = Color(nsWin.withAlphaComponent(winOpacity))
        } else if bgOpacity > 0, let nsBg = NSColor(cgColor: bgColorRef) {
            backgroundColor = Color(nsBg.withAlphaComponent(bgOpacity))
        } else {
            backgroundColor = Color.clear
        }

        // Window rounded corner radius
        let radius = MACaptionAppearanceGetWindowRoundedCornerRadius(domain, &b7)
        cornerRadius = radius > 0 ? radius : 8.0

        // Relative font size scale
        let relSize = MACaptionAppearanceGetRelativeCharacterSize(domain, &b8)
        fontScale = relSize > 0 ? relSize : 1.0

        // Edge style
        var bEdge = MACaptionAppearanceBehavior.useValue
        let edgeStyle = MACaptionAppearanceGetTextEdgeStyle(domain, &bEdge)
        hasShadow = (edgeStyle != .none)
    }
}
