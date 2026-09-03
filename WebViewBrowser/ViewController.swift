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
    /// 底部工具栏高度
    private let tabBarHeight: CGFloat = 72
    /// 翻译按钮尺寸（圆形）
    private let translateButtonSize: CGFloat = 60
    /// 单次翻译最大文本段数（防止超大页面内存溢出）
    private let maxTranslateSegments = 5000
    // MARK: - UI 组件
    private var tabBar: UIView!
    private var tabBarBlur: UIVisualEffectView!
    private var tabButtons: [UIButton] = []
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
        setupWebViewContainer()
        setupTabBar()
        setupWebViews()
        setupProgressView()
        setupRefreshControls()
        setupGestures()
        switchToTab(index: 0)
        loadInitialPages()
    }
    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
    // MARK: - 底部工具栏（毛玻璃 + 圆形翻译按钮居中）
    private func setupTabBar() {
        tabBar = UIView()
        tabBar.backgroundColor = .clear
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        let blur = UIBlurEffect(style: .systemMaterial)
        tabBarBlur = UIVisualEffectView(effect: blur)
        tabBarBlur.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(tabBarBlur)
        let separator = UIView()
        separator.backgroundColor = .separator.withAlphaComponent(0.3)
        separator.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(separator)
        NSLayoutConstraint.activate([
            tabBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -tabBarHeight),
            tabBarBlur.topAnchor.constraint(equalTo: tabBar.topAnchor),
            tabBarBlur.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            tabBarBlur.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            tabBarBlur.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            separator.topAnchor.constraint(equalTo: tabBar.topAnchor),
            separator.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        let tabLeft = createTabButton(title: windowTitles[0], tag: 0)
        tabBar.addSubview(tabLeft)
        tabButtons.append(tabLeft)
        let tabRight = createTabButton(title: windowTitles[1], tag: 1)
        tabBar.addSubview(tabRight)
        tabButtons.append(tabRight)
        translateButton = UIButton(type: .system)
        translateButton.setTitle("译", for: .normal)
        translateButton.titleLabel?.font = .systemFont(ofSize: 22, weight: .bold)
        translateButton.backgroundColor = .systemBlue
        translateButton.setTitleColor(.white, for: .normal)
        translateButton.layer.cornerRadius = translateButtonSize / 2
        translateButton.layer.shadowColor = UIColor.systemBlue.cgColor
        translateButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        translateButton.layer.shadowRadius = 8
        translateButton.layer.shadowOpacity = 0.3
        translateButton.translatesAutoresizingMaskIntoConstraints = false
        translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
        tabBar.addSubview(translateButton)
        NSLayoutConstraint.activate([
            tabLeft.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 20),
            tabLeft.centerYAnchor.constraint(equalTo: tabBar.topAnchor, constant: tabBarHeight / 2),
            tabLeft.widthAnchor.constraint(equalToConstant: 84),
            tabLeft.heightAnchor.constraint(equalToConstant: 32),
            tabRight.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -20),
            tabRight.centerYAnchor.constraint(equalTo: tabBar.topAnchor, constant: tabBarHeight / 2),
            tabRight.widthAnchor.constraint(equalToConstant: 84),
            tabRight.heightAnchor.constraint(equalToConstant: 32),
            translateButton.centerXAnchor.constraint(equalTo: tabBar.centerXAnchor),
            translateButton.centerYAnchor.constraint(equalTo: tabBar.topAnchor, constant: tabBarHeight / 2),
            translateButton.widthAnchor.constraint(equalToConstant: translateButtonSize),
            translateButton.heightAnchor.constraint(equalToConstant: translateButtonSize)
        ])
    }
    private func createTabButton(title: String, tag: Int) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.tag = tag
        button.layer.cornerRadius = 16
        button.layer.masksToBounds = true
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor.separator.cgColor
        button.backgroundColor = .secondarySystemFill
        button.setTitleColor(.label, for: .normal)
        button.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
        return button
    }
    @objc private func tabTapped(_ sender: UIButton) {
        switchToTab(index: sender.tag)
    }
    private func switchToTab(index: Int) {
        activeIndex = index
        for (i, button) in tabButtons.enumerated() {
            if i == index {
                button.backgroundColor = .systemBlue.withAlphaComponent(0.12)
                button.setTitleColor(.systemBlue, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
            } else {
                button.backgroundColor = .secondarySystemFill
                button.setTitleColor(.label, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 14, weight: .regular)
            }
        }
        for (i, webView) in webViews.enumerated() {
            webView.isHidden = (i != index)
        }
        updateProgressView()
        updateTranslateButtonState()
    }
    private func updateTabTitle(index: Int, title: String) {
        guard index < tabButtons.count else { return }
        // 空标题时保持默认标题，避免标签文字被清空
        let safeTitle = title.isEmpty ? windowTitles[index] : title
        let displayTitle = safeTitle.count > 6 ? String(safeTitle.prefix(6)) + "…" : safeTitle
        tabButtons[index].setTitle(displayTitle, for: .normal)
    }
    // MARK: - WebView 容器
    private func setupWebViewContainer() {
        webViewContainer = UIView()
        webViewContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webViewContainer)
        NSLayoutConstraint.activate([
            webViewContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.allowsBackForwardNavigationGestures = false
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.scrollView.bounces = true
            webView.scrollView.contentInset.bottom = tabBarHeight + 8
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
    // MARK: - 进度条（顶部）
    private func setupProgressView() {
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .clear
        progressView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
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
    // MARK: - 全局翻译功能
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
            translateButton.layer.shadowColor = UIColor.systemGray.cgColor
            return
        }
        translateButton.isEnabled = true
        if isTranslated[activeIndex] {
            translateButton.backgroundColor = .systemGreen
            translateButton.setTitle("原", for: .normal)
            translateButton.layer.shadowColor = UIColor.systemGreen.cgColor
        } else {
            translateButton.backgroundColor = .systemBlue
            translateButton.setTitle("译", for: .normal)
            translateButton.layer.shadowColor = UIColor.systemBlue.cgColor
        }
    }
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
            self.isTranslating = true
            self.isTranslated[targetIndex] = true
            self.updateTranslateButtonState()
            self.translateWithOperationQueue(texts) { [weak self] translations in
                guard let self = self else { return }
                self.applyTranslations(translations, to: targetWebView)
                self.isTranslating = false
                self.updateTranslateButtonState()
            }
        }
    }
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
                _ = sem.wait(timeout: .now() + 12)
                lock.lock()
                results[i] = translatedResult ?? text
                lock.unlock()
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            queue.waitUntilAllOperationsAreFinished()
            DispatchQueue.main.async {
                completion(results)
            }
        }
    }
    private func translateSingle(_ text: String, completion: @escaping (String?) -> Void) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
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
            toast.bottomAnchor.constraint(equalTo: tabBar.topAnchor, constant: -16),
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
        if let index = webViews.firstIndex(of: webView), index < refreshControls.count {
            refreshControls[index].endRefreshing()
        }
        if let index = webViews.firstIndex(of: webView), let title = webView.title {
            updateTabTitle(index: index, title: title)
        }
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
