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

    let session = ChatSession()
    private let panel: QueryPanel

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
            onExpandedChange: { [weak self] expanded in self?.resize(expanded: expanded) })
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        panel.contentView = host
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            let height = session.turns.isEmpty ? Self.compactHeight : Self.expandedHeight
            let top = visible.maxY - visible.height * 0.18
            panel.setFrame(NSRect(x: visible.midX - Self.width / 2, y: top - height,
                                  width: Self.width, height: height), display: true)
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
        resize(expanded: false)
    }

    private func resize(expanded: Bool) {
        let height = expanded ? Self.expandedHeight : Self.compactHeight
        var frame = panel.frame
        guard frame.height != height else { return }
        frame.origin.y = frame.maxY - height   // grow downward, keep the input bar in place
        frame.size.height = height
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    // Clicking elsewhere hides the panel but keeps the session (⌥Space brings it back).
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
}
