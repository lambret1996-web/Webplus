//
//  OfflineCacheManager.swift
//  轻量浏览器 - 四级离线缓存管理器
//
//  功能：
//  - 完整保存网页（HTML + 图片/CSS/JS资源）到四级离线缓存
//  - 轻量保存（仅URL+标题，进程终止兜底）
//  - App启动后补全未完成的离线保存
//  - URL去重、空间保护、数量上限、先进先出淘汰
//

import UIKit
import WebKit

class OfflineCacheManager {

    static let shared = OfflineCacheManager()

    // MARK: - 目录结构
    // Library/CacheManager/Level4_Offline/
    //   ├── index.plist        # 离线网页清单
    //   └── items/<uuid>/      # 每个网页一个文件夹
    //       ├── index.html
    //       ├── manifest.json
    //       └── assets/

    private let fileManager = FileManager.default

    private var offlineRoot: URL {
        let lib = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return lib.appendingPathComponent("CacheManager/Level4_Offline", isDirectory: true)
    }

    private var itemsDir: URL { offlineRoot.appendingPathComponent("items", isDirectory: true) }
    private var indexPath: URL { offlineRoot.appendingPathComponent("index.plist") }

    // MARK: - 数据模型
    struct OfflineItem: Codable {
        var uuid: String
        var pageTitle: String
        var originURL: String
        var saveTimestamp: TimeInterval
        var saveType: String        // "auto" 自动保存 / "manual" 手动保存
        var isProtected: Bool       // 四级保护标记
        var saveStatus: String      // "completed" 完成 / "pending" 待补资源
    }

    // MARK: - 用户配置读取
    private var autoSaveOnBackground: Bool {
        UserDefaults.standard.object(forKey: "offlineAutoSaveOnBackground") as? Bool ?? true
    }
    private var autoSaveOnNavigate: Bool {
        UserDefaults.standard.object(forKey: "offlineAutoSaveOnNavigate") as? Bool ?? false
    }
    private var completePendingOnLaunch: Bool {
        UserDefaults.standard.object(forKey: "offlineCompletePendingOnLaunch") as? Bool ?? true
    }
    private var maxAutoItems: Int {
        let v = UserDefaults.standard.integer(forKey: "offlineMaxAutoItems")
        return v > 0 ? v : 20
    }
    private var spaceThresholdGB: Double {
        let v = UserDefaults.standard.double(forKey: "offlineSpaceThresholdGB")
        return v > 0 ? v : 2.0
    }
    private var urlDedupDays: Int {
        let v = UserDefaults.standard.integer(forKey: "offlineUrlDedupDays")
        return v >= 0 ? v : 7
    }

    // MARK: - 保存任务锁
    private var isSaving = false

    // MARK: - 公开方法

    /// 切后台：完整保存当前网页
    func saveOnBackground(webView: WKWebView?) {
        guard autoSaveOnBackground else { return }
        saveCurrentPage(webView: webView, saveType: "auto")
    }

    /// 页面跳转：自动保存上一个页面（可选）
    func saveOnNavigate(from webView: WKWebView?) {
        guard autoSaveOnNavigate else { return }
        saveCurrentPage(webView: webView, saveType: "auto")
    }

    /// 进程终止：轻量保存URL+标题（完整资源下次启动补全）
    func savePendingOnTerminate(webView: WKWebView?) {
        guard autoSaveOnBackground else { return }
        guard let webView = webView,
              let url = webView.url,
              url.absoluteString.hasPrefix("http") else { return }

        let title = webView.title ?? url.absoluteString
        addPendingItem(url: url.absoluteString, title: title)
    }

    /// App启动后补全 pending 记录（网络直接下载，不占用当前浏览页面）
    func completePendingSaves() {
        guard completePendingOnLaunch else { return }
        let items = allItems()
        let pendings = items.filter { $0.saveStatus == "pending" }
        guard !pendings.isEmpty, !isSaving else { return }
        for item in pendings {
            savePageFromNetwork(urlString: item.originURL, pageTitle: item.pageTitle, saveType: "auto")
        }
    }

    /// 从网络直接下载网页保存（进程终止兜底补全用）
    func savePageFromNetwork(urlString: String, pageTitle: String, saveType: String, completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: urlString),
              url.absoluteString.hasPrefix("http"),
              !isSaving else {
            completion?(false)
            return
        }
        if saveType == "auto" && isURLRecentlySaved(urlString) {
            completion?(false)
            return
        }
        if saveType == "auto" && !hasEnoughFreeSpace() {
            logEvent("空间不足，暂停网络保存")
            completion?(false)
            return
        }

