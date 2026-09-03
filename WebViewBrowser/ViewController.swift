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
    /// 带超时的翻译请求会话（10秒请求超时，15秒资源超时）
    private lazy var translateSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        config.httpMaximumConnectionsPerHost = 5
        return URLSession(configuration: config)
    }()
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
    // MARK: - 全局翻译功能（原生端发起请求，后台队列并发，不阻塞主线程）
    @objc private func translateTapped() {
        // 翻译中禁止重复点击
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
    /// JS：收集页面所有待翻译文本节点，保存原文，返回文本数组JSON
    private let collectTextJS = """
    (function() {
        if (window.__browser_translate_active__) return JSON.stringify({error:'already_active'});
        window.__browser_translate_active__ = true;
        var texts = [];
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
            if (!n.__browser_orig_text__) n.__browser_orig_text__ = n.textContent;
            texts.push(n.textContent.trim());
        }
        return JSON.stringify({count: texts.length, texts: texts});
    })();
    """
    /// 启动翻译流程：锁定目标WebView → JS收集文本 → 后台队列原生端翻译 → JS应用结果
    private func startTranslation() {
        // 锁定当前窗口，翻译过程中切换标签不影响结果
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
            // 标记翻译中，禁用按钮
            self.isTranslating = true
            self.isTranslated[targetIndex] = true
            self.updateTranslateButtonState()

            // 后台队列执行翻译，不阻塞主线程
            self.translateTextsNative(texts) { [weak self] translations in
                guard let self = self else { return }
                // 应用翻译结果到锁定的目标窗口
                self.applyTranslations(translations, to: targetWebView)
                self.isTranslating = false
                self.updateTranslateButtonState()
            }
        }
    }
    /// 原生端批量翻译：后台队列执行，5并发，NSLock保护数组，MyMemory→有道双源降级
    private func translateTextsNative(_ texts: [String], completion: @escaping ([String]) -> Void) {
        let lock = NSLock()
        var results = Array(repeating: "", count: texts.count)
        let group = DispatchGroup()
        let semaphore = DispatchSemaphore(value: 5)

        // 关键：在后台队列执行 semaphore.wait()，绝不阻塞主线程
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(texts) }
                return
            }
            for (i, text) in texts.enumerated() {
                semaphore.wait()
                group.enter()
                self.translateSingleNative(text) { translated in
                    lock.lock()
                    results[i] = translated ?? text
                    lock.unlock()
                    group.leave()
                    semaphore.signal()
                }
            }
            group.wait()
            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
    /// 原生端单段翻译：MyMemory → 有道双源降级，使用带超时的会话
    private func translateSingleNative(_ text: String, completion: @escaping (String?) -> Void) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        // 源1：MyMemory
        guard let url1 = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=autodetect|zh-CN") else {
            completion(nil)
            return
        }
        translateSession.dataTask(with: url1) { data, _, error in
            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["responseStatus"] as? Int, status == 200,
               let respData = json["responseData"] as? [String: Any],
               let translated = respData["translatedText"] as? String,
               !translated.isEmpty {
                completion(translated)
                return
            }
            // 源2：有道翻译
            guard let url2 = URL(string: "https://fanyi.youdao.com/translate?&doctype=json&type=AUTO&i=\(encoded)") else {
                completion(nil)
                return
            }
            self.translateSession.dataTask(with: url2) { data, _, _ in
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let code = json["errorCode"] as? Int, code == 0,
                   let resultArr = json["translateResult"] as? [[[String: Any]]] {
                    var translated = ""
                    for seg in resultArr[0] {
                        if let tgt = seg["tgt"] as? String {
                            translated += tgt
                        }
                    }
                    if !translated.isEmpty {
                        completion(translated)
                        return
                    }
                }
                completion(nil)
            }.resume()
        }.resume()
    }
    /// JS：将翻译结果应用到指定WebView的页面对应文本节点
    private func applyTranslations(_ translations: [String], to webView: WKWebView) {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: translations),
              let jsonStr = String(data: jsonData, encoding: .utf8) else { return }
        let applyJS = """
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
            return 'applied';
        })();
        """
        webView.evaluateJavaScript(applyJS, completionHandler: nil)
    }
    /// 恢复原文：调用页面内保存的原文
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
        targetWebView.evaluateJavaScript(js) { [weak self] result, error in
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
