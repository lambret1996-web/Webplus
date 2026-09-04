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
    private let tempCacheTTL: TimeInterval = 30 * 60
    private let staticCacheTTL: TimeInterval = 7 * 24 * 3600
    private let largeFileTTL: TimeInterval = 48 * 3600
    private let memoryCostLimit = 80 * 1024 * 1024
    private let maxCacheSize = 200 * 1024 * 1024
    
    // MARK: - 静态资源扩展名
    private let staticExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "ico", "tiff", "heic", "avif",
        "css", "js", "woff", "woff2", "ttf", "eot", "otf",
        "mp4", "webm", "mp3", "wav", "ogg"
    ]
    
    override init(memoryCapacity: Int, diskCapacity: Int, diskPath path: String?) {
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowserCache", isDirectory: true)
        tempCacheDir = cacheBase.appendingPathComponent("TempWebCache", isDirectory: true)
        staticCacheDir = cacheBase.appendingPathComponent("StaticWebCache", isDirectory: true)
        
        super.init(memoryCapacity: memoryCapacity, diskCapacity: diskCapacity, diskPath: path)
        
        memoryCache.totalCostLimit = memoryCostLimit
        createCacheDirectories()
        cleanupExpiredCache()
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
        return response.expectedContentLength > 5 * 1024 * 1024
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
              let response = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CachedURLResponse.self, from: data) else {
            return nil
        }
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
              let response = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CachedURLResponse.self, from: data) else {
            return nil
        }
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
        memoryCache.setObject(response, forKey: key as NSString, cost: response.data.count)
    }
    
    private func storeToTemp(_ response: CachedURLResponse, for request: URLRequest) {
        guard let key = cacheKey(for: request) else { return }
        let fileURL = tempCacheDir.appendingPathComponent(key)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: true) {
            try? data.write(to: fileURL)
        }
    }
    
    private func storeToStatic(_ response: CachedURLResponse, for request: URLRequest) {
        guard let key = cacheKey(for: request) else { return }
        let fileURL = staticCacheDir.appendingPathComponent(key)
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: response, requiringSecureCoding: true) {
            try? data.write(to: fileURL)
        }
    }
    
    // MARK: - 重写URLCache方法
    override func cachedResponse(for request: URLRequest) -> CachedURLResponse? {
        if request.cachePolicy == .reloadIgnoringLocalCacheData ||
           request.cachePolicy == .reloadIgnoringLocalAndRemoteCacheData {
            return nil
        }
        
        if let cached = memoryCachedResponse(for: request) {
            return cached
        }
        
        if !isStaticResource(request), let cached = tempCachedResponse(for: request) {
            storeToMemory(cached, for: request)
            return cached
        }
        
        if isStaticResource(request), let cached = staticCachedResponse(for: request) {
            storeToMemory(cached, for: request)
            return cached
        }
        
        return nil
    }
    
    override func storeCachedResponse(_ cachedResponse: CachedURLResponse, for request: URLRequest) {
        guard request.httpMethod != "POST",
              cachedResponse.response is HTTPURLResponse else {
            return
        }
        
        storeToMemory(cachedResponse, for: request)
        
        if isStaticResource(request) {
            storeToStatic(cachedResponse, for: request)
        } else {
            storeToTemp(cachedResponse, for: request)
        }
        
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
        let hostKey = host.replacingOccurrences(of: ".", with: "_")
        for dir in [tempCacheDir, staticCacheDir] {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for file in files where file.contains(hostKey) {
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent(file))
                }
            }
        }
    }
    
    // MARK: - 过期清理
    private func cleanupExpiredCache() {
        for dir in [tempCacheDir, staticCacheDir] {
            let ttl = (dir == tempCacheDir) ? tempCacheTTL : staticCacheTTL
            if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
                for file in files {
                    let fileURL = dir.appendingPathComponent(file)
                    if let modDate = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date,
                       Date().timeIntervalSince(modDate) > ttl {
                        try? FileManager.default.removeItem(at: fileURL)
                    }
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
