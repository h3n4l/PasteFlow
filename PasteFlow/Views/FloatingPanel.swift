import AppKit
import SwiftUI

final class FloatingPanel: NSPanel {
    var onArrowUp: (() -> Void)?
    var onArrowDown: (() -> Void)?
    var onEnter: (() -> Void)?
    var onEsc: (() -> Void)?
    var onCmdNumber: ((Int) -> Void)?
    var onTab: (() -> Void)?
    /// Called when the panel starts to hide, whatever the cause.
    var onHide: (() -> Void)?

    /// Whether the panel is shown or on its way in. False once it starts to fade out.
    var isPresented: Bool { phase == .shown }

    private enum Phase { case hidden, shown, hiding }
    private var phase = Phase.hidden
    /// Goes up with every show and hide, so that a finished animation can tell it was overtaken.
    private var transitionCount = 0
    private var hideCompletions: [() -> Void] = []
    private var localMonitor: Any?

    private static let scaleAnimationKey = "panelScale"

    init<Content: View>(rootView: Content) {
        let frame = NSRect(x: 0, y: 0, width: 560, height: 456)
        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        self.isFloatingPanel = true
        self.level = .floating
        self.titleVisibility = .hidden
        self.titlebarAppearsTransparent = true
        self.titlebarSeparatorStyle = .none
        // The hidden title bar lies over the search row; keep it from dragging the panel.
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.isReleasedWhenClosed = false
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = false
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true

        // The panel's background is a blur material that lets the desktop show through.
        // It fills the window, so the system clips it to the window's own rounded corners.
        let material = NSVisualEffectView(frame: frame)
        material.material = .popover
        material.blendingMode = .behindWindow
        // The panel never makes PasteFlow the active app; without this the material would look inactive.
        material.state = .active

        let hostingView = NSHostingView(rootView: rootView)
        // Lay the content out edge to edge. With the default safe area it would start below
        // the hidden title bar and no longer fit the panel.
        hostingView.safeAreaRegions = []
        hostingView.frame = material.bounds
        hostingView.autoresizingMask = [.width, .height]
        material.addSubview(hostingView)
        // Showing and hiding scale this view's layer.
        material.wantsLayer = true
        self.contentView = material
        // Default to system appearance; updated by updateAppearance()
    }

