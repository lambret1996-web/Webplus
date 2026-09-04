//
//  FourLevelCache.swift
//  WebViewBrowser
//
//  四级分层缓存管理器：内存→瞬时磁盘→持久静态→网络兜底
//

import Foundation

class FourLevelCache: URLCache {
    
    // MARK: - 缓存目录
    private let memoryCache = NSCache<NSString, CachedURLResponse>()
    private let tempCacheDir: URL
    private let staticCacheDir: URL
    
    // MARK: - 时效配置
    private let tempCacheTTL: TimeInterval = 30 * 60      // 二级瞬时缓存：30分钟
    private let staticCacheTTL: TimeInterval = 7 * 24 * 3600 // 三级持久缓存：7天
    private let largeFileTTL: TimeInterval = 48 * 3600     // 大文件：48小时
    private let memoryCostLimit = 80 * 1024 * 1024         // 一级内存：80MB
    private let maxCacheSize = 200 * 1024 * 1024           // 总缓存上限：200MB
    
    // MARK: - 静态资源扩展名
    private let staticExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "ico", "tiff", "heic", "avif",
        "css", "js", "woff", "woff2", "ttf", "eot", "otf",
        "mp4", "webm", "mp3", "wav", "ogg"
    ]
    
    // MARK: - 单例
    static let shared = FourLevelCache()
    
    private override init(memoryCapacity: Int, diskCapacity: Int, diskPath path: String?) {
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowserCache", isDirectory: true)
        tempCacheDir = cacheBase.appendingPathComponent("TempWebCache", isDirectory: true)
        staticCacheDir = cacheBase.appendingPathComponent("StaticWebCache", isDirectory: true)
        
        super.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: path)
        
        memoryCache.totalCostLimit = memoryCostLimit
        createCacheDirectories()
        cleanupExpiredCache()
    }
    
    convenience init() {
        self.init(memoryCapacity: 80 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "FourLevelCache")
    }
    
    // MARK: - 目录创建
    private func createCacheDirectories() {
        for dir in [tempCacheDir, staticCacheDir] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - 缓存键
    private func cacheKey(for request: URLRequest) -> String? {
        guard let url = request.url?.absoluteString else { return nil }
        return url.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "?", with: "_")
            .replacingOccurrences(of: "&", with: "_")
    }
    
    // MARK: - 判断资源类型
    private func isStaticResource(_ request: URLRequest) -> Bool {
        guard let ext = request.url?.pathExtension.lowercased() else { return false }
        return staticExtensions.contains(ext)
    }
    
    private func isLargeFile(_ response: URLResponse) -> Bool {
        return response.expectedContentLength > 5 * 1024 * 1024 // 大于5MB
    }
    
    // MARK: - 一级：内存缓存读取
    private func memoryCachedResponse(for request: URLRequest) -> CachedURLResponse? {
        guard let key = cacheKey(for: request) else { return nil }
        return memoryCache.object(forKey: key as NSString)
    }
    
    // MARK: - 二级：瞬时磁盘缓存读取
    private func tempCachedResponse(for request: URLRequest) -> CachedURLResponse? {
        guard let key = cacheKey(for: request) else { return nil }
        let fileURL = tempCacheDir.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: fileURL),
              let response = NSKeyedUnarchiver.unarchiveObject(with: data) as? CachedURLResponse else {
            return nil
        }
        // 检查过期
        if let modDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > tempCacheTTL {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return response
    }
    
    // MARK: - 三级：持久静态缓存读取
    private func staticCachedResponse(for request: URLRequest) -> CachedURLResponse? {
        guard let key = cacheKey(for: request) else { return nil }
        let fileURL = staticCacheDir.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: fileURL),
              let response = NSKeyedUnarchiver.unarchiveObject(with: data) as? CachedURLResponse else {
            return nil
        }
        // 检查过期
        let ttl = isLargeFile(response.response) ? largeFileTTL : staticCacheTTL
        if let modDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
           Date().timeIntervalSince(modDate) > ttl {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        return response
    }
    
    // MARK: - 写入缓存
    private func storeToMemory(_ response: CachedURLResponse, for request: URLRequest) {
        guard let key = cacheKey(for: request) else { return }
        let cost = response.data.count
        memoryCache.setObject(response, forKey: key as NSString, cost: cost)
    }
    
    private func storeToTemp(_ response: CachedURLResponse, for request: URLRequest) {
        guard let key = cacheKey(for: request) else { return }
        let fileURL = tempCacheDir.appendingPathComponent(key)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: false) {
            try? data.write(to: fileURL)
        }
    }
    
    private func storeToStatic(_ response: CachedURLResponse, for request: URLRequest) {
        guard let key = cacheKey(for: request) else { return }
        let fileURL = staticCacheDir.appendingPathComponent(key)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: false) {
            try? data.write(to: fileURL)
        }
    }
    
    // MARK: - 重写URLCache方法
    override func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        // 强制刷新请求不使用缓存
        if request.cachePolicy == .reloadIgnoringLocalCacheData ||
           request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData {
            return nil
        }
        
        // 一级：内存缓存
        if let cached = memoryCachedResponse(for: request) {
            return cached
        }
        
        // 二级：瞬时磁盘缓存（动态页面）
        if !isStaticResource(request), let cached = tempCachedResponse(for: request) {
            storeToMemory(cached, for: request) // 回写到内存
            return cached
        }
        
        // 三级：持久静态缓存
        if isStaticResource(request), let cached = staticCachedResponse(for: request) {
            storeToMemory(cached, for: request) // 回写到内存
            return cached
        }
        
        // 四级：网络兜底（返回nil让系统走网络）
        return nil
    }
    
    override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {
        // 不缓存POST请求和非HTTP响应
        guard request.httpMethod != "POST",
              cachedResponse.response is HTTPURLResponse else {
            return
        }
        
        // 一级：写入内存
        storeToMemory(cachedResponse, for: request)
        
        // 二级/三级：写入磁盘
        if isStaticResource(request) {
            storeToStatic(cachedResponse, for: request)
        } else {
            storeToTemp(cachedResponse, for: request)
        }
        
        // 检查总容量，超标自动清理
        checkAndCleanupIfNeeded()
    }
    
    override func removeCachedResponse(for request: URLRequest) {
        guard let key = cacheKey(for: request) else { return }
        memoryCache.removeObject(forKey: key as NSString)
        try? FileManager.default.removeItem(at: tempCacheDir.appendingPathComponent(key))
        try? FileManager.default.removeItem(at: staticCacheDir.appendingPathComponent(key))
    }
    
    override func removeAllCachedResponses() {
        memoryCache.removeAllObjects()
        try? FileManager.default.removeItem(at: tempCacheDir)
        try? FileManager.default.removeItem(at: staticCacheDir)
        createCacheDirectories()
    }
    
    // MARK: - 精细化清理
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }
    
    func clearTempCache() {
        try? FileManager.default.removeItem(at: tempCacheDir)
        createCacheDirectories()
    }
    
    func clearStaticCache() {
        try? FileManager.default.removeItem(at: staticCacheDir)
        createCacheDirectories()
    }
    
    func clearCacheForSite(_ host: String) {
        let predicate = NSPredicate(format: "SELF CONTAINS %@", host.replacingOccurrences(of: ".", with: "_"))
        for dir in [tempCacheDir, staticCacheDir] {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for file in files where predicate.evaluate(with: file) {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
                }
            }
        }
    }
    
    // MARK: - 过期清理
    private func cleanupExpiredCache() {
        // 清理二级过期缓存
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tempCacheDir.path) {
            for file in files {
                let fileURL = tempCacheDir.appendingPathComponent(file)
                if let modDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
                   Date().timeIntervalSince(modDate) > tempCacheTTL {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
        // 清理三级过期缓存
        if let files = try? FileManager.default.contentsOfDirectory(atPath: staticCacheDir.path) {
            for file in files {
                let fileURL = staticCacheDir.appendingPathComponent(file)
                if let modDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
                   Date().timeIntervalSince(modDate) > staticCacheTTL {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }
    
    // MARK: - 容量检查
    private func checkAndCleanupIfNeeded() {
        var totalSize = 0
        for dir in [tempCacheDir, staticCacheDir] {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for file in files {
                    let fileURL = dir.appendingPathComponent(file)
                    if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int {
                        totalSize += size
                    }
                }
            }
        }
        if totalSize > maxCacheSize {
            // LRU淘汰：删除最旧的文件
            cleanupLRU()
        }
    }
    
    private func cleanupLRU() {
        var allFiles: [(url: URL, date: Date)] = []
        for dir in [tempCacheDir, staticCacheDir] {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for file in files {
                    let fileURL = dir.appendingPathComponent(file)
                    if let modDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date {
                        allFiles.append((fileURL, modDate))
                    }
                }
            }
        }
        // 按时间排序，删除最旧的30%
        allFiles.sort { $0.date < $1.date }
        let removeCount = allFiles.count / 3
        for i in 0..<removeCount {
            try? FileManager.default.removeItem(at: allFiles[i].url)
        }
    }
    
    // MARK: - 缓存统计
    func cacheSize() -> (memory: Int, temp: Int, static: Int) {
        var tempSize = 0, staticSize = 0
        if let files = try? FileManager.default.contentsOfDirectory(atPath: tempCacheDir.path) {
            for file in files {
                let fileURL = tempCacheDir.appendingPathComponent(file)
                if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int {
                    tempSize += size
                }
            }
        }
        if let files = try? FileManager.default.contentsOfDirectory(atPath: staticCacheDir.path) {
            for file in files {
                let fileURL = staticCacheDir.appendingPathComponent(file)
                if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int {
                    staticSize += size
                }
            }
        }
        return (memoryCostLimit, tempSize, staticSize)
    }
}
