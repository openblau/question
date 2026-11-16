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
    private var subscriptionItem: NSMenuItem!
    private var apiKeyItem: NSMenuItem!

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
        let header = NSMenuItem(title: "Answer With", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        subscriptionItem = NSMenuItem(title: "Claude Subscription", action: #selector(useSubscription), keyEquivalent: "")
        apiKeyItem = NSMenuItem(title: "Anthropic API Key", action: #selector(useAPIKey), keyEquivalent: "")
        menu.addItem(subscriptionItem)
        menu.addItem(apiKeyItem)
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
        header.target = nil
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        installEditMenu()
        enableLoginItemOnFirstLaunch()
        if panel.session.needsKey { setKey() }
    }

    /// A menu-bar-only app has no menu bar, but ⌘V, ⌘C, ⌘X, ⌘A and ⌘Z are still routed
    /// through the main menu's key equivalents. Without an Edit menu they do nothing.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        let item = NSMenuItem()
        item.submenu = edit
        main.addItem(item)
        NSApp.mainMenu = main
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
        let hasKey = panel.session.apiKey != nil || Keychain.exists
        subscriptionItem.state = panel.session.backend == .subscription ? .on : .off
        apiKeyItem.state = panel.session.backend == .apiKey ? .on : .off
        setKeyItem.title = hasKey ? "Change API Key…" : "Set API Key…"
        forgetKeyItem.isEnabled = hasKey
        switch SMAppService.mainApp.status {
        case .enabled: loginItem.state = .on; loginItem.title = "Open at Login"
        case .requiresApproval: loginItem.state = .off; loginItem.title = "Open at Login (approve in System Settings)"
        default: loginItem.state = .off; loginItem.title = "Open at Login"
        }
    }

    @objc private func openPanel() { panel.show() }

    /// Uses the Claude Code login, so there's nothing to enter here.
    @objc private func useSubscription() {
        guard ClaudeCodeClient.executable != nil else {
            let alert = NSAlert()
            alert.messageText = "Claude Code Not Found"
            alert.informativeText = "Question uses your Claude subscription through Claude Code. "
                + "Install it from claude.com/claude-code, run `claude` in Terminal to log in, then relaunch Question."
            NSApp.activate()
            alert.runModal()
            return
        }
        panel.session.use(.subscription)
    }

    @objc private func useAPIKey() {
        panel.session.use(.apiKey)
        if panel.session.needsKey { setKey() }
    }

    @objc private func setKey() {
        let alert = NSAlert()
        alert.messageText = !Keychain.exists ? "Set Anthropic API Key" : "Change Anthropic API Key"
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
