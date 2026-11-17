import AppKit
import SwiftUI

final class QueryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// Owns the floating Spotlight-style panel.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 720
    static let compactHeight: CGFloat = 64
    static let expandedHeight: CGFloat = 560
    static let maxInputLines = 8

    private static let positionKey = "panelTopLeft"

    let session = ChatSession()
    private let panel: QueryPanel
    /// True while we move the panel ourselves, so only the user's drags are remembered.
    private var positioning = false
    /// Height of the input bar, which grows with multi-line text.
    private var inputHeight = PanelController.compactHeight
    /// Where the user last dragged the panel's top-left corner.
    private var savedTopLeft = UserDefaults.standard.string(forKey: PanelController.positionKey).map(NSPointFromString)

    override init() {
        panel = QueryPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.compactHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        super.init()

        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let root = ChatView(
            session: session,
            onEndSession: { [weak self] in self?.endSession() },
            onExpandedChange: { [weak self] _ in self?.resize(animate: true) },
            onInputHeightChange: { [weak self] height in
                self?.inputHeight = max(height, Self.compactHeight)
                self?.resize(animate: false)
            })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let height = targetHeight
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        var topLeft: NSPoint?
        // Reopen where the user left it, as long as the input bar is still on a screen.
        if let savedTopLeft {
            let bar = NSRect(x: savedTopLeft.x, y: savedTopLeft.y - Self.compactHeight,
                             width: Self.width, height: Self.compactHeight)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(bar) }) { topLeft = savedTopLeft }
        }
        if topLeft == nil, let visible = screen?.visibleFrame {
            topLeft = NSPoint(x: visible.midX - Self.width / 2, y: visible.maxY - visible.height * 0.18)
        }
        if let topLeft {
            move(to: NSRect(x: topLeft.x, y: topLeft.y - height, width: Self.width, height: height), animate: false)
        }
        panel.makeKeyAndOrderFront(nil)
        session.focusTick += 1
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Esc: wipe the conversation from memory and close.
    func endSession() {
        session.end()
        hide()
        resize(animate: true)
    }

    /// Just the input bar before the first question, the full panel after.
    private var targetHeight: CGFloat {
        session.turns.isEmpty ? inputHeight : max(Self.expandedHeight, inputHeight + 240)
    }

    private func resize(animate: Bool) {
        let height = targetHeight
        var frame = panel.frame
        guard frame.height != height else { return }
        frame.origin.y = frame.maxY - height   // grow downward, keep the input bar in place
        frame.size.height = height
        move(to: frame, animate: animate && panel.isVisible)
    }

    private func move(to frame: NSRect, animate: Bool) {
        positioning = true
        panel.setFrame(frame, display: true, animate: animate)
        positioning = false
    }

    func windowDidMove(_ notification: Notification) {
        guard !positioning else { return }
        let topLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        savedTopLeft = topLeft
        UserDefaults.standard.set(NSStringFromPoint(topLeft), forKey: Self.positionKey)
    }

    // Clicking elsewhere hides the panel but keeps the session (⌥Space brings it back).
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
