//
//  TranslateManager.swift
//  轻量浏览器 - JS离线英译中翻译管理器
//
//  功能：
//  - 加载内置英译中词库
//  - 生成JS翻译脚本并注入WKWebView
//  - 翻译结果缓存到四级离线缓存
//  - 混合模式：文字离线翻译 + 图片在线翻译（复用原有百度接口）
//

import UIKit
import WebKit

class TranslateManager {

    static let shared = TranslateManager()

    private var dictionary: [String: String] = [:]
    private var isDictionaryLoaded = false

    // MARK: - 翻译模式
    enum TranslateMode: String {
        case hybrid = "hybrid"      // 混合：文字离线+图片在线
        case online = "online"      // 传统在线翻译
    }

    var currentMode: TranslateMode {
        let mode = UserDefaults.standard.string(forKey: "translateMode") ?? "hybrid"
        return TranslateMode(rawValue: mode) ?? .hybrid
    }

    func setMode(_ mode: TranslateMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "translateMode")
    }

    // MARK: - 加载词库
    func loadDictionaryIfNeeded() {
        guard !isDictionaryLoaded else { return }
        guard let path = Bundle.main.path(forResource: "en_zh_dict", ofType: "json"),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return
        }
        dictionary = dict
        isDictionaryLoaded = true
    }

    // MARK: - 生成JS翻译脚本
    private func generateTranslateScript() -> String {
        loadDictionaryIfNeeded()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dictionary),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }

        // JS脚本：遍历DOM文本节点，用词库替换翻译
        let script = """
        (function() {
            if (window.__translated__) return;
            window.__translated__ = true;
            const dict = \(jsonString);
            function translateText(text) {
                if (!text || !text.trim()) return text;
                // 跳过纯数字、纯符号
                if (/^[\\d\\s\\W]+$/.test(text)) return text;
                // 跳过中文为主的文本
                if (/[\\u4e00-\\u9fa5]/.test(text) && text.replace(/[\\u4e00-\\u9fa5]/g, '').length < text.length * 0.3) return text;
                let result = text;
                // 按词长度降序匹配，避免短词先替换
                const keys = Object.keys(dict).sort((a, b) => b.length - a.length);
                for (const key of keys) {
                    const escaped = key.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                    const regex = new RegExp('\\\\b' + escaped + '\\\\b', 'gi');
                    result = result.replace(regex, dict[key]);
                }
                return result;
            }
            function walk(node) {
                if (node.nodeType === 3) {
                    const text = node.textContent;
                    if (text && text.trim() && /[a-zA-Z]/.test(text)) {
                        node.textContent = translateText(text);
                    }
                } else if (node.nodeType === 1) {
                    const tag = node.tagName;
                    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'CODE' || tag === 'PRE') return;
                    if (node.alt) node.alt = translateText(node.alt);
                    if (node.placeholder) node.placeholder = translateText(node.placeholder);
                    if (node.title) node.title = translateText(node.title);
                    if (node.value && (tag === 'INPUT' || tag === 'BUTTON')) node.value = translateText(node.value);
                    for (let i = 0; i < node.childNodes.length; i++) {
                        walk(node.childNodes[i]);
                    }
                }
            }
            walk(document.body);
            // 记录翻译状态
            document.documentElement.setAttribute('data-translated', 'true');
        })();
        """
        return script
    }

    // MARK: - 执行离线文字翻译
    func translatePageOffline(webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        let script = generateTranslateScript()
        guard !script.isEmpty else {
            completion?(false)
            return
        }
        webView.evaluateJavaScript(script) { _, error in
            completion?(error == nil)
        }
    }

    // MARK: - 还原原文
    func restoreOriginal(webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        let script = """
        (function() {
            if (window.__translated__) {
                window.__translated__ = false;
                document.documentElement.removeAttribute('data-translated');
                location.reload();
            }
        })();
        """
        webView.evaluateJavaScript(script) { _, error in
            completion?(error == nil)
        }
    }

    // MARK: - 翻译缓存（四级离线缓存联动）
    func saveTranslationCache(forURL url: String, translations: [String: String]) {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? ""
        let translateDir = (cacheDir as NSString).appendingPathComponent("CacheManager/Level4_Offline/translate_cache")
        let fileManager = FileManager.default
        try? fileManager.createDirectory(atPath: translateDir, withIntermediateDirectories: true)

        let safeName = url.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: ".", with: "_")
        let filePath = (translateDir as NSString).appendingPathComponent("\(safeName).json")

        let cacheData: [String: Any] = [
            "url": url,
            "timestamp": Date().timeIntervalSince1970,
            "translations": translations
        ]
        if let data = try? JSONSerialization.data(withJSONObject: cacheData, options: .prettyPrinted) {
            try? data.write(to: URL(fileURLWithPath: filePath))
        }
    }

    func loadTranslationCache(forURL url: String) -> [String: String]? {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? ""
        let translateDir = (cacheDir as NSString).appendingPathComponent("CacheManager/Level4_Offline/translate_cache")
        let safeName = url.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: ".", with: "_")
        let filePath = (translateDir as NSString).appendingPathComponent("\(safeName).json")

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: filePath)),
              let cache = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let translations = cache["translations"] as? [String: String] else {
            return nil
        }
        return translations
    }

    func clearAllTranslationCache() {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? ""
        let translateDir = (cacheDir as NSString).appendingPathComponent("CacheManager/Level4_Offline/translate_cache")
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: translateDir)
        try? fileManager.createDirectory(atPath: translateDir, withIntermediateDirectories: true)
    }

    func translationCacheSize() -> Int64 {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true).first ?? ""
        let translateDir = (cacheDir as NSString).appendingPathComponent("CacheManager/Level4_Offline/translate_cache")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(atPath: translateDir) else { return 0 }
        var size: Int64 = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = (translateDir as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath) {
                size += attrs[.size] as? Int64 ?? 0
            }
        }
        return size
    }
}
