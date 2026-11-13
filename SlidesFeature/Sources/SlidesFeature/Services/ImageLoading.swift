import UIKit
import WebKit

/// Image data the slides can use: what UIKit reads as it is, and SVG drawn to a PNG.
@MainActor
enum ImageLoading {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Data UIKit can decode, turning SVG into PNG first.
    static func usableData(_ data: Data, mimeType: String? = nil) async throws -> Data {
        if UIImage(data: data) != nil { return data }
        if isSVG(data, mimeType: mimeType) { return try await SVGRasterizer.png(from: data) }
        throw Failure(message: "この形式の画像は読み込めませんでした。")
    }

    /// An image from a web address (https or http).
    static func download(_ text: String) async throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme) else {
            throw Failure(message: "画像のリンク（https://…）を入力してください。")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "画像を取得できませんでした。リンクと通信状態を確認してください。")
        }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure(message: "画像を取得できませんでした（\(http.statusCode)）。")
        }
        return try await usableData(data, mimeType: response.mimeType)
    }

    static func isSVG(_ data: Data, mimeType: String?) -> Bool {
        if mimeType?.lowercased().contains("svg") == true { return true }
        let head = String(decoding: data.prefix(1024), as: UTF8.self).lowercased()
        return head.contains("<svg")
    }
}

/// Draws an SVG with WebKit (the system has no other SVG renderer) and takes a picture of it,
/// its longest side 1024 points at the screen's scale.
@MainActor
final class SVGRasterizer: NSObject, WKNavigationDelegate {
    private var finished: CheckedContinuation<Void, Error>?

    static func png(from data: Data) async throws -> Data {
        try await SVGRasterizer().render(data)
    }

    private func render(_ data: Data) async throws -> Data {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 1024), configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = self
        // Laid out in a window (off screen), or WebKit draws nothing.
        let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        webView.frame.origin = CGPoint(x: -20000, y: -20000)
        window?.addSubview(webView)
        defer { webView.removeFromSuperview() }

        let base64 = data.base64EncodedString()
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>html,body{margin:0;padding:0;background:transparent}img{display:block}</style></head>
        <body><img id="svg" src="data:image/svg+xml;base64,\(base64)"></body></html>
        """
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            finished = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
        // The image's own size, then fitted to 1024 points on its longest side.
        let measured = try await webView.evaluateJavaScript(
            "(function(){var i=document.getElementById('svg');return [i.naturalWidth||0,i.naturalHeight||0];})()"
        ) as? [Double] ?? []
        var width = measured.first ?? 0
        var height = measured.count > 1 ? measured[1] : 0
        if width <= 0 || height <= 0 {
            width = 1024
            height = 1024
        }
        let fit = 1024 / max(width, height)
        width = (width * fit).rounded()
        height = (height * fit).rounded()
        _ = try await webView.evaluateJavaScript(
            "(function(){var i=document.getElementById('svg');i.style.width='\(Int(width))px';i.style.height='\(Int(height))px';return 1;})()"
        )
        webView.frame.size = CGSize(width: width, height: height)
        try await Task.sleep(for: .milliseconds(150))
        let snapshot = WKSnapshotConfiguration()
        snapshot.rect = CGRect(x: 0, y: 0, width: width, height: height)
        snapshot.afterScreenUpdates = true
        let image = try await webView.takeSnapshot(configuration: snapshot)
        guard let png = image.pngData() else { throw ImageLoading.Failure(message: "SVGを画像にできませんでした。") }
        return png
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated {
            finished?.resume()
            finished = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            finished?.resume(throwing: ImageLoading.Failure(message: "SVGを読み込めませんでした。"))
            finished = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        MainActor.assumeIsolated {
            finished?.resume(throwing: ImageLoading.Failure(message: "SVGを読み込めませんでした。"))
            finished = nil
        }
    }
}
