import Cocoa
import WebKit

// MARK: - Config

struct Config {
    let url: URL
    let icon: String
    let title: String
    let idleTimeout: TimeInterval
    let width: CGFloat
    let height: CGFloat

    static func parse() -> Config {
        let args = CommandLine.arguments
        func flag(_ name: String, _ fallback: String) -> String {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return fallback }
            return args[i + 1]
        }
        let size = flag("--size", "630x700").split(separator: "x")
        return Config(
            url: URL(string: flag("--url", "https://www.icloud.com/notes"))!,
            icon: flag("--icon", "checklist"),
            title: flag("--title", "WebTray"),
            idleTimeout: Double(flag("--idle", "600")) ?? 600,
            width: size.count >= 1 ? CGFloat(Double(size[0]) ?? 420) : 420,
            height: size.count >= 2 ? CGFloat(Double(size[1]) ?? 700) : 700
        )
    }
}

// MARK: - Tab

struct Tab {
    let label: String
    let url: URL
    let hostMatch: String
}

class TabState {
    let tab: Tab
    var webView: WKWebView?
    var idleTimer: Timer?
    var canGoBackObservation: NSKeyValueObservation?
    var isWarm: Bool { webView != nil }

    init(tab: Tab) { self.tab = tab }

    func tearDown() {
        idleTimer?.invalidate()
        idleTimer = nil
        canGoBackObservation = nil
        webView?.removeFromSuperview()
        webView = nil
    }
}

// MARK: - WebViewController

class WebViewController: NSViewController, WKUIDelegate, WKNavigationDelegate {
    private var tabStates: [TabState] = []
    private var backButton: NSButton!
    private var tabButtons: [NSButton] = []
    private var toolbar: NSView!
    private var currentTab: Int = 0
    private var popupWebView: WKWebView?
    private static let toolbarHeight: CGFloat = 24
    let config: Config

    private let internalHosts = ["icloud.com", "apple.com", "google.com", "googleapis.com", "gstatic.com", "anthropic.com", "claude.ai"]

