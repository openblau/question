import AppKit
import ServiceManagement

@main
@MainActor
enum QuestionApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var panel: PanelController!
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem!
    private var setKeyItem: NSMenuItem!
    private var forgetKeyItem: NSMenuItem!
    private var loginItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = PanelController()
        hotKey = HotKey { [weak self] in self?.panel.toggle() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "questionmark.bubble", accessibilityDescription: "Question")

        let menu = NSMenu()
        let open = NSMenuItem(title: hotKey == nil ? "Open (⌥Space unavailable)" : "Open  ⌥Space",
                              action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(open)
        menu.addItem(.separator())
        setKeyItem = NSMenuItem(title: "Set API Key…", action: #selector(setKey), keyEquivalent: "")
        forgetKeyItem = NSMenuItem(title: "Forget API Key", action: #selector(forgetKey), keyEquivalent: "")
        menu.addItem(setKeyItem)
        menu.addItem(forgetKeyItem)
        menu.addItem(.separator())
        loginItem = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Question", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        enableLoginItemOnFirstLaunch()
        if panel.session.needsKey { setKey() }
    }

    // MARK: Login item

    private static let loginConfiguredKey = "loginItemConfigured"

    /// Turns "Open at Login" on once; after that it's the user's toggle.
    private func enableLoginItemOnFirstLaunch() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.loginConfiguredKey) else { return }
        defaults.set(true, forKey: Self.loginConfiguredKey)
        try? SMAppService.mainApp.register()
    }

    @objc private func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let hasKey = !panel.session.needsKey
        setKeyItem.title = hasKey ? "Change API Key…" : "Set API Key…"
        forgetKeyItem.isEnabled = hasKey
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on; loginItem.title = "Open at Login"
        case .requiresApproval: loginItem.state = .off; loginItem.title = "Open at Login (approve in System Settings)"
        default: loginItem.state = .off; loginItem.title = "Open at Login"
        }
    }

    @objc private func openPanel() { panel.show() }

    @objc private func setKey() {
        let alert = NSAlert()
        alert.messageText = panel.session.needsKey ? "Set Anthropic API Key" : "Change Anthropic API Key"
        alert.informativeText = "Create a key at console.anthropic.com → Settings → API Keys. It's stored in your macOS Keychain."
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-ant-…"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            try panel.session.saveKey(key)
            panel.show()
        } catch {
            let failure = NSAlert(error: error)
            failure.runModal()
        }
    }

    @objc private func forgetKey() { panel.session.forgetKey() }
    @objc private func quit() { NSApp.terminate(nil) }
}
