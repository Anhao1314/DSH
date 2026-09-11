import SwiftUI
import WebKit

/// 页面 → 原生 的单向事件（对应控制台 §4.2 桥接发的三类消息）。
struct WebHostEvent {
    enum Kind: String {
        case runningChanged
        case selectionChanged
        case taskFinished
    }

    let kind: Kind
    let sessionId: String
    let running: Bool
    let verdict: String
}

/// WKWebView 的持有者与「切会话」入口。
///
/// 切换会话优先调用页面里的 `window.dshHostAPI.select(id)`（不整页重载）；
/// 页面还没注册好 API、或目标 id 不在列表里时，降级为整页带 `?session=` 重载。
final class WebViewStore: ObservableObject {
    weak var webView: WKWebView?
    private(set) var baseURL: URL?
    var onHostEvent: ((WebHostEvent) -> Void)?

    func reload() { webView?.reload() }

    func setBase(_ url: URL) { baseURL = url }

    func select(session id: String) {
        guard WebViewStore.isSafeSessionID(id), let webView else { return }
        let script = "window.dshHostAPI && window.dshHostAPI.select(\(WebViewStore.jsLiteral(id))) ? 'ok' : 'no'"
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard (result as? String) != "ok" else { return }
            self?.reloadSelecting(session: id)
        }
    }

    func reloadSelecting(session id: String) {
        guard WebViewStore.isSafeSessionID(id),
              let base = baseURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "session" }
        items.append(URLQueryItem(name: "session", value: id))
        components.queryItems = items
        guard let url = components.url else { return }
        webView?.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    /// session id 与中继同一条白名单正则：`session-<uuid>` 或裸 `<uuid>`。
    static func isSafeSessionID(_ id: String) -> Bool {
        let pattern = "^(?:session-)?[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        return id.range(of: pattern, options: [.regularExpression]) != nil
    }

    /// 拼进 JS 的字面量必须转义（id 已过白名单，这里仍然按最坏情况处理）。
    static func jsLiteral(_ value: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [value], options: [])) ?? Data("[\"\"]".utf8)
        let json = String(data: data, encoding: .utf8) ?? "[\"\"]"
        return String(json.dropFirst().dropLast())
    }
}

struct WebView: NSViewRepresentable {
    let url: URL
    let store: WebViewStore
    var onFail: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: ArtifactSchemeHandler.scheme)
        configuration.userContentController.addUserScript(WKUserScript(
            source: "window.dshNativeArtifacts = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        configuration.userContentController.add(context.coordinator, name: Coordinator.handlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground") // 加载期间露出 SwiftUI 背景
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))

        context.coordinator.store = store
        store.setBase(url)
        DispatchQueue.main.async { store.webView = webView }
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // token 轮换 / 容器重启后 url 会变，此时才整页重载。
        if nsView.url != url {
            store.setBase(url)
            nsView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    static func dismantleNSView(_ nsView: WKWebView, coordinator: Coordinator) {
        nsView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.handlerName)
        nsView.stopLoading()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFail: onFail) }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let handlerName = "dshHost"

        let onFail: () -> Void
        let schemeHandler = ArtifactSchemeHandler()
        weak var store: WebViewStore?

        init(onFail: @escaping () -> Void) {
            self.onFail = onFail
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Coordinator.handlerName,
                  let body = message.body as? [String: Any],
                  let rawType = body["type"] as? String,
                  let kind = WebHostEvent.Kind(rawValue: rawType) else { return }
            let event = WebHostEvent(
                kind: kind,
                sessionId: body["sessionId"] as? String ?? "",
                running: body["running"] as? Bool ?? false,
                verdict: body["verdict"] as? String ?? ""
            )
            store?.onHostEvent?(event)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            onFail()
        }

        func webView(_ webView: WKWebView, didFailProvisionalLoadWithError error: Error) {
            if (error as NSError).code == NSURLErrorCancelled { return }
            onFail()
        }
    }
}
