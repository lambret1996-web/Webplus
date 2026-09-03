import UIKit
// MARK: - 精细化智能缓存：按资源类型区分缓存时长
class SmartURLCache: URLCache {
    private let staticCacheTTL: TimeInterval = 24 * 60 * 60
    private let htmlCacheTTL: TimeInterval = 30 * 60
    override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {
        guard let httpResponse = cachedResponse.response as? HTTPURLResponse else {
            super.storeCachedResponse(cachedResponse, for: request)
            return
        }
        // 安全转换 allHeaderFields
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                headers[k] = v
            }
        }
        let mimeType = headers["Content-Type"]?.lowercased() ?? ""
        let urlPath = request.url?.path.lowercased() ?? ""
        let isStatic = mimeType.hasPrefix("image/") ||
                       mimeType.contains("javascript") ||
                       mimeType.contains("css") ||
                       mimeType.contains("font") ||
                       urlPath.hasSuffix(".js") || urlPath.hasSuffix(".css") ||
                       urlPath.hasSuffix(".png") || urlPath.hasSuffix(".jpg") ||
                       urlPath.hasSuffix(".jpeg") || urlPath.hasSuffix(".gif") ||
                       urlPath.hasSuffix(".svg") || urlPath.hasSuffix(".webp") ||
                       urlPath.hasSuffix(".woff") || urlPath.hasSuffix(".woff2") ||
                       urlPath.hasSuffix(".ttf") || urlPath.hasSuffix(".ico")
        let ttl = isStatic ? staticCacheTTL : htmlCacheTTL
        headers["Cache-Control"] = "public, max-age=\(Int(ttl))"
        if let modifiedResponse = HTTPURLResponse(url: httpResponse.url ?? request.url!,
                                                   statusCode: httpResponse.statusCode,
                                                   httpVersion: "HTTP/1.1",
                                                   headerFields: headers) {
            var userInfo = cachedResponse.userInfo ?? [:]
            userInfo[AnyHashable("storeDate")] = Date()
            let smartResponse = CachedURLResponse(response: modifiedResponse,
                                                   data: cachedResponse.data,
                                                   userInfo: userInfo,
                                                   storagePolicy: .allowed)
            super.storeCachedResponse(smartResponse, for: request)
        } else {
            super.storeCachedResponse(cachedResponse, for: request)
        }
    }
    override func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        guard let cached = super.cachedResponse(for: request),
              let httpResponse = cached.response as? HTTPURLResponse,
              let cacheControl = httpResponse.allHeaderFields["Cache-Control"] as? String,
              let maxAgeMatch = cacheControl.range(of: "max-age=(\\d+)", options: .regularExpression),
              let maxAge = TimeInterval(cacheControl[maxAgeMatch].replacingOccurrences(of: "max-age=", with: "")) else {
            return super.cachedResponse(for: request)
        }
        if let userInfo = cached.userInfo, let storedDate = userInfo[AnyHashable("storeDate")] as? Date {
            if Date().timeIntervalSince(storedDate) > maxAge {
                removeCachedResponse(for: request)
                return nil
            }
        }
        return cached
    }
}
@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // 精细化智能缓存：静态资源24h，HTML 30min
        let memoryCapacity = 64 * 1024 * 1024
        let diskCapacity = 256 * 1024 * 1024
        let cache = SmartURLCache(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: "SmartBrowserCache")
        URLCache.shared = cache
        // 网络优化：HTTP/3(QUIC)系统自动协商，优化连接参数
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 8
        config.httpShouldUsePipelining = true
        config.waitsForConnectivity = true
        config.networkServiceType = .responsiveData
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return true
    }
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
    }
}
