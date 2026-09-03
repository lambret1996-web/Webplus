import UIKit
import WebKit
class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate, UITextFieldDelegate {
    // MARK: - 配置项
    private let windowTitles: [String] = ["GitHub", "CF", "Google", "YouTube"]
    private let windowURLs: [String] = [
        "https://github.com",
        "https://dash.cloudflare.com/",
        "https://www.google.com",
        "https://www.youtube.com"
    ]
    private let tabBarHeight: CGFloat = 28
    private let translateButtonSize: CGFloat = 24
    private let maxTranslateSegments = 5000
    private let refreshTriggerDistance: CGFloat = 70
    // MARK: - UI 组件
    private var tabBar: UIView!
    private var tabButtons: [UIButton] = []
    private var translateButton: UIButton!
    private var urlTextField: UITextField!
    private var webViews: [WKWebView] = []
    private var webViewContainer: UIView!
    private var progressView: UIProgressView!
    private var panGestures: [UIPanGestureRecognizer] = []
    /// 自定义下拉刷新
    private var refreshViews: [UIView] = []
    private var refreshIndicators: [UIActivityIndicatorView] = []
    private var refreshLabels: [UILabel] = []
    private var isRefreshing: [Bool] = [false, false, false, false]
    private var activeIndex: Int = 0
    // MARK: - 手势相关
    private var gestureStartPoint: CGPoint = .zero
    private var gestureStartDate: Date = .init()
    private let gestureThreshold: CGFloat = 80
    private let gestureMaxDuration: TimeInterval = 0.5
    // MARK: - 翻译相关
    private var isTranslated: [Bool] = [false, false, false, false]
    private var isTranslating = false
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        checkAndClearCacheIfNeeded()
        setupTabBar()
        setupWebViewContainer()
        setupWebViews()
        setupProgressView()
        setupGestures()
        switchToTab(index: 0)
        loadInitialPages()
    }
    override var prefersStatusBarHidden: Bool { false }
    override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }
    // MARK: - 缓存管理（24小时自动清空）
    private func checkAndClearCacheIfNeeded() {
        let lastClear = UserDefaults.standard.double(forKey: "lastCacheClearTime")
        let now = Date().timeIntervalSince1970
        let twentyFourHours: TimeInterval = 24 * 60 * 60
        // 首次启动或超过24小时则清除缓存
        if lastClear == 0 || now - lastClear > twentyFourHours {
            URLCache.shared.removeAllCachedResponses()
            let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().removeData(ofTypes: dataTypes, modifiedSince: Date.distantPast) {
                UserDefaults.standard.set(now, forKey: "lastCacheClearTime")
            }
        }
    }
    // MARK: - 顶部工具栏
    private func setupTabBar() {
        tabBar = UIView()
        tabBar.backgroundColor = .secondarySystemBackground
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        let separator = UIView()
        separator.backgroundColor = .separator.withAlphaComponent(0.5)
        separator.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(separator)
        NSLayoutConstraint.activate([
            tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: tabBarHeight),
            separator.bottomAnchor.constraint(equalTo: tabBar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: tabBar.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
        // 翻译按钮（底层）
        translateButton = UIButton(type: .custom)
        translateButton.setTitle("译", for: .normal)
        translateButton.titleLabel?.font = .systemFont(ofSize: 10, weight: .bold)
        translateButton.backgroundColor = .systemBlue
        translateButton.setTitleColor(.white, for: .normal)
        translateButton.layer.cornerRadius = translateButtonSize / 2
        translateButton.layer.shadowColor = UIColor.systemBlue.cgColor
        translateButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        translateButton.layer.shadowRadius = 6
        translateButton.layer.shadowOpacity = 0.25
        translateButton.translatesAutoresizingMaskIntoConstraints = false
        translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
        tabBar.addSubview(translateButton)
        // 标签按钮（动态创建4个）
        let tabWidth: CGFloat = 50
        let tabFont: CGFloat = 10
        for (i, title) in windowTitles.enumerated() {
            let btn = UIButton(type: .system)
            btn.setTitle(title, for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: tabFont, weight: i == 0 ? .bold : .regular)
            btn.tag = i
            btn.backgroundColor = .clear
            btn.setTitleColor(i == 0 ? .systemBlue : .secondaryLabel, for: .normal)
            btn.translatesAutoresizingMaskIntoConstraints = false
            btn.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside)
            tabBar.addSubview(btn)
            tabButtons.append(btn)
        }
        // 网址输入框（翻译按钮和Google之间）
        urlTextField = UITextField()
        urlTextField.placeholder = "输入网址"
        urlTextField.font = .systemFont(ofSize: 10)
        urlTextField.borderStyle = .roundedRect
        urlTextField.backgroundColor = .tertiarySystemBackground
        urlTextField.keyboardType = .URL
        urlTextField.autocorrectionType = .no
        urlTextField.autocapitalizationType = .none
        urlTextField.returnKeyType = .go
        urlTextField.clearButtonMode = .whileEditing
        urlTextField.delegate = self
        urlTextField.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(urlTextField)
        NSLayoutConstraint.activate([
            // 左1：GitHub
            tabButtons[0].leadingAnchor.constraint(equalTo: tabBar.leadingAnchor, constant: 6),
            tabButtons[0].centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabButtons[0].widthAnchor.constraint(equalToConstant: tabWidth),
            tabButtons[0].heightAnchor.constraint(equalToConstant: 24),
            // 左2：CF
            tabButtons[1].leadingAnchor.constraint(equalTo: tabButtons[0].trailingAnchor, constant: 2),
            tabButtons[1].centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabButtons[1].widthAnchor.constraint(equalToConstant: 42),
            tabButtons[1].heightAnchor.constraint(equalToConstant: 24),
            // 翻译按钮：CF右边距10px
            translateButton.leadingAnchor.constraint(equalTo: tabButtons[1].trailingAnchor, constant: 10),
            translateButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            translateButton.widthAnchor.constraint(equalToConstant: translateButtonSize),
            translateButton.heightAnchor.constraint(equalToConstant: translateButtonSize),
            // 网址输入框：翻译按钮右边距5px，Google左边距5px
            urlTextField.leadingAnchor.constraint(equalTo: translateButton.trailingAnchor, constant: 5),
            urlTextField.trailingAnchor.constraint(equalTo: tabButtons[2].leadingAnchor, constant: -5),
            urlTextField.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            urlTextField.heightAnchor.constraint(equalToConstant: 22),
            // 右2：Google
            tabButtons[2].trailingAnchor.constraint(equalTo: tabButtons[3].leadingAnchor, constant: -2),
            tabButtons[2].centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabButtons[2].widthAnchor.constraint(equalToConstant: tabWidth),
            tabButtons[2].heightAnchor.constraint(equalToConstant: 24),
            // 右1：YouTube
            tabButtons[3].trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -6),
            tabButtons[3].centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabButtons[3].widthAnchor.constraint(equalToConstant: tabWidth),
            tabButtons[3].heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    // MARK: - 网址输入框
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        guard let input = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else { return true }
        var urlString = input
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        if let url = URL(string: urlString) {
            currentWebView.load(URLRequest(url: url))
        }
        return true
    }
    /// 更新地址栏显示当前页面URL
    private func updateURLField() {
        urlTextField.text = currentWebView.url?.absoluteString ?? ""
    }
    @objc private func tabTapped(_ sender: UIButton) {
        switchToTab(index: sender.tag)
    }
    private func switchToTab(index: Int) {
        activeIndex = index
        for (i, button) in tabButtons.enumerated() {
            if i == index {
                button.setTitleColor(.systemBlue, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 10, weight: .bold)
            } else {
                button.setTitleColor(.secondaryLabel, for: .normal)
                button.titleLabel?.font = .systemFont(ofSize: 10, weight: .regular)
            }
        }
        for (i, webView) in webViews.enumerated() {
            webView.isHidden = (i != index)
        }
        updateProgressView()
        updateTranslateButtonState()
        updateURLField()
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
        for i in 0..<windowTitles.count {
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
            webView.scrollView.delegate = self
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
            setupCustomRefresh(for: webView, index: i)
        }
    }
    /// 自定义下拉刷新（触发距离120pt，避免误触）
    private func setupCustomRefresh(for webView: WKWebView, index: Int) {
        let refreshView = UIView(frame: CGRect(x: 0, y: -60, width: UIScreen.main.bounds.width, height: 60))
        refreshView.backgroundColor = .clear
        refreshView.autoresizingMask = [.flexibleWidth]
        refreshView.isHidden = true
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.center = CGPoint(x: refreshView.bounds.midX - 50, y: refreshView.bounds.midY)
        indicator.hidesWhenStopped = true
        refreshView.addSubview(indicator)
        let label = UILabel(frame: CGRect(x: refreshView.bounds.midX - 30, y: 0, width: 120, height: 60))
        label.text = "下拉刷新"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .left
        refreshView.addSubview(label)
        webView.scrollView.addSubview(refreshView)
        refreshViews.append(refreshView)
        refreshIndicators.append(indicator)
        refreshLabels.append(label)
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
    // MARK: - UIScrollViewDelegate（自定义下拉刷新）
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let index = webViews.firstIndex(where: { $0.scrollView === scrollView }) else { return }
        guard !isRefreshing[index] else { return }
        let pullDistance = -scrollView.contentOffset.y
        if pullDistance > 0 {
            refreshViews[index].isHidden = false
            if pullDistance >= refreshTriggerDistance {
                refreshLabels[index].text = "释放刷新"
                refreshLabels[index].textColor = .systemBlue
            } else {
                refreshLabels[index].text = "下拉刷新"
                refreshLabels[index].textColor = .secondaryLabel
            }
        } else {
            refreshViews[index].isHidden = true
        }
    }
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard let index = webViews.firstIndex(where: { $0.scrollView === scrollView }) else { return }
        guard !isRefreshing[index] else { return }
        let pullDistance = -scrollView.contentOffset.y
        if pullDistance >= refreshTriggerDistance {
            startCustomRefresh(for: index)
        }
    }
    private func startCustomRefresh(for index: Int) {
        isRefreshing[index] = true
        refreshIndicators[index].startAnimating()
        refreshLabels[index].text = "刷新中..."
        refreshLabels[index].textColor = .systemBlue
        UIView.animate(withDuration: 0.25) {
            self.webViews[index].scrollView.contentInset.top = 60
        }
        webViews[index].reload()
    }
    private func endCustomRefresh(for index: Int) {
        guard isRefreshing[index] else { return }
        isRefreshing[index] = false
        refreshIndicators[index].stopAnimating()
        refreshLabels[index].text = "下拉刷新"
        refreshLabels[index].textColor = .secondaryLabel
        UIView.animate(withDuration: 0.25, animations: {
            self.webViews[index].scrollView.contentInset.top = 0
        }) { _ in
            self.refreshViews[index].isHidden = true
        }
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
                if currentWebView.canGoBack { currentWebView.goBack() }
            } else {
                if currentWebView.canGoForward { currentWebView.goForward() }
            }
        default:
            break
        }
    }
    // MARK: - 翻译功能
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
            if let _ = error {
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
                    lock.lock(); results[i] = text; lock.unlock()
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
            DispatchQueue.main.async { completion(results) }
        }
    }
    private func translateSingle(_ text: String, completion: @escaping (String?) -> Void) {
        let encoded = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
        let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
        guard let url1 = URL(string: "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=zh-CN&dt=t&q=\(encoded)") else {
            completion(nil); return
        }
        var req1 = URLRequest(url: url1)
        req1.timeoutInterval = 10
        req1.httpMethod = "GET"
        req1.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req1.setValue("*/*", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req1) { data, response, _ in
            if let data = data,
               let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
               let segments = json.first as? [[Any]] {
                var translated = ""
                for seg in segments {
                    if seg.count > 0, let t = seg[0] as? String { translated += t }
                }
                if !translated.isEmpty { completion(translated); return }
            }
            guard let url2 = URL(string: "https://api.mymemory.translated.net/get?q=\(encoded)&langpair=autodetect|zh-CN") else {
                completion(nil); return
            }
            var req2 = URLRequest(url: url2)
            req2.timeoutInterval = 10
            req2.httpMethod = "GET"
            req2.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            req2.setValue("https://mymemory.translated.net/", forHTTPHeaderField: "Referer")
            URLSession.shared.dataTask(with: req2) { data, response, _ in
                if let data = data,
                   let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["responseStatus"] as? Int, status == 200,
                   let respData = json["responseData"] as? [String: Any],
                   let translated = respData["translatedText"] as? String,
                   !translated.isEmpty {
                    completion(translated); return
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
                if (idx < translations.length && translations[idx]) n.textContent = translations[idx];
                idx++;
            }
            return 'applied';
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
                    if (n.nodeType === 3 && n.__browser_orig_text__) n.textContent = n.__browser_orig_text__;
                }
            }
            window.__browser_translate_active__ = false;
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
            toast.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
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
    // MARK: - 下载功能（跳转默认浏览器）
    private func isDownloadResponse(_ response: URLResponse) -> Bool {
        guard let httpResponse = response as? HTTPURLResponse else { return false }
        // HTML 页面一律不认为是下载（避免登录页面等被误判）
        if let mimeType = response.mimeType, mimeType.lowercased().contains("text/html") { return false }
        if let disposition = httpResponse.allHeaderFields["Content-Disposition"] as? String,
           disposition.lowercased().contains("attachment") {
            return true
        }
        if let mimeType = response.mimeType, !mimeType.isEmpty {
            let viewableTypes = ["text/html", "text/plain", "application/xhtml+xml", "image/", "video/", "audio/", "application/pdf"]
            let isViewable = viewableTypes.contains { mimeType.lowercased().hasPrefix($0) }
            if !isViewable { return true }
        }
        if let url = response.url, let ext = url.pathExtension.lowercased() as String? {
            let downloadExts = ["zip", "rar", "7z", "tar", "gz", "dmg", "pkg", "exe", "msi", "deb", "rpm", "apk", "ipa", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "epub", "mobi", "csv"]
            if downloadExts.contains(ext) { return true }
        }
        return false
    }
    /// 检测到下载时弹窗提示，用户确认后跳转默认浏览器
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard isDownloadResponse(navigationResponse.response),
              let downloadURL = navigationResponse.response.url else {
            decisionHandler(.allow)
            return
        }
        let response = navigationResponse.response
        let fileName = response.suggestedFilename ?? downloadURL.lastPathComponent
        let fileSize = (response as? HTTPURLResponse)?.expectedContentLength ?? -1
        let sizeStr = fileSize > 0 ? ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file) : "未知大小"
        let alert = UIAlertController(
            title: "下载文件",
            message: "文件名：\(fileName)\n大小：\(sizeStr)\n将跳转默认浏览器下载",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "打开浏览器", style: .default) { _ in
            UIApplication.shared.open(downloadURL)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        self.present(alert, animated: true)
        decisionHandler(.cancel)
    }
    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let index = webViews.firstIndex(of: webView) {
            endCustomRefresh(for: index)
            isTranslated[index] = false
            if index == activeIndex { updateTranslateButtonState() }
        }
        if webView === currentWebView {
            progressView.isHidden = true
            updateURLField()
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let index = webViews.firstIndex(of: webView) { endCustomRefresh(for: index) }
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let index = webViews.firstIndex(of: webView) { endCustomRefresh(for: index) }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.allow)
    }
    // MARK: - WKUIDelegate
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank 链接在当前 WebView 打开
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
