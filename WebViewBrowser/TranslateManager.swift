//
//  TranslateManager.swift
//  轻量浏览器 - JS离线英译中翻译管理器（v16.7安全版）
//
//  v16.7 修复：
//  - walk改为迭代版（栈遍历），避免深层DOM递归栈溢出导致闪退
//  - 添加翻译节点上限（3000），超大页面分批处理
//  - 所有completion回调统一在主线程执行
//  - 简化重试逻辑，最多重试2次
//  - 添加webView加载状态检查
//

import UIKit
import WebKit

class TranslateManager {

    static let shared = TranslateManager()

    private var generalDictionary: [String: String] = [:]
    private var githubDictionary: [String: String] = [:]
    private var isGeneralLoaded = false
    private var isGithubLoaded = false

    // 内置兜底高频词条
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
        "actions": "工作流", "wiki": "维基文档", "discussion": "讨论",
        "sign in": "登录", "sign up": "注册", "sign out": "退出",
        "explore": "探索", "trending": "趋势", "marketplace": "应用市场",
        "pricing": "价格", "docs": "文档", "support": "支持",
        "new": "新建", "file": "文件", "folder": "文件夹",
        "name": "名称", "description": "描述", "public": "公开", "private": "私有",
        "readme": "说明文档", "license": "许可证", "language": "语言", "topics": "主题"
    ]

    // MARK: - 翻译模式
    enum TranslateMode: String {
        case local = "local"
        case online = "online"
        case mixed = "mixed"
        case alwaysOn = "alwaysOn"  // v16.9 一直开启翻译（默认使用离线翻译）
    }

    var currentMode: TranslateMode {
        let mode = UserDefaults.standard.string(forKey: "translateMode") ?? "mixed"
        return TranslateMode(rawValue: mode) ?? .mixed
    }

    func setMode(_ mode: TranslateMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: "translateMode")
    }

    // v16.9 是否开启自动翻译（一直开启翻译模式）
    var isAutoTranslateEnabled: Bool {
        return currentMode == .alwaysOn
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
            print("[TranslateManager] 通用词库加载失败，使用兜底词条(\(fallbackDict.count)条)")
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
            print("[TranslateManager] GitHub词库加载失败，使用空词库")
            githubDictionary = [:]
            isGithubLoaded = true
        }
        return githubDictionary
    }

    func isGithubSite(url: URL?) -> Bool {
        guard let host = url?.host?.lowercased() else { return false }
        return host.contains("github.com") || host.contains("githubusercontent.com") || host.contains("github.io")
    }

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

    // MARK: - 生成JS翻译脚本（v16.10：MutationObserver动态监听子菜单/SPA内容）
    private func generateTranslateScript(dictionary: [String: String]) -> String {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dictionary),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return ""
        }

        let script = """
        (function() {
            try {
                if (window.__browser_translated__) {
                    return {success: true, already: true, translated: 0};
                }
                if (!document.body) {
                    return {success: false, reason: 'no_body'};
                }
                if (document.readyState === 'loading') {
                    return {success: false, reason: 'page_loading'};
                }
                const dict = \(jsonString);
                const skipTags = {'SCRIPT':1,'STYLE':1,'NOSCRIPT':1,'SVG':1,'CODE':1,'PRE':1,'TEXTAREA':1,'INPUT':1,'SELECT':1,'OPTION':1,'IFRAME':1,'CANVAS':1,'TEMPLATE':1};
                const MAX_NODES = 3000;
                let translatedCount = 0;
                let observer = null;
                let pendingNodes = [];
                let debounceTimer = null;

                function translateText(text) {
                    if (!text || !text.trim()) return text;
                    if (/^[\\d\\s\\W_]+$/.test(text)) return text;
                    const chineseCount = (text.match(/[\\u4e00-\\u9fa5]/g) || []).length;
                    if (chineseCount > text.length * 0.4) return text;
                    if (text.trim().length > 300) return text;
                    let result = text;
                    const keys = Object.keys(dict);
                    keys.sort(function(a, b) { return b.length - a.length; });
                    for (let i = 0; i < keys.length; i++) {
                        try {
                            const key = keys[i];
                            if (!key || key.length < 2) continue;
                            const escaped = key.replace(/[.*+?^${}()|[\\]\\\\]/g, '\\\\$&');
                            const regex = new RegExp('\\\\b' + escaped + '\\\\b', 'gi');
                            result = result.replace(regex, dict[key]);
                        } catch(e) {}
                    }
                    return result;
                }

                function translateNode(node) {
                    if (!node) return;
                    if (node.nodeType === 3) {
                        const text = node.textContent;
                        if (text && text.trim() && /[a-zA-Z]/.test(text)) {
                            const newText = translateText(text);
                            if (newText !== text) {
                                node.textContent = newText;
                                translatedCount++;
                            }
                        }
                        return;
                    }
                    if (node.nodeType === 1) {
                        const tag = node.tagName;
                        if (skipTags[tag]) return;
                        try {
                            if (node.alt) {
                                const newAlt = translateText(node.alt);
                                if (newAlt !== node.alt) { node.alt = newAlt; translatedCount++; }
                            }
                            if (node.placeholder) {
                                const newPh = translateText(node.placeholder);
                                if (newPh !== node.placeholder) { node.placeholder = newPh; translatedCount++; }
                            }
                            if (node.title) {
                                const newTitle = translateText(node.title);
                                if (newTitle !== node.title) { node.title = newTitle; translatedCount++; }
                            }
                            if (node.value && (tag === 'INPUT' || tag === 'BUTTON')) {
                                const newVal = translateText(node.value);
                                if (newVal !== node.value) { node.value = newVal; translatedCount++; }
                            }
                        } catch(e) {}
                    }
                }

                // 迭代版遍历（使用栈，避免递归栈溢出）
                function translateSubtree(root) {
                    if (!root) return;
                    const stack = [root];
                    let nodeCount = 0;
                    while (stack.length > 0 && nodeCount < MAX_NODES) {
                        const node = stack.pop();
                        if (!node) continue;
                        nodeCount++;
                        translateNode(node);
                        if (node.nodeType === 1 && node.childNodes) {
                            const tag = node.tagName;
                            if (!skipTags[tag]) {
                                const children = node.childNodes;
                                for (let i = children.length - 1; i >= 0; i--) {
                                    if (children[i].nodeType === 1 || children[i].nodeType === 3) {
                                        stack.push(children[i]);
                                    }
                                }
                            }
                        }
                    }
                }

                // v16.10 防抖处理动态节点翻译
                function flushPendingTranslations() {
                    if (pendingNodes.length === 0) return;
                    const nodes = pendingNodes;
                    pendingNodes = [];
                    for (let i = 0; i < nodes.length; i++) {
                        try {
                            translateSubtree(nodes[i]);
                        } catch(e) {}
                    }
                }

                function scheduleTranslation(node) {
                    if (!node) return;
                    pendingNodes.push(node);
                    if (debounceTimer) clearTimeout(debounceTimer);
                    debounceTimer = setTimeout(flushPendingTranslations, 150);
                }

                // v16.10 启动MutationObserver监听动态内容（子菜单、SPA路由变化等）
                function startObserver() {
                    if (observer) return;
                    try {
                        observer = new MutationObserver(function(mutations) {
                            for (let i = 0; i < mutations.length; i++) {
                                const mutation = mutations[i];
                                if (mutation.type === 'childList') {
                                    const added = mutation.addedNodes;
                                    for (let j = 0; j < added.length; j++) {
                                        const node = added[j];
                                        if (node.nodeType === 1 || node.nodeType === 3) {
                                            scheduleTranslation(node);
                                        }
                                    }
                                } else if (mutation.type === 'characterData') {
                                    const node = mutation.target;
                                    if (node.nodeType === 3) {
                                        const text = node.textContent;
                                        if (text && text.trim() && /[a-zA-Z]/.test(text)) {
                                            const newText = translateText(text);
                                            if (newText !== text) {
                                                node.textContent = newText;
                                                translatedCount++;
                                            }
                                        }
                                    }
                                }
                            }
                        });
                        observer.observe(document.body, {
                            childList: true,
                            subtree: true,
                            characterData: true,
                            characterDataOldValue: false
                        });
                        window.__browser_translate_observer__ = observer;
                    } catch(e) {
                        console.warn('MutationObserver启动失败:', e);
                    }
                }

                // 初始全量翻译
                translateSubtree(document.body);

                try {
                    document.documentElement.setAttribute('data-translated', 'true');
                } catch(e) {}

                if (translatedCount > 0) {
                    window.__browser_translated__ = true;
                }

                // v16.10 启动动态监听，确保子菜单展开后自动翻译
                startObserver();

                return {success: true, translated: translatedCount, observer: true};
            } catch(e) {
                return {success: false, reason: 'exception: ' + e.message};
            }
        })();
        """
        return script
    }

    // MARK: - 本地翻译（安全版）
    func translateLocalOnly(webView: WKWebView, completion: @escaping (Bool, String?) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.translateLocalOnly(webView: webView, completion: completion)
            }
            return
        }

        let dict = getMergedDictionary(for: webView.url)
        let script = generateTranslateScript(dictionary: dict)
        guard !script.isEmpty else {
            DispatchQueue.main.async { completion(false, "脚本生成失败") }
            return
        }

        print("[TranslateManager] 开始本地翻译，词库\(dict.count)条")
        executeScript(webView: webView, script: script, attempts: 2, interval: 0.6, completion: completion)
    }

    private func executeScript(webView: WKWebView, script: String, attempts: Int, interval: TimeInterval, completion: @escaping (Bool, String?) -> Void) {
        webView.evaluateJavaScript(script) { result, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[TranslateManager] JS执行异常: \(error.localizedDescription)")
                    if attempts > 0 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                            self?.executeScript(webView: webView, script: script, attempts: attempts - 1, interval: interval, completion: completion)
                        }
                    } else {
                        completion(false, "JS执行异常: \(error.localizedDescription)")
                    }
                    return
                }

                guard let dict = result as? [String: Any] else {
                    print("[TranslateManager] 返回格式异常: \(String(describing: result))")
                    completion(false, "返回格式异常")
                    return
                }

                let success = dict["success"] as? Bool ?? false
                let reason = dict["reason"] as? String
                let translated = dict["translated"] as? Int ?? 0
                let already = dict["already"] as? Bool ?? false

                if already {
                    print("[TranslateManager] 页面已翻译过")
                    completion(true, "页面已翻译过")
                    return
                }

                if success {
                    print("[TranslateManager] 本地翻译成功，翻译了\(translated)处文本")
                    completion(true, "翻译了\(translated)处文本")
                    return
                }

                if (reason == "page_loading" || reason == "no_body") && attempts > 0 {
                    print("[TranslateManager] 页面未就绪(\(reason ?? ""))，\(interval)秒后重试（剩余\(attempts)次）")
                    DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                        self?.executeScript(webView: webView, script: script, attempts: attempts - 1, interval: interval, completion: completion)
                    }
                    return
                }

                print("[TranslateManager] 本地翻译失败: \(reason ?? "未知")")
                completion(false, reason ?? "翻译失败")
            }
        }
    }

    // MARK: - 混合翻译（本地优先，失败降级在线）
    func translateMixed(webView: WKWebView, onlineFallback: @escaping () -> Void, completion: @escaping (Bool, String?) -> Void) {
        translateLocalOnly(webView: webView) { success, reason in
            if success {
                completion(true, reason)
            } else {
                print("[TranslateManager] 本地翻译失败(\(reason ?? "未知"))，降级在线翻译")
                onlineFallback()
                completion(false, "已降级在线翻译")
            }
        }
    }

    // MARK: - 还原原文
    func restoreOriginal(webView: WKWebView, completion: ((Bool) -> Void)? = nil) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.restoreOriginal(webView: webView, completion: completion)
            }
            return
        }
        let script = """
        (function() {
            try {
                // v16.10 停止MutationObserver，避免还原后又被自动翻译
                if (window.__browser_translate_observer__) {
                    try { window.__browser_translate_observer__.disconnect(); } catch(e) {}
                    window.__browser_translate_observer__ = null;
                }
                if (window.__browser_translated__) {
                    window.__browser_translated__ = false;
                    document.documentElement.removeAttribute('data-translated');
                    location.reload();
                    return true;
                }
                return false;
            } catch(e) {
                return false;
            }
        })();
        """
        webView.evaluateJavaScript(script) { _, error in
            DispatchQueue.main.async {
                completion?(error == nil)
            }
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
