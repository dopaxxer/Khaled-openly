import UIKit
import WebKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = WebViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

final class WebViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let productionURL = URL(string: "https://openly.ink")!

    private lazy var apiSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    private lazy var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .default()
        configuration.applicationNameForUserAgent = "Openly-iOS/2.0"
        configuration.userContentController.add(self, name: "openlyApi")

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.navigationDelegate = self
        view.uiDelegate = self
        view.allowsBackForwardNavigationGestures = true
        view.scrollView.contentInsetAdjustmentBehavior = .never
        return view
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.95, alpha: 1)
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refreshPage(_:)), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl

        loadOpenlyBundle()
    }

    private func loadOpenlyBundle() {
        guard let indexURL = Bundle.main.url(
            forResource: "index",
            withExtension: "html",
            subdirectory: "WebBundle"
        ) else {
            webView.loadHTMLString(
                "<html><body style='font-family:-apple-system;padding:40px'>Openly bundle is missing.</body></html>",
                baseURL: nil
            )
            return
        }

        webView.loadFileURL(indexURL, allowingReadAccessTo: indexURL.deletingLastPathComponent())
    }

    @objc private func refreshPage(_ sender: UIRefreshControl) {
        webView.reload()
        sender.endRefreshing()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "openlyApi",
              let payload = message.body as? [String: Any],
              let requestID = payload["id"] as? String,
              let path = payload["path"] as? String,
              path.hasPrefix("/api/"),
              let targetURL = URL(string: path, relativeTo: productionURL)?.absoluteURL,
              targetURL.scheme == "https",
              targetURL.host == "openly.ink" else {
            return
        }

        var request = URLRequest(url: targetURL)
        request.httpMethod = (payload["method"] as? String) ?? "GET"
        request.timeoutInterval = 45

        if let headers = payload["headers"] as? [String: Any] {
            for (key, value) in headers {
                request.setValue(String(describing: value), forHTTPHeaderField: key)
            }
        }

        if let body = payload["body"] as? String {
            request.httpBody = body.data(using: .utf8)
        }

        apiSession.dataTask(with: request) { [weak self] data, response, error in
            let http = response as? HTTPURLResponse
            let status = error == nil ? (http?.statusCode ?? 200) : 599
            var responseHeaders: [String: String] = [:]

            if let http {
                for (key, value) in http.allHeaderFields {
                    responseHeaders[String(describing: key)] = String(describing: value)
                }
            }

            var responseBody = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            if let error, responseBody.isEmpty {
                responseBody = error.localizedDescription
            }

            self?.resolveNativeRequest(
                id: requestID,
                payload: [
                    "status": status,
                    "headers": responseHeaders,
                    "body": responseBody
                ]
            )
        }.resume()
    }

    private func resolveNativeRequest(id: String, payload: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(payload),
              let payloadData = try? JSONSerialization.data(withJSONObject: payload),
              let payloadJSON = String(data: payloadData, encoding: .utf8),
              let idData = try? JSONEncoder().encode(id),
              let idJSON = String(data: idData, encoding: .utf8) else {
            return
        }

        let script = "window.__openlyNativeResolve(\(idJSON), \(payloadJSON));"
        DispatchQueue.main.async { [weak self] in
            self?.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }

        if url.isFileURL || url.scheme == "about" {
            decisionHandler(.allow)
            return
        }

        if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto", "tel"].contains(scheme) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        return nil
    }
}
