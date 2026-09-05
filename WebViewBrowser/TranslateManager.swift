//
//  TranslateManager.swift
//  轻量浏览器 - JS离线英译中翻译管理器（v16.4重构版）
//
//  功能：
//  - 加载内置通用英译中词库 + GitHub专用词库
//  - 三套翻译入口：本地翻译 / 在线翻译 / 混合翻译
//  - 域名智能识别，GitHub站点自动合并专用词库
//  - 异常容错，词典加载失败使用内置兜底词条
//  - 翻译结果缓存到四级离线缓存
//

import UIKit
import WebKit

class TranslateManager {

    static let shared = TranslateManager()

    private var generalDictionary: [String: String] = [:]
    private var githubDictionary: [String: String] = [:]
    private var isGeneralLoaded = false
    private var isGithubLoaded = false

    // 内置兜底高频词条（JSON加载失败时使用）
    private let fallbackDict: [String: String] = [
        "home": "首页", "back": "返回", "forward": "前进", "refresh": "刷新",
        "search": "搜索", "submit": "提交", "cancel": "取消", "ok": "确定",
        "save": "保存", "delete": "删除", "edit": "编辑", "add": "添加",
        "close": "关闭", "open": "打开", "download": "下载", "upload": "上传",
        "login": "登录", "logout": "退出登录", "register": "注册", "next": "下一步",
        "previous": "上一步", "continue": "继续", "confirm": "确认", "settings": "设置",
        "help": "帮助", "about": "关于", "menu": "菜单", "profile": "个人资料",
        "notification": "通知", "message": "消息", "favorite": "收藏", "history": "历史记录",
        "loading": "加载中", "success": "成功", "error": "错误", "warning": "警告",
        "failed": "失败", "completed": "已完成", "pending": "待处理", "update": "更新",
        "create": "创建", "send": "发送", "share": "分享", "copy": "复制",
        "paste": "粘贴", "cut": "剪切", "print": "打印", "welcome": "欢迎",
        "hello": "你好", "thank you": "谢谢", "please": "请", "sorry": "抱歉",
        "repository": "仓库", "star": "标星", "fork": "复刻", "commit": "提交",
        "issue": "议题", "pull request": "合并请求", "release": "版本发布",
        "branch": "分支", "clone": "克隆", "watch": "关注", "code": "代码",
        "actions": "工作流", "wiki": "维基文档", "discussion": "讨论"
    ]

    // MARK: - 翻译模式
    enum TranslateMode: String {
        case local = "local"        // 仅本地翻译
        case online = "online"      // 仅在线翻译
        case mixed = "mixed"        // 混合翻译（默认）
    }

    var currentMode: TranslateMode {
        let mode = UserDefaults.standard.string(forKey: "translateMode") ?? "mixed"
        return TranslateMode(rawValue: mode) ?? .mixed
    }