    func updateAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system:
            self.appearance = nil
        case .light:
            self.appearance = NSAppearance(named: .aqua)
        case .dark:
            self.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func centerOnScreen() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let x = screenFrame.midX - frame.width / 2
        let y = screenFrame.midY - frame.height / 2
        setFrameOrigin(NSPoint(x: x, y: y))
    }
    
    

    func showPanel() {
        guard phase != .shown else { return }
        // A panel that is still fading out goes at once, so that it always opens from the same state.
        if phase == .hiding { finishHiding() }
        phase = .shown
        transitionCount += 1
        let transition = transitionCount
        centerOnScreen()
        installKeyMonitor()
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        animate(PanelMotion.showTransition(reduceMotion: Self.reduceMotion), showing: true) { [weak self] in
            guard let self, self.phase == .shown, self.transitionCount == transition else { return }
            // Normally the fade has just arrived here. This makes sure of it.
            self.alphaValue = 1
            // The shadow may have been drawn for the smaller panel the animation started from.
            self.invalidateShadow()
        }
    }

    /// Fades the panel out, then takes it off screen. `completion` runs once it is off screen,
    /// which is when the app underneath has the keyboard again.
    func hidePanel(completion: (() -> Void)? = nil) {
        if let completion { hideCompletions.append(completion) }
        switch phase {
        case .hidden:
            runHideCompletions()
        case .hiding:
            break
        case .shown:
            phase = .hiding
            transitionCount += 1
            let transition = transitionCount
            onHide?()
            animate(PanelMotion.hideTransition(reduceMotion: Self.reduceMotion), showing: false) { [weak self] in
                guard let self, self.phase == .hiding, self.transitionCount == transition else { return }
                self.finishHiding()
            }
        }
    }

    func toggle() {
        if isPresented { hidePanel() } else { showPanel() }
    }

    override func cancelOperation(_ sender: Any?) { hidePanel() }
    override func resignKey() {
        super.resignKey()
        // Taking the panel off screen also ends up here; only a panel that is still up needs hiding.
        if phase == .shown { hidePanel() }
    }

    // MARK: - Show and Hide Animation

    private static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Fades the window and scales its content about the centre, then calls `completion`.
    private func animate(_ transition: PanelMotion.WindowTransition, showing: Bool, completion: @escaping () -> Void) {
        if let layer = contentView?.layer {
            // If the panel is closed while it is still opening, it shrinks from the size it has reached.
            let reached = layer.presentation()?.transform ?? CATransform3DIdentity
            layer.removeAnimation(forKey: Self.scaleAnimationKey)
            if transition.scale != 1 {
                // The layer itself keeps its full size; only what is on screen is scaled. That way
                // AppKit, which owns the layer's geometry, never sees the change.
                let scaled = NSValue(caTransform3D: Self.scaling(layer, by: transition.scale))
                let scale = CABasicAnimation(keyPath: "transform")
                scale.fromValue = showing ? scaled : NSValue(caTransform3D: reached)
                scale.toValue = showing ? NSValue(caTransform3D: CATransform3DIdentity) : scaled
                scale.duration = transition.duration
                scale.timingFunction = transition.timing
                if !showing {
                    // Stay small until the window is off screen; `finishHiding` removes this.
                    scale.fillMode = .forwards
                    scale.isRemovedOnCompletion = false
                }
                layer.add(scale, forKey: Self.scaleAnimationKey)
            }
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transition.duration
            context.timingFunction = transition.timing
            animator().alphaValue = showing ? 1 : 0
        }
        // Timed separately instead of using the fade's own completion handler: the fade does not
        // advance while the display is off or the screen is locked, and the panel must still end
        // up shown or hidden.
        DispatchQueue.main.asyncAfter(deadline: .now() + transition.duration, execute: completion)
    }

    /// A transform that scales a layer about its centre, wherever its anchor point is.
    private static func scaling(_ layer: CALayer, by scale: CGFloat) -> CATransform3D {
        let size = layer.bounds.size, anchor = layer.anchorPoint
        let shift = CATransform3DMakeTranslation(
            size.width * (0.5 - anchor.x) * (1 - scale), size.height * (0.5 - anchor.y) * (1 - scale), 0)
        return CATransform3DScale(shift, scale, scale, 1)
    }

    private func finishHiding() {
        phase = .hidden
        removeKeyMonitor()
        orderOut(nil)
        contentView?.layer?.removeAnimation(forKey: Self.scaleAnimationKey)
        runHideCompletions()
    }

    private func runHideCompletions() {
        let completions = hideCompletions
        hideCompletions = []
        completions.forEach { $0() }
    }

    // MARK: - Key Event Monitor

    /// Intercepts key events before any view (including TextField) handles them.
    private func installKeyMonitor() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isVisible else { return event }
            // While the panel fades out it still has the keyboard. Drop what is typed then,
            // rather than let it reach the search field of a panel that is on its way out.
            guard self.phase == .shown else { return nil }
            return self.handleKeyEvent(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    /// Returns true if the event was handled (consumed).
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Cmd+1 through Cmd+9
        if event.modifierFlags.contains(.command) {
            if let chars = event.charactersIgnoringModifiers,
               let num = Int(chars), num >= 1, num <= 9 {
                onCmdNumber?(num)
                return true
            }
        }

        switch event.keyCode {
        case 126: // Up arrow
            onArrowUp?()
            return true
        case 125: // Down arrow
            onArrowDown?()
            return true
        case 36: // Return/Enter
            onEnter?()
            return true
        case 48: // Tab
            onTab?()
            return true
        case 53: // Esc
            onEsc?()
            return true
        default:
            return false // Let TextField and other views handle it
        }
    }

    deinit {
        removeKeyMonitor()
    }
}
