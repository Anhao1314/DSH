import SwiftUI
import WebKit

// Thin WKWebView wrapper. All UI is the self-built console served by the
// in-container relay at /console. Artifact preview uses the native
// `dsh-artifact` scheme below instead of the absent /console-api backend.
final class WebViewStore: ObservableObject {
    weak var webView: WKWebView?
    func reload() { webView?.reload() }
}

struct WebView: NSViewRepresentable {
    let url: URL
    let store: WebViewStore
    var onFail: () -> Void

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.setURLSchemeHandler(context.coordinator.schemeHandler, forURLScheme: ArtifactSchemeHandler.scheme)
        cfg.userContentController.addUserScript(WKUserScript(
            source: "window.dshNativeArtifacts = true;",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        wv.setValue(false, forKey: "drawsBackground") // let SwiftUI background show while loading
        wv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        DispatchQueue.main.async { self.store.webView = wv }
        return wv
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if nsView.url != url {
            nsView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFail: onFail) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onFail: () -> Void
        let schemeHandler = ArtifactSchemeHandler()

        init(onFail: @escaping () -> Void) {
            self.onFail = onFail
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