    func setMode(_ mode: TranslateMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "translateMode")
    }

    // MARK: - 加载词库
    func loadGeneralDictionary() -> [String: String] {
        if isGeneralLoaded && !generalDictionary.isEmpty {
            return generalDictionary
        }
        if let path = Bundle.main.path(forResource: "en_zh_dict", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            generalDictionary = dict
            isGeneralLoaded = true
            print("[TranslateManager] 通用词库加载成功，词条数: \(dict.count)")
        } else {
            print("[TranslateManager] 通用词库加载失败，使用兜底词条")
            generalDictionary = fallbackDict
            isGeneralLoaded = true
        }
        return generalDictionary
    }

    func loadGithubDictionary() -> [String: String] {
        if isGithubLoaded {
            return githubDictionary
        }
        if let path = Bundle.main.path(forResource: "github_dict", ofType: "json"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            githubDictionary = dict
            isGithubLoaded = true
            print("[TranslateManager] GitHub词库加载成功，词条数: \(dict.count)")
        } else {
            print("[TranslateManager] GitHub词库加载失败")
            githubDictionary = [:]
            isGithubLoaded = true
        }
        return githubDictionary
    }

    // 判断是否为GitHub站点
    func isGithubSite(url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host.contains("github.com") || host.contains("githubusercontent.com") || host.contains("github.io")
    }

    // 获取合并后的词库（GitHub站点合并专用词库）
    func getMergedDictionary(for url: URL?) -> [String: String] {
        var dict = loadGeneralDictionary()
        if isGithubSite(url: url) {
            let ghDict = loadGithubDictionary()
            for (key, value) in ghDict {
                dict[key] = value
            }
            print("[TranslateManager] GitHub站点，合并后词条数: \(dict.count)")
        }
        return dict
    }

    // MARK: - 生成JS翻译脚本（重构版：递归遍历Text节点）
    private func generateTranslateScript(dictionary: [String: String]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dictionary),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }

        let script = """
        (function() {
            try {
                if (window.__browser_translated__) return {success: true, already: true};
                if (document.readyState !== 'complete') {
                    return {success: false, reason: 'not_ready'};
                }
                window.__browser_translated__ = true;
                const dict = \(jsonString);
                const skipTags = {'SCRIPT':1,'STYLE':1,'NOSCRIPT':1,'SVG':1,'CODE':1,'PRE':1,'TEXTAREA':1,'INPUT':1,'SELECT':1,'OPTION':1,'IFRAME':1,'CANVAS':1};
                function translateText(text) {
                    if (!text || !text.trim()) return text;
                    if (/^[\\d\\s\\W]+$/.test(text)) return text;
                    const chineseCount = (text.match(/[\\u4e00-\\u9fa5]/g) || []).length;
                    if (chineseCount > text.length * 0.4) return text;
                    if (text.trim().length > 200) return text;
                    let result = text;
                    const keys = Object.keys(dict).sort((a, b) => b.length - a.length);
                    for (const key of keys) {
                        try {
                            const escaped = key.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                            const regex = new RegExp('\\\\b' + escaped + '\\\\b', 'gi');
                            result = result.replace(regex, dict[key]);
                        } catch(e) {}
                    }
                    return result;
                }
                function walk(node) {
                    if (!node) return;
                    if (node.nodeType === 3) {
                        const text = node.textContent;
                        if (text && text.trim() && /[a-zA-Z]/.test(text)) {
                            if (!node.parentNode || !node.parentNode.getAttribute) {
                                node.textContent = translateText(text);
                            } else if (!node.parentNode.getAttribute('data-translated')) {
                                node.textContent = translateText(text);
                            }
                        }
                    } else if (node.nodeType === 1) {
                        const tag = node.tagName;
                        if (skipTags[tag]) return;
                        if (node.getAttribute && node.getAttribute('data-translated')) return;
                        if (node.alt) node.alt = translateText(node.alt);
                        if (node.placeholder) node.placeholder = translateText(node.placeholder);
                        if (node.title) node.title = translateText(node.title);
                        if (node.value && (tag === 'INPUT' || tag === 'BUTTON')) node.value = translateText(node.value);
                        if (node.setAttribute) node.setAttribute('data-translated', '1');
                        const children = node.childNodes;
                        for (let i = 0; i < children.length; i++) {
                            walk(children[i]);
                        }
                    }
                }
                walk(document.body);
                document.documentElement.setAttribute('data-translated', 'true');
                return {success: true};
            } catch(e) {
                return {success: false, reason: 'exception: ' + e.message};
            }
        })();
        """
        return script
    }

    // MARK: - 本地翻译（仅JS词库，无自动降级）
    func translateLocalOnly(webView: WKWebView, completion: @escaping (Bool, String?) -> Void) {
        let dict = getMergedDictionary(for: webView.url)
        let script = generateTranslateScript(dictionary: dict)
        guard !script.isEmpty else {
            completion(false, "脚本生成失败")
            return
        }

        let checkReady = "(function(){ return document.readyState; })()"
        webView.evaluateJavaScript(checkReady) { [weak self] result, error in
            guard let self = self else { return }
            let readyState = result as? String ?? "unknown"
            if readyState != "complete" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.executeLocalScript(webView: webView, script: script, completion: completion)
                }
            } else {
                self.executeLocalScript(webView: webView, script: script, completion: completion)
            }
        }
    }

    private func executeLocalScript(webView: WKWebView, script: String, completion: @escaping (Bool, String?) -> Void) {
        webView.evaluateJavaScript(script) { result, error in
            if let error = error {
                completion(false, "JS执行异常: \(error.localizedDescription)")
                return
            }
            if let dict = result as? [String: Any] {
                let success = dict["success"] as? Bool ?? false
                let reason = dict["reason"] as? String
                if success {
                    completion(true, nil)
                } else if reason == "not_ready" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        webView.evaluateJavaScript(script) { result2, error2 in
                            if let error2 = error2 {
                                completion(false, "JS执行异常: \(error2.localizedDescription)")
                            } else {
                                let dict2 = result2 as? [String: Any]
                                let s2 = dict2?["success"] as? Bool ?? false
                                completion(s2, s2 ? nil : (dict2?["reason"] as? String ?? "未知错误"))
                            }
                        }
                    }
                } else {
                    completion(false, reason ?? "翻译失败")
                }
            } else {
                completion(false, "返回格式异常")
            }
        }
    }

    // MARK: - 混合翻译（本地优先，失败自动降级在线）
    func translateMixed(webView: WKWebView, onlineFallback: @escaping () -> Void, completion: @escaping (Bool, String?) -> Void) {
        translateLocalOnly(webView: webView) { success, reason in
            if success {
                completion(true, nil)
            } else {
                print("[TranslateManager] 本地翻译失败(\(reason ?? "未知"))，降级在线翻译")
                onlineFallback()
                completion(false, "已降级在线翻译")
            }
        }
    }

    // MARK: - 还原原文
    func restoreOriginal(webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        let script = """
        (function() {
            if (window.__browser_translated__) {
                window.__browser_translated__ = false;
                document.documentElement.removeAttribute('data-translated');
                location.reload();
                return true;
            }
            return false;
        })();
        """
        webView.evaluateJavaScript(script) { result, error in
            completion?(error == nil)
        }
    }

    // MARK: - 翻译缓存
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