        isSaving = true
        let uuid = UUID().uuidString

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
            guard let self = self, let data = data, let html = String(data: data, encoding: .utf8) else {
                self?.isSaving = false
                completion?(false)
                return
            }
            DispatchQueue.global(qos: .utility).async {
                let ok = self.saveHTMLPage(uuid: uuid, html: html, originURL: urlString, pageTitle: pageTitle, saveType: saveType)
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.logEvent("启动补全保存\(ok ? "成功" : "失败"): \(urlString)")
                    completion?(ok)
                }
            }
        }.resume()
    }

    /// 完整保存当前网页
    func saveCurrentPage(webView: WKWebView?, saveType: String, completion: ((Bool) -> Void)? = nil) {
        guard let webView = webView,
              let url = webView.url,
              url.absoluteString.hasPrefix("http"),
              !isSaving else {
            completion?(false)
            return
        }

        // 去重：同URL在去重周期内已保存则跳过
        if saveType == "auto" && isURLRecentlySaved(url.absoluteString) {
            completion?(false)
            return
        }

        // 空间保护：剩余空间低于阈值暂停自动保存
        if saveType == "auto" && !hasEnoughFreeSpace() {
            logEvent("空间不足，暂停自动保存")
            completion?(false)
            return
        }

        isSaving = true
        let uuid = UUID().uuidString
        let originURL = url.absoluteString

        // 通过 evaluateJavaScript 获取渲染后的完整 HTML
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
            guard let self = self else { return }
            guard let html = result as? String else {
                self.isSaving = false
                completion?(false)
                return
            }

            let pageTitle = webView.title ?? originURL
            DispatchQueue.global(qos: .utility).async {
                let ok = self.saveHTMLPage(uuid: uuid, html: html, originURL: originURL, pageTitle: pageTitle, saveType: saveType)
                DispatchQueue.main.async {
                    self.isSaving = false
                    self.logEvent("\(saveType == "manual" ? "手动" : "自动")保存\(ok ? "成功" : "失败"): \(originURL)")
                    completion?(ok)
                }
            }
        }
    }

    // MARK: - 核心保存逻辑

    private func saveHTMLPage(uuid: String, html: String, originURL: String, pageTitle: String, saveType: String) -> Bool {
        do {
            try fileManager.createDirectory(at: itemsDir, withIntermediateDirectories: true)
            let itemDir = itemsDir.appendingPathComponent(uuid, isDirectory: true)
            let assetsDir = itemDir.appendingPathComponent("assets", isDirectory: true)
            try fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)

            // 解析并下载资源
            let (newHTML, assetCount) = downloadAndRewriteAssets(html: html, originURL: originURL, assetsDir: assetsDir, uuid: uuid)

            // 写入 index.html
            try newHTML.write(to: itemDir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

            // 写入 manifest.json
            let manifest: [String: Any] = [
                "url": originURL,
                "title": pageTitle,
                "savedAt": Date().timeIntervalSince1970,
                "assets": assetCount
            ]
            let jsonData = try JSONSerialization.data(withJSONObject: manifest, options: .prettyPrinted)
            try jsonData.write(to: itemDir.appendingPathComponent("manifest.json"))

            // 更新索引
            let item = OfflineItem(
                uuid: uuid,
                pageTitle: pageTitle,
                originURL: originURL,
                saveTimestamp: Date().timeIntervalSince1970,
                saveType: saveType,
                isProtected: true,
                saveStatus: "completed"
            )
            addItemToIndex(item)

            // 自动保存数量上限：先进先出淘汰最旧的auto
            if saveType == "auto" {
                enforceAutoItemLimit()
            }
            return true
        } catch {
            return false
        }
    }

    /// 解析HTML中的资源引用并下载到本地，返回重写后的HTML
    private func downloadAndRewriteAssets(html: String, originURL: String, assetsDir: URL, uuid: String) -> (String, Int) {
        guard let baseURL = URL(string: originURL) else { return (html, 0) }
        var newHTML = html
        var count = 0

        // 匹配 <img src="...">, <script src="...">, <link href="...">, srcset
        let patterns: [(String, String)] = [
            ("src=\"([^\"]+)\"", "src"),
            ("href=\"([^\"]+)\"", "href")
        ]

        for (pattern, attr) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsRange = NSRange(newHTML.startIndex..<newHTML.endIndex, in: newHTML)
            let matches = regex.matches(in: newHTML, range: nsRange)

            // 从后往前替换，避免偏移问题
            for match in matches.reversed() {
                guard let urlRange = Range(match.range(at: 1), in: newHTML) else { continue }
                let resourceURLString = String(newHTML[urlRange])
                guard resourceURLString.hasPrefix("http") || resourceURLString.hasPrefix("//") else { continue }

                let absolute: URL
                if resourceURLString.hasPrefix("//") {
                    absolute = URL(string: "https:" + resourceURLString) ?? baseURL
                } else {
                    absolute = URL(string: resourceURLString, relativeTo: baseURL)?.absoluteURL ?? baseURL
                }

                guard absolute.host != nil else { continue }

                // 下载资源
                if let localName = downloadAsset(url: absolute, assetsDir: assetsDir, uuid: uuid) {
                    let ext = localName
                    let replacement = "\(attr)=\"assets/\(ext)\""
                    if let r = Range(match.range, in: newHTML) {
                        newHTML.replaceSubrange(r, with: replacement)
                        count += 1
                    }
                }
            }
        }
        return (newHTML, count)
    }

    /// 下载单个资源到本地，返回本地文件名
    private func downloadAsset(url: URL, assetsDir: URL, uuid: String) -> String? {
        // 同步下载（在后台线程执行）
        let semaphore = DispatchSemaphore(value: 0)
        var localName: String? = nil
        var localData: Data? = nil

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data = data, data.count > 0 {
                localData = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 5)

        guard let data = localData else { return nil }
        // 生成本地文件名
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let safeName = "\(abs(url.absoluteString.hashValue))\(UUID().uuidString.prefix(4)).\(ext)"
        let fileURL = assetsDir.appendingPathComponent(safeName)
        do {
            try data.write(to: fileURL)
            localName = safeName
        } catch {
            localName = nil
        }
        return localName
    }

    // MARK: - 索引管理

    private func addItemToIndex(_ item: OfflineItem) {
        var items = allItems()
        items.append(item)
        saveItems(items)
    }

    func allItems() -> [OfflineItem] {
        guard let data = try? Data(contentsOf: indexPath) else { return [] }
        let decoder = PropertyListDecoder()
        return (try? decoder.decode([OfflineItem].self, from: data)) ?? []
    }

    private func saveItems(_ items: [OfflineItem]) {
        let encoder = PropertyListEncoder()
        guard let data = try? encoder.encode(items) else { return }
        try? fileManager.createDirectory(at: offlineRoot, withIntermediateDirectories: true)
        try? data.write(to: indexPath)
    }

    /// 删除离线网页（解除保护并删除文件）
    func deleteItem(uuid: String) -> Bool {
        var items = allItems()
        items.removeAll { $0.uuid == uuid }
        saveItems(items)
        let itemDir = itemsDir.appendingPathComponent(uuid, isDirectory: true)
        try? fileManager.removeItem(at: itemDir)
        return true
    }

    /// 打开离线网页：返回本地 index.html 的 URL
    func localURL(for item: OfflineItem) -> URL? {
        let fileURL = itemsDir.appendingPathComponent(item.uuid, isDirectory: true).appendingPathComponent("index.html")
        return fileManager.fileExists(atPath: fileURL.path) ? fileURL : nil
    }

    /// 四级缓存总大小
    func totalSize() -> Int64 {
        folderSize(atPath: offlineRoot.path)
    }

    /// 轻量保存 pending 记录（进程终止兜底）
    private func addPendingItem(url: String, title: String) {
        guard !isURLRecentlySaved(url) else { return }
        let item = OfflineItem(
            uuid: UUID().uuidString,
            pageTitle: title,
            originURL: url,
            saveTimestamp: Date().timeIntervalSince1970,
            saveType: "auto",
            isProtected: true,
            saveStatus: "pending"
        )
        var items = allItems()
        items.append(item)
        saveItems(items)
    }

    /// pending 记录补全为 completed（WebView加载完成后调用）
    func markPendingCompleted(uuid: String) {
        var items = allItems()
        for i in items.indices where items[i].uuid == uuid {
            items[i].saveStatus = "completed"
        }
        saveItems(items)
    }

    // MARK: - 策略辅助

    private func isURLRecentlySaved(_ url: String) -> Bool {
        let dedupDays = urlDedupDays
        guard dedupDays > 0 else { return false }
        let cutoff = Date().timeIntervalSince1970 - Double(dedupDays) * 86400
        return allItems().contains { $0.originURL == url && $0.saveTimestamp > cutoff }
    }

    private func hasEnoughFreeSpace() -> Bool {
        let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
        let free = attrs?[.systemFreeSize] as? Int64 ?? 0
        let threshold = Int64(spaceThresholdGB * 1024 * 1024 * 1024)
        return free > threshold
    }

    private func enforceAutoItemLimit() {
        var items = allItems()
        let autoItems = items.filter { $0.saveType == "auto" }
        if autoItems.count > maxAutoItems {
            // 按时间升序排序，删除最旧的
            let sorted = autoItems.sorted { $0.saveTimestamp < $1.saveTimestamp }
            let toRemove = sorted.prefix(autoItems.count - maxAutoItems)
            for item in toRemove {
                deleteItem(uuid: item.uuid)
            }
        }
    }

    private func folderSize(atPath path: String) -> Int64 {
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
        var size: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                size += attrs[.size] as? Int64 ?? 0
            }
        }
        return size
    }

    // MARK: - 日志
    private let logKey = "offlineSaveLog"

    private func logEvent(_ message: String) {
        var logs = UserDefaults.standard.stringArray(forKey: logKey) ?? []
        logs.append("[\(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium))] \(message)")
        if logs.count > 50 { logs.removeFirst(logs.count - 50) }
        UserDefaults.standard.set(logs, forKey: logKey)
    }

    func saveLog() -> [String] {
        UserDefaults.standard.stringArray(forKey: logKey) ?? []
    }

    /// 存储空间占比（供缓存页面显示）
    var freeSpaceInfo: (total: Int64, free: Int64) {
        let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
        let total = attrs?[.systemSize] as? Int64 ?? 0
        let free = attrs?[.systemFreeSize] as? Int64 ?? 0
        return (total, free)
    }
}