    init(config: Config) {
        self.config = config
        let tabs = [
            Tab(label: "iCloud", url: config.url, hostMatch: "icloud"),
            Tab(label: "Gmail", url: URL(string: "https://mail.google.com/mail/mu/")!, hostMatch: "mail.google"),
            Tab(label: "Calendar", url: URL(string: "https://calendar.google.com/calendar/r")!, hostMatch: "calendar.google"),
            Tab(label: "Claude", url: URL(string: "https://claude.ai/")!, hostMatch: "claude.ai"),
        ]
        self.tabStates = tabs.map { TabState(tab: $0) }
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: config.width, height: config.height))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
        showTab(0)
    }

    private func setupToolbar() {
        let h = Self.toolbarHeight
        toolbar = NSView(frame: NSRect(x: 0, y: view.bounds.height - h, width: view.bounds.width, height: h))
        toolbar.autoresizingMask = [.width, .minYMargin]

        let sep = NSBox(frame: NSRect(x: 0, y: 0, width: toolbar.bounds.width, height: 1))
        sep.boxType = .separator
        sep.autoresizingMask = [.width]
        toolbar.addSubview(sep)

        backButton = NSButton(frame: NSRect(x: 2, y: 1, width: 20, height: 20))
        backButton.bezelStyle = .accessoryBarAction
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
        backButton.imagePosition = .imageOnly
        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.isBordered = false
        backButton.isEnabled = false
        toolbar.addSubview(backButton)

        var x: CGFloat = 28
        for (i, state) in tabStates.enumerated() {
            let btn = NSButton(frame: .zero)
            btn.bezelStyle = .accessoryBarAction
            btn.title = state.tab.label
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            btn.isBordered = false
            btn.target = self
            btn.action = #selector(tabClicked(_:))
            btn.tag = i
            btn.sizeToFit()
            btn.frame = NSRect(x: x, y: 1, width: btn.frame.width + 8, height: 20)
            toolbar.addSubview(btn)
            tabButtons.append(btn)
            x += btn.frame.width + 2
        }

        let homeBtn = NSButton(frame: NSRect(x: toolbar.bounds.width - 48, y: 1, width: 20, height: 20))
        homeBtn.bezelStyle = .accessoryBarAction
        homeBtn.image = NSImage(systemSymbolName: "house", accessibilityDescription: "Home")
        homeBtn.imagePosition = .imageOnly
        homeBtn.target = self
        homeBtn.action = #selector(goHome)
        homeBtn.isBordered = false
        homeBtn.autoresizingMask = [.minXMargin]
        toolbar.addSubview(homeBtn)

        let reloadBtn = NSButton(frame: NSRect(x: toolbar.bounds.width - 24, y: 1, width: 20, height: 20))
        reloadBtn.bezelStyle = .accessoryBarAction
        reloadBtn.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
        reloadBtn.imagePosition = .imageOnly
        reloadBtn.target = self
        reloadBtn.action = #selector(doReload)
        reloadBtn.isBordered = false
        reloadBtn.autoresizingMask = [.minXMargin]
        toolbar.addSubview(reloadBtn)

        view.addSubview(toolbar)
        highlightTab(0)
    }

    // MARK: - Tab switching

    private func showTab(_ index: Int) {
        let prev = tabStates[currentTab]
        prev.webView?.isHidden = true
        startIdleTimer(for: currentTab)

        currentTab = index
        let state = tabStates[index]

        state.idleTimer?.invalidate()
        state.idleTimer = nil

        if !state.isWarm {
            createWebView(for: state)
        }
        state.webView?.isHidden = false
        updateBackButton()
        highlightTab(index)
    }

    private func createWebView(for state: TabState) {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        cfg.defaultWebpagePreferences = prefs

        let cssScript = WKUserScript(
            source: """
                var style = document.createElement('style');
                style.textContent = '#views { top: 0px !important; } #nav { height: 0px !important; overflow: hidden !important; }';
                document.documentElement.appendChild(style);
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        cfg.userContentController.addUserScript(cssScript)

        let h = Self.toolbarHeight
        let webFrame = NSRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height - h)
        let wv = WKWebView(frame: webFrame, configuration: cfg)
        wv.autoresizingMask = [.width, .height]
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"
        wv.uiDelegate = self
        wv.navigationDelegate = self
        view.addSubview(wv, positioned: .below, relativeTo: toolbar)
        state.webView = wv

        state.canGoBackObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
            self?.updateBackButton()
        }

        wv.load(URLRequest(url: state.tab.url))
    }

    private func updateBackButton() {
        backButton.isEnabled = tabStates[currentTab].webView?.canGoBack ?? false
    }

    // MARK: - Idle management

    private func startIdleTimer(for index: Int) {
        let state = tabStates[index]
        guard state.isWarm else { return }
        state.idleTimer?.invalidate()
        state.idleTimer = Timer.scheduledTimer(withTimeInterval: config.idleTimeout, repeats: false) { [weak state] _ in
            state?.tearDown()
        }
    }

    func startAllIdleTimers() {
        for i in 0..<tabStates.count {
            startIdleTimer(for: i)
        }
    }

    func cancelCurrentIdleTimer() {
        let state = tabStates[currentTab]
        state.idleTimer?.invalidate()
        state.idleTimer = nil
    }

    func ensureCurrentTabWarm() {
        let state = tabStates[currentTab]
        if !state.isWarm {
            createWebView(for: state)
        }
        state.webView?.isHidden = false
        updateBackButton()
    }

    func tearDownAll() {
        for state in tabStates { state.tearDown() }
        backButton.isEnabled = false
    }

    var isWarm: Bool { tabStates.contains(where: { $0.isWarm }) }

    // MARK: - Actions

    @objc private func tabClicked(_ sender: NSButton) {
        guard sender.tag != currentTab else { return }
        showTab(sender.tag)
    }

    @objc private func doReload() { tabStates[currentTab].webView?.reload() }
    @objc func goBack() { tabStates[currentTab].webView?.goBack() }
    @objc func goHome() { tabStates[currentTab].webView?.load(URLRequest(url: tabStates[currentTab].tab.url)) }

    private func highlightTab(_ activeIndex: Int) {
        for (i, btn) in tabButtons.enumerated() {
            btn.contentTintColor = i == activeIndex ? .controlAccentColor : .tertiaryLabelColor
        }
    }

    // MARK: - Navigation

    private func isInternalNavigation(_ url: URL) -> Bool {
        guard let host = url.host else { return true }
        return internalHosts.contains(where: { host.hasSuffix($0) })
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated,
              let url = navigationAction.request.url,
              !isInternalNavigation(url) else {
            decisionHandler(.allow)
            return
        }
        NSWorkspace.shared.open(url)
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url, !isInternalNavigation(url) {
            NSWorkspace.shared.open(url)
            return nil
        }
        let popup = WKWebView(frame: webView.bounds, configuration: configuration)
        popup.autoresizingMask = [.width, .height]
        popup.uiDelegate = self
        popup.navigationDelegate = self
        popup.customUserAgent = webView.customUserAgent
        webView.addSubview(popup)
        popupWebView = popup
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView == popupWebView {
            popupWebView?.removeFromSuperview()
            popupWebView = nil
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var webVC: WebViewController!
    private var lastClose: Date = .distantPast
    private let config = Config.parse()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let btn = statusItem.button {
            btn.image = NSImage(systemSymbolName: config.icon, accessibilityDescription: config.title)
            btn.target = self
            btn.action = #selector(onClick(_:))
            btn.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        webVC = WebViewController(config: config)
        popover = NSPopover()
        popover.contentSize = NSSize(width: config.width, height: config.height)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = webVC
    }

    @objc private func onClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggle()
        }
    }

    private func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else if Date().timeIntervalSince(lastClose) > 0.3 {
            open()
        }
    }

    private func open() {
        webVC.cancelCurrentIdleTimer()
        webVC.ensureCurrentTabWarm()
        guard let btn = statusItem.button else { return }
        popover.show(relativeTo: btn.bounds, of: btn, preferredEdge: .minY)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        lastClose = Date()
        webVC.startAllIdleTimers()
    }

    private func showMenu() {
        let menu = NSMenu()
        let reload = NSMenuItem(title: "Reset", action: #selector(doReload), keyEquivalent: "")
        reload.target = self
        menu.addItem(reload)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit \(config.title)", action: #selector(doQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { self.statusItem.menu = nil }
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    @objc private func doReload() { webVC.goHome() }
    @objc private func doQuit() { NSApp.terminate(nil) }
}

// MARK: - Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
