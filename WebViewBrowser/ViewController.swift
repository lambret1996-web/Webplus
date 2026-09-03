import UIKit
import WebKit
class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    // MARK: - 配置项
    /// 两个窗口的默认页面
    private let windowURLs: [String] = [
        "https://github.com",
        "https://dash.cloudflare.com/"
    ]
    /// 窗口标签默认名称
    private let windowTitles: [String] = ["窗口一", "窗口二"]
    /// 标签栏高度
    private let tabBarHeight: CGFloat = 44
    /// 翻译按钮宽度
    private let translateButtonWidth: CGFloat = 52
    /// 单次翻译最大文本段数（防止超大页面内存溢出）
    private let maxTranslateSegments = 5000
    // MARK: - UI 组件
    private var tabBar: UIView!
    private var tabButtons: [UIButton] = []
    private var tabIndicator: UIView!
    private var translateButton: UIButton!
    private var webViews: [WKWebView] = []
    private var webViewContainer: UIView!
    private var progressView: UIProgressView!
    private var refreshControls: [UIRefreshControl] = []
    private var panGestures: [UIPanGestureRecognizer] = []
    /// 当前激活的窗口索引
    private var activeIndex: Int = 0
    // MARK: - 手势相关
    private var gestureStartPoint: CGPoint = .zero
    private var gestureStartDate: Date = .init()
    private let gestureThreshold: CGFloat = 80
    private let gestureMaxDuration: TimeInterval = 0.5
    // MARK: - 翻译相关
    private var isTranslated: [Bool] = [false, false]
    private var isTranslating = false
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupTabBar()
        setupWebViewContainer()
        setupWebViews()
        setupProgressView()
        setupRefreshControls()
        setupGestures()
        switchToTab(index: 0)
        loadInitialPages()
    }
    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
    // MARK: - 标签栏
    private func setupTabBar() {
        tabBar = UIView()
        tabBar.backgroundColor = .systemGray6
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: tabBarHeight)
        ])
        // 翻译按钮（右侧）
        translateButton = UIButton(type: .system)
        translateButton.setTitle("译", for: .normal)
        translateButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        translateButton.backgroundColor = .systemBlue
        translateButton.setTitleColor(.white, for: .normal)
        translateButton.layer.cornerRadius = 8
        translateButton.translatesAutoresizingMaskIntoConstraints = false
        translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
        tabBar.addSubview(translateButton)
        NSLayoutConstraint.activate([
            translateButton.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -8),
            translateButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            translateButton.widthAnchor.constraint(equalToConstant: translateButtonWidth),
            translateButton.heightAnchor.constraint(equalToConstant: 32)
        ])
        // 标签按钮容器
        let tabsStack = UIStackView()
        tabsStack.axis = .horizontal
        tabsStack.distribution = .fillEqually
        tabsStack.spacing = 4
        tabsStack.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tabsStack)
        NSLayoutConstraint.activate([
            tabsStack.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 8),
            tabsStack.trailingAnchor.constraint(equalTo: translateButton.leadingAnchor, constant: -8),
            tabsStack.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabsStack.heightAnchor.constraint(equalToConstant: 32)
        ])
        for (index, title) in windowTitles.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.tag = index
            button.layer.cornerRadius = 8
            button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabsStack.addArrangedSubview(button)
            tabButtons.append(button)
        }
        // 选中指示条
        tabIndicator = UIView()
        tabIndicator.backgroundColor = .systemBlue
        tabIndicator.layer.cornerRadius = 2
        tabIndicator.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tabIndicator)
    }
    @objc private func tabTapped(_ sender: UIButton) {
        switchToTab(index: sender.tag)
    }
    private func switchToTab(index: Int) {
        activeIndex = index
        for (i, button) in tabButtons.enumerated() {
            if i == index {
                button.backgroundColor = .systemBackground
                button.setTitleColor(.label, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            } else {
                button.backgroundColor = .clear
                button.setTitleColor(.secondaryLabel, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
            }
        }
        // 切换 WebView 显示
        for (i, webView) in webViews.enumerated() {
            webView.isHidden = (i != index)
        }
        // 更新进度条
        updateProgressView()
        // 更新翻译按钮状态
        updateTranslateButtonState()
    }
    private func updateTabTitle(index: Int, title: String) {
        guard index < tabButtons.count else { return }
        let displayTitle = title.count > 8 ? String(title.prefix(8)) + "…" : title
        tabButtons[index].setTitle(displayTitle, for: .normal)
    }
    // MARK: - WebView 容器
    private func setupWebViewContainer() {
        webViewContainer = UIView()
        webViewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webViewContainer)
        NSLayoutConstraint.activate([
            webViewContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            webViewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
    private func setupWebViews() {
        for i in 0..<2 {
            let config = WKWebViewConfiguration()
            config.allowsInlineMediaPlayback = true
            config.mediaTypesRequiringUserActionForPlayback = []
            // 允许在页面中执行 JavaScript（翻译功能需要）
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.allowsBackForwardNavigationGestures = false
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.scrollView.bounces = true
            webView.isHidden = (i != 0)
            webViewContainer.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
                webView.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor)
            ])
            webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
            webViews.append(webView)
        }
    }
    private func loadInitialPages() {
        for (index, urlString) in windowURLs.enumerated() {
            guard let url = URL(string: urlString) else { continue }
            webViews[index].load(URLRequest(url: url))
        }
    }
    private var currentWebView: WKWebView {
        webViews[activeIndex]
    }
    // MARK: - 进度条
    private func setupProgressView() {
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 2)
        ])
    }
    private func updateProgressView() {
        let progress = currentWebView.estimatedProgress
        progressView.progress = Float(progress)
        progressView.isHidden = progress >= 1.0
    }
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(WKWebView.estimatedProgress),
           let webView = object as? WKWebView,
           webView === currentWebView {
            updateProgressView()
        }
    }
    // MARK: - 下拉刷新
    private func setupRefreshControls() {
        for webView in webViews {
            let refresh = UIRefreshControl()
            refresh.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
            webView.scrollView.addSubview(refresh)
            refreshControls.append(refresh)
        }
    }
    @objc private func handleRefresh() {
        currentWebView.reload()
    }
    // MARK: - 手势导航
    private func setupGestures() {
        for webView in webViews {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.cancelsTouchesInView = false
            webView.addGestureRecognizer(pan)
            panGestures.append(pan)
        }
    }
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.view === currentWebView else { return }
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .began:
            gestureStartPoint = location
            gestureStartDate = Date()
        case .ended:
            let elapsed = Date().timeIntervalSince(gestureStartDate)
            let horizontalDistance = translation.x
            let verticalDistance = abs(translation.y)
            guard elapsed <= gestureMaxDuration,
                  abs(horizontalDistance) > gestureThreshold,
                  abs(horizontalDistance) > verticalDistance * 1.5 else {
                return
            }
            if horizontalDistance > 0 {
                if currentWebView.canGoForward {
                    currentWebView.goForward()
                }
            } else {
                if currentWebView.canGoBack {
                    currentWebView.goBack()
                }
            }
        default:
            break
        }
    }
    // MARK: - 全局翻译功能（OperationQueue并发，URLSession.shared，不阻塞主线程）
    @objc private func translateTapped() {
        guard !isTranslating else { return }
        if isTranslated[activeIndex] {
            restoreOriginalText()
        } else {
            startTranslation()
        }
    }
    private func updateTranslateButtonState() {
        if isTranslating {
            translateButton.backgroundColor = .systemGray
            translateButton.setTitle("…", for: .normal)
            translateButton.isEnabled = false
            return
        }
        translateButton.isEnabled = true
        if isTranslated[activeIndex] {
            translateButton.backgroundColor = .systemGreen
            translateButton.setTitle("原", for: .normal)
        } else {
            translateButton.backgroundColor = .systemBlue
            translateButton.setTitle("译", for: .normal)
        }
    }
    /// JS：收集页面待翻译文本（限制最大数量，保存原文），返回JSON
    private var collectTextJS: String {
        let maxSeg = maxTranslateSegments
        return """
        (function() {
            if (window.__browser_translate_active__) return JSON.stringify({error:'already_active'});
            window.__browser_translate_active__ = true;
            var texts = [];
            var count = 0;
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(node) {
                    if (!node.textContent || !node.textContent.trim()) return NodeFilter.FILTER_REJECT;
                    var p = node.parentElement;
                    if (!p) return NodeFilter.FILTER_REJECT;
                    var t = p.tagName.toLowerCase();
                    if (t==='script'||t==='style'||t==='noscript'||t==='textarea'||t==='input'||t==='select'||t==='option'||t==='code'||t==='pre') return NodeFilter.FILTER_REJECT;
                    if (/[\\u4e00-\\u9fa5]/.test(node.textContent)) return NodeFilter.FILTER_REJECT;
                    if (node.textContent.trim().length < 2) return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            var n;
            while ((n = walker.nextNode())) {
                if (count >= \(maxSeg)) break;
                if (!n.__browser_orig_text__) n.__browser_orig_text__ = n.textContent;
                texts.push(n.textContent.trim());
                count++;
            }
            return JSON.stringify({count: texts.length, texts: texts});
        })();
        """
    }
    /// 启动翻译：锁定目标WebView → JS收集文本 → OperationQueue并发翻译 → 分批应用结果
    private func startTranslation() {
        let targetWebView = currentWebView
        let targetIndex = activeIndex

        targetWebView.evaluateJavaScript(collectTextJS) { [weak self] result, error in
            guard let self = self else { return }
            if let error = error {
                print("收集文本失败: \(error.localizedDescription)")
                self.showTranslateToast("翻译启动失败")
                return
            }
            guard let jsonStr = result as? String,
                  let data = jsonStr.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let texts = dict["texts"] as? [String] else {
                self.showTranslateToast("页面无可翻译内容")
                return
            }
            if texts.isEmpty {
                self.isTranslated[targetIndex] = true
                self.updateTranslateButtonState()
                return
            }
            // 标记翻译中
            self.isTranslating = true
            self.isTranslated[targetIndex] = true
            self.updateTranslateButtonState()

            // OperationQueue 并发翻译（后台线程，不阻塞主线程）
            self.translateWithOperationQueue(texts) { [weak self] translations in
                guard let self = self else { return }
                // 一次性应用翻译结果（TreeWalker只遍历一次，在文本修改前完成所有匹配，顺序正确）
                self.applyTranslations(translations, to: targetWebView)
                self.isTranslating = false
                self.updateTranslateButtonState()
            }
        }
    }
    /// OperationQueue 并发翻译：max 5并发，每请求12秒超时，NSLock保护结果数组
    private func translateWithOperationQueue(_ texts: [String], completion: @escaping ([String]) -> Void) {
        let lock = NSLock()
        var results = Array(repeating: "", count: texts.count)

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5
        queue.qualityOfService = .userInitiated

        for (i, text) in texts.enumerated() {
            queue.addOperation { [weak self] in
                guard let self = self else {
                    lock.lock()
                    results[i] = text
                    lock.unlock()
                    return
                }
                let sem = DispatchSemaphore(value: 0)
                var translatedResult: String? = nil

                self.translateSingle(text) { translated in
                    translatedResult = translated
                    sem.signal()
                }

                // 等待最多12秒（请求超时10秒+2秒缓冲）
                _ = sem.wait(timeout: .now() + 12)

                lock.lock()
                results[i] = translatedResult ?? text
                lock.unlock()
            }
        }

        // 后台队列等待所有操作完成，绝不阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async {
            queue.waitUntilAllOperationsAreFinished()
            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
    /// 单段翻译：Google gtx 主源 → MyMemory 备用，URLSession.shared，每请求10秒超时
    private func translateSingle(_ text: String, completion: @escaping (String?) -> Void) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"

        // 源1：Google 翻译 gtx 端点（无需API key，翻译质量最好）
        guard let url1 = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=\(encoded)") else {
            completion(nil)
            return
        }
        var req1 = URLRequest(url: url1)
        req1.timeoutInterval = 10
        req1.httpMethod = "GET"
        req1.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req1.setValue("*/*", forHTTPHeaderField: "Accept")
        req1.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")

        URLSession.shared.dataTask(with: req1) { data, response, error in
            // Google gtx 返回嵌套数组格式：[[["译文","原文",...]],...]
            if let data = data,
               let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               let segments = json.first as? [[Any]] {
                var translated = ""
                for seg in segments {
                    if seg.count > 0, let text = seg[0] as? String {
                        translated += text
                    }
                }
                if !translated.isEmpty {
                    completion(translated)
                    return
                }
            }
            print("Google翻译失败，降级到MyMemory")

            // 源2：MyMemory 备用
            guard let url2 = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=autodetect|zh-CN") else {
                completion(nil)
                return
            }
            var req2 = URLRequest(url: url2)
            req2.timeoutInterval = 10
            req2.httpMethod = "GET"
            req2.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req2.setValue("application/json", forHTTPHeaderField: "Accept")
            req2.setValue("https://mymemory.translated.net/", forHTTPHeaderField: "Referer")

            URLSession.shared.dataTask(with: req2) { data, response, error in
                if let data = data,
                   let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["responseStatus"] as? Int, status == 200,
                   let respData = json["responseData"] as? [String: Any],
                   let translated = respData["translatedText"] as? String,
                   !translated.isEmpty {
                    completion(translated)
                    return
                }
                if let data = data, let raw = String(data: data, encoding: .utf8) {
                    print("MyMemory返回: \(raw.prefix(200))")
                }
                completion(nil)
            }.resume()
        }.resume()
    }
    /// 一次性应用翻译结果到页面（TreeWalker只遍历一次，在文本修改前完成所有匹配，避免分批应用时的顺序错乱）
    private func applyTranslations(_ translations: [String], to webView: WKWebView) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: translations),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        let js = """
        (function() {
            var translations = \(jsonStr);
            var idx = 0;
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function(node) {
                    if (!node.textContent || !node.textContent.trim()) return NodeFilter.FILTER_REJECT;
                    var p = node.parentElement;
                    if (!p) return NodeFilter.FILTER_REJECT;
                    var t = p.tagName.toLowerCase();
                    if (t==='script'||t==='style'||t==='noscript'||t==='textarea'||t==='input'||t==='select'||t==='option'||t==='code'||t==='pre') return NodeFilter.FILTER_REJECT;
                    if (/[\\u4e00-\\u9fa5]/.test(node.textContent)) return NodeFilter.FILTER_REJECT;
                    if (node.textContent.trim().length < 2) return NodeFilter.FILTER_REJECT;
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            var n;
            while ((n = walker.nextNode())) {
                if (idx < translations.length && translations[idx]) {
                    n.textContent = translations[idx];
                }
                idx++;
            }
            window.__browser_translate_done__ = true;
            return 'applied:' + idx;
        })();
        """
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    /// 恢复原文
    private func restoreOriginalText() {
        let targetWebView = currentWebView
        let targetIndex = activeIndex
        let js = """
        (function() {
            var all = document.querySelectorAll('*');
            for (var i = 0; i < all.length; i++) {
                for (var j = 0; j < all[i].childNodes.length; j++) {
                    var n = all[i].childNodes[j];
                    if (n.nodeType === 3 && n.__browser_orig_text__) {
                        n.textContent = n.__browser_orig_text__;
                    }
                }
            }
            window.__browser_translate_active__ = false;
            window.__browser_translate_done__ = false;
            return 'restored';
        })();
        """
        targetWebView.evaluateJavaScript(js) { [weak self] _, _ in
            guard let self = self else { return }
            self.isTranslated[targetIndex] = false
            self.updateTranslateButtonState()
        }
    }
    /// 显示翻译提示（轻量toast）
    private func showTranslateToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        toast.textColor = .white
        toast.font = .systemFont(ofSize: 14)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 8
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            toast.heightAnchor.constraint(equalToConstant: 36)
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.25, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.25, delay: 1.5, options: [], animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 结束下拉刷新
        if let index = webViews.firstIndex(of: webView), index < refreshControls.count {
            refreshControls[index].endRefreshing()
        }
        // 更新标签标题
        if let index = webViews.firstIndex(of: webView), let title = webView.title {
            updateTabTitle(index: index, title: title)
        }
        // 页面加载后重置翻译状态（新页面需要重新翻译）
        if let index = webViews.firstIndex(of: webView) {
            isTranslated[index] = false
            if index == activeIndex {
                updateTranslateButtonState()
            }
        }
        if webView === currentWebView {
            progressView.isHidden = true
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let index = webViews.firstIndex(of: webView), index < refreshControls.count {
            refreshControls[index].endRefreshing()
        }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let index = webViews.firstIndex(of: webView), index < refreshControls.count {
            refreshControls[index].endRefreshing()
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
    deinit {
        for webView in webViews {
            webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        }
    }
}
// MARK: - UIGestureRecognizerDelegate
extension ViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) * 1.2
    }
}
