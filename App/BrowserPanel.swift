import AppKit
import SwiftUI
import WebKit

/// A session's own browser. Its tabs stay open, scrolled and signed in while you move between
/// sessions. Links clicked in the terminal open here; ⌘-click opens the default browser instead.
@MainActor @Observable
final class SessionBrowser {
    private(set) var tabs: [BrowserTab] = []
    var selectedID: BrowserTab.ID?
    var isVisible = false

    var selected: BrowserTab? { tabs.first { $0.id == selectedID } ?? tabs.last }

    /// Shows a link, reusing a tab already on that page.
    func open(_ url: URL) {
        isVisible = true
        if let tab = tabs.first(where: { $0.url == url }) {
            selectedID = tab.id
        } else {
            add(BrowserTab(url: url, browser: self))
        }
    }

    func newTab() {
        isVisible = true
        add(BrowserTab(url: nil, browser: self))
    }

    func add(_ tab: BrowserTab) {
        tabs.append(tab)
        selectedID = tab.id
    }

    func close(_ tab: BrowserTab) {
        guard let index = tabs.firstIndex(where: { $0 === tab }) else { return }
        tab.tearDown()
        tabs.remove(at: index)
        if selectedID == tab.id { selectedID = tabs.indices.contains(index) ? tabs[index].id : tabs.last?.id }
        if tabs.isEmpty { isVisible = false }
    }

    func closeAll() {
        tabs.forEach { $0.tearDown() }
        tabs = []
        isVisible = false
    }
}

@MainActor @Observable
final class BrowserTab: NSObject, Identifiable, WKNavigationDelegate, WKUIDelegate {
    let id = UUID()
    let webView: WKWebView
    private(set) var title = ""
    private(set) var url: URL?
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private weak var browser: SessionBrowser?

    /// Shared by every session: one persistent cookie store, so signing in once is enough.
    static let configuration: WKWebViewConfiguration = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        // Identify as Safari: some sign-in pages refuse browsers they do not recognize.
        configuration.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.preferences.isElementFullscreenEnabled = true
        return configuration
    }()

    init(url: URL?, browser: SessionBrowser, configuration: WKWebViewConfiguration = BrowserTab.configuration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.browser = browser
        self.url = url
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        observations = [
            webView.observe(\.title) { [weak self] view, _ in MainActor.assumeIsolated { self?.title = view.title ?? "" } },
            webView.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { if let url = view.url { self?.url = url } } },
            webView.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            webView.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } },
        ]
        if let url { webView.load(URLRequest(url: url)) }
    }

    var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.host() ?? "New Tab"
    }

    func load(_ url: URL) {
        self.url = url
        webView.load(URLRequest(url: url))
    }

    func tearDown() {
        observations = []
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    // Links that ask for a new window open as a tab in the same session's browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let browser else { return nil }
        let tab = BrowserTab(url: nil, browser: browser, configuration: configuration)
        browser.add(tab)
        return tab.webView
    }

    func webViewDidClose(_ webView: WKWebView) {
        browser?.close(self)
    }

    // Mail, app and other non-web links go to the system.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased(),
              !["http", "https", "about", "blob", "data", "file"].contains(scheme) else { return .allow }
        NSWorkspace.shared.open(url)
        return .cancel
    }
}

/// The browser column: tabs, navigation and the selected page.
struct BrowserPanel: View {
    let browser: SessionBrowser
    @ViewState<String> private var address = ""
    @FocusState private var addressFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            toolbar
            Rectangle().fill(Theme.line).frame(height: 1)
            if let tab = browser.selected {
                WebViewHost(webView: tab.webView)
            } else {
                Text("no pages open").font(Theme.mono(11)).foregroundStyle(Theme.faint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .onChange(of: browser.selected?.url, initial: true) {
            if !addressFocused { address = browser.selected?.url?.absoluteString ?? "" }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(browser.tabs) { tab in tabChip(tab) }
                Button {
                    browser.newTab()
                    address = ""
                    addressFocused = true
                } label: {
                    Text("+").font(Theme.mono(13, .bold)).frame(width: 30, height: 30).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.phosphor)
                .help("New tab")
            }
        }
        .background(Theme.panel)
    }

    private func tabChip(_ tab: BrowserTab) -> some View {
        let selected = tab.id == browser.selected?.id
        return HStack(spacing: 6) {
            if tab.isLoading { Text("◌").foregroundStyle(Theme.phosphor) }
            Text(tab.displayTitle).lineLimit(1).truncationMode(.tail)
            Button { browser.close(tab) } label: { Text("×").font(Theme.mono(12)) }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.dim)
                .help("Close tab")
        }
        .font(Theme.mono(10.5))
        .foregroundStyle(selected ? Theme.text : Theme.dim)
        .frame(maxWidth: 180, alignment: .leading)
        .padding(.horizontal, 10).frame(height: 30)
        .background(selected ? Theme.background : .clear)
        .overlay(alignment: .top) { Rectangle().fill(Theme.phosphor).frame(height: 2).opacity(selected ? 1 : 0) }
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { browser.selectedID = tab.id }
        .help(tab.url?.absoluteString ?? tab.displayTitle)
    }

    private var toolbar: some View {
        let tab = browser.selected
        return HStack(spacing: 6) {
            navButton("‹", help: "Back", enabled: tab?.canGoBack == true) { tab?.webView.goBack() }
            navButton("›", help: "Forward", enabled: tab?.canGoForward == true) { tab?.webView.goForward() }
            if tab?.isLoading == true {
                navButton("×", help: "Stop", enabled: true) { tab?.webView.stopLoading() }
            } else {
                navButton("↻", help: "Reload", enabled: tab != nil) { tab?.webView.reload() }
            }
            TextField("address", text: $address)
                .textFieldStyle(.plain).font(Theme.mono(11)).foregroundStyle(Theme.text)
                .focused($addressFocused)
                .onSubmit(go)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(addressFocused ? Theme.phosphor.opacity(0.6) : Theme.line, lineWidth: 1))
            navButton("⧉", help: "Open in your default browser", enabled: tab?.url != nil) {
                if let url = tab?.url { NSWorkspace.shared.open(url) }
            }
            navButton("⇥", help: "Hide the browser (⌘B). Its tabs stay open.", enabled: true) { browser.isVisible = false }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Theme.panel)
    }

    private func navButton(_ glyph: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph).font(Theme.mono(13, .semibold)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Theme.phosphor : Theme.faint.opacity(0.5))
        .disabled(!enabled)
        .help(help)
    }

    /// Loads what was typed: a full URL, or a host such as `github.com/owner/repo`.
    private func go() {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return }
        let candidate = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: candidate), url.host() != nil else { return }
        if let tab = browser.selected { tab.load(url) } else { browser.open(url) }
        addressFocused = false
    }
}

/// Hosts a tab's web view. The view belongs to the tab, not to SwiftUI, so leaving a session
/// detaches it without unloading the page.
private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ container: NSView, context: Context) {
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}
