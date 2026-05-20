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
            title: flag("--title", "MenuTray"),
            idleTimeout: Double(flag("--idle", "600")) ?? 600,
            width: size.count >= 1 ? CGFloat(Double(size[0]) ?? 420) : 420,
            height: size.count >= 2 ? CGFloat(Double(size[1]) ?? 700) : 700
        )
    }
}

// MARK: - WebViewController

struct Tab {
    let label: String
    let url: URL
    let hostMatch: String
}

class WebViewController: NSViewController, WKUIDelegate, WKNavigationDelegate {
    private var webView: WKWebView?
    private var backButton: NSButton!
    private var tabButtons: [NSButton] = []
    private var toolbar: NSView!
    private var canGoBackObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private static let toolbarHeight: CGFloat = 24
    let config: Config
    let tabs: [Tab]

    init(config: Config) {
        self.config = config
        self.tabs = [
            Tab(label: "iCloud", url: config.url, hostMatch: "icloud"),
            Tab(label: "Gmail", url: URL(string: "https://mail.google.com/mail/mu/")!, hostMatch: "mail.google"),
            Tab(label: "Calendar", url: URL(string: "https://calendar.google.com/calendar/r")!, hostMatch: "calendar.google"),
        ]
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: config.width, height: config.height))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
        warmUp()
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
        for (i, tab) in tabs.enumerated() {
            let btn = NSButton(frame: .zero)
            btn.bezelStyle = .accessoryBarAction
            btn.title = tab.label
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

    @objc private func doReload() { webView?.reload() }

    private func highlightTab(_ activeIndex: Int) {
        for (i, btn) in tabButtons.enumerated() {
            btn.contentTintColor = i == activeIndex ? .controlAccentColor : .tertiaryLabelColor
        }
    }

    private var currentTab: Int = 0

    private func activeTabIndex(for url: URL?) -> Int? {
        guard let host = url?.host else { return nil }
        for (i, tab) in tabs.enumerated() {
            if host.contains(tab.hostMatch) { return i }
        }
        return nil
    }

    @objc private func tabClicked(_ sender: NSButton) {
        let tab = tabs[sender.tag]
        webView?.load(URLRequest(url: tab.url))
        currentTab = sender.tag
        highlightTab(sender.tag)
    }

    func warmUp() {
        guard webView == nil else { return }
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
        webView = wv

        canGoBackObservation = wv.observe(\.canGoBack, options: [.new]) { [weak self] _, change in
            self?.backButton.isEnabled = change.newValue ?? false
        }
        urlObservation = wv.observe(\.url, options: [.new]) { [weak self] _, change in
            guard let self, let idx = self.activeTabIndex(for: change.newValue ?? nil) else { return }
            self.currentTab = idx
            self.highlightTab(idx)
        }

        wv.load(URLRequest(url: config.url))
    }

    func tearDown() {
        canGoBackObservation = nil
        urlObservation = nil
        webView?.removeFromSuperview()
        webView = nil
        backButton.isEnabled = false
        currentTab = 0
        highlightTab(0)
    }

    func reload() { webView?.reload() }
    func goHome() { webView?.load(URLRequest(url: config.url)) }
    var isWarm: Bool { webView != nil }

    @objc func goBack() { webView?.goBack() }

    private let internalHosts = ["icloud.com", "apple.com", "google.com", "googleapis.com", "gstatic.com", "accounts.google.com"]

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
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var webVC: WebViewController!
    private var idleTimer: Timer?
    private var lastClose: Date = .distantPast
    private let config = Config.parse()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

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
        idleTimer?.invalidate()
        idleTimer = nil
        if !webVC.isWarm { webVC.warmUp() }
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
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: config.idleTimeout, repeats: false) { [weak self] _ in
            self?.webVC.tearDown()
        }
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

    @objc private func doReload() { webVC.goHome() }
    @objc private func doQuit() { NSApp.terminate(nil) }
}

// MARK: - Entry

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
