import UIKit
import WebKit
import AVFoundation
import Photos
import CoreLocation
import CoreBluetooth
import Speech
import UserNotifications
import LocalAuthentication
import MediaPlayer
import CoreMotion
import Contacts
import EventKit
import AppTrackingTransparency
class ViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate, UITextFieldDelegate {
    // MARK: - 配置项
    private var windowTitles: [String] = ["GitHub", "CF", "Google", "YouTube"]
    private var windowURLs: [String] = [
        "https://github.com",
        "https://dash.cloudflare.com/",
        "https://www.google.com",
        "https://www.youtube.com"
    ]
    /// 书签列表（长按GitHub收藏，长按CF打开）
    private var bookmarks: [String] = []
    private let bookmarksKey = "savedBookmarks"
    private let customTitlesKey = "customWindowTitles"
    private let customURLsKey = "customWindowURLs"
    private let tabBarHeight: CGFloat = 28
    private let translateButtonSize: CGFloat = 17
    private let maxTranslateSegments = 5000
    private let refreshTriggerDistance: CGFloat = 70
    // MARK: - UI 组件
    private var tabBar: UIView!
    private var tabButtons: [UIButton] = []
    private var translateButton: UIButton!
    private var downloadButton: UIButton!
    private var downloadBadge: UILabel!
    private var confirmBar: UIView?
    private var pendingDownloadURL: String?
    private var pendingDownloadName: String?
    // 第三方登录
    private var loginConfirmBar: UIView?
    private var pendingLoginURL: URL?
    private var pendingLoginPlatform: ThirdPartyPlatform?
    private var loginConfirmKey = "loginConfirmEnabled"
    private var isLoginRedirecting = false
    private var urlTextField: UITextField!
    private var webViews: [WKWebView] = []
    private var webViewContainer: UIView!
    private var progressView: UIProgressView!
    private var panGestures: [UIPanGestureRecognizer] = []
    // 右边缘下滑功能菜单
    private var edgeMenuView: UIView!
    private var edgeMenuOverlay: UIButton!
    private var edgeMenuLeadingConstraint: NSLayoutConstraint!
    private var edgeMenuIsOpen = false
    private var edgeMenuStartX: CGFloat = 0
    private var edgeMenuPanStart: CGPoint = .zero
    private var edgeMenuDidTrigger = false
    /// 自定义下拉刷新
    private var refreshViews: [UIView] = []
    private var refreshIndicators: [UIActivityIndicatorView] = []
    private var refreshLabels: [UILabel] = []
    private var isRefreshing: [Bool] = [false, false, false, false]
    private var activeIndex: Int = 0
    // MARK: - 手势相关
    private var gestureStartPoint: CGPoint = .zero
    private var gestureStartDate: Date = .init()
    private let gestureThreshold: CGFloat = 90
    private let gestureMaxDuration: TimeInterval = 0.5
    // MARK: - 翻译相关
    private var isTranslated: [Bool] = [false, false, false, false]
    private var isTranslating = false
    // MARK: - 广告拦截配置
    private var adBlockEnabled: Bool = true
    private var customAdDomains: [String] = []
    private let adBlockKey = "adBlockEnabled"
    private let customAdDomainsKey = "customAdDomains"
    private let globalImageBlockKey = "globalImageBlock"
    private let fourLevelCache = FourLevelCache(memoryCapacity: 80 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024, diskPath: "FourLevelCache")
    // MARK: - UA切换
    private var currentUAIndex: Int = 0
    private let uaIndexKey = "currentUAIndex"
    // MARK: - 网页搜索
    private var currentFindIndex: Int = 0
    private var totalFindCount: Int = 0
    private var findBarView: UIView?
    private var findTextField: UITextField?
    private var findCountLabel: UILabel?
    private var findKeyword: String = ""
    private var findBottomConstraint: NSLayoutConstraint?
    private let uaPresets = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Safari/605.1.15",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    ]
    private let uaNames = ["默认移动端", "桌面版", "Safari原版"]
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        loadCustomConfig()
        checkAndClearCacheIfNeeded()
        setupTabBar()
        setupWebViewContainer()
        setupWebViews()
        setupProgressView()
        setupGestures()
        setupEdgeMenu()
        switchToTab(index: 0)
        loadInitialPages()
        // 下载管理回调
        DownloadManager.shared.onProgress = { [weak self] _ in
            DispatchQueue.main.async { self?.updateDownloadBadge() }
        }
        DownloadManager.shared.onStatusChanged = { [weak self] _ in
            DispatchQueue.main.async { self?.updateDownloadBadge() }
        }
        DownloadManager.shared.onCompleted = { [weak self] task in
            DispatchQueue.main.async {
                self?.updateDownloadBadge()
                let alert = UIAlertController(
                    title: "下载完成",
                    message: "\(task.fileName)\n已保存到：文件 App → 本应用 → Downloads",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "查看文件", style: .default) { _ in
                    if let path = task.localPath {
                        let url = URL(fileURLWithPath: path)
                        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                        self?.present(activityVC, animated: true)
                    }
                })
                alert.addAction(UIAlertAction(title: "好的", style: .cancel))
                self?.present(alert, animated: true)
            }
        }
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
        translateButton.backgroundColor = UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
        translateButton.setTitleColor(.white, for: .normal)
        translateButton.layer.cornerRadius = translateButtonSize / 2
        translateButton.layer.shadowColor = UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0).cgColor
        translateButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        translateButton.layer.shadowRadius = 6
        translateButton.layer.shadowOpacity = 0.25
        translateButton.translatesAutoresizingMaskIntoConstraints = false
        translateButton.addTarget(self, action: #selector(translateTapped), for: .touchUpInside)
        tabBar.addSubview(translateButton)
        // 下载按钮
        downloadButton = UIButton(type: .system)
        downloadButton.setImage(UIImage(systemName: "arrow.down.circle"), for: .normal)
        downloadButton.tintColor = .systemBlue
        downloadButton.translatesAutoresizingMaskIntoConstraints = false
        downloadButton.addTarget(self, action: #selector(downloadButtonTapped), for: .touchUpInside)
        tabBar.addSubview(downloadButton)
        // 下载角标
        downloadBadge = UILabel()
        downloadBadge.text = "0"
        downloadBadge.font = .systemFont(ofSize: 9, weight: .bold)
        downloadBadge.textColor = .white
        downloadBadge.backgroundColor = .systemRed
        downloadBadge.textAlignment = .center
        downloadBadge.layer.cornerRadius = 8
        downloadBadge.layer.masksToBounds = true
        downloadBadge.isHidden = true
        downloadBadge.translatesAutoresizingMaskIntoConstraints = false
        tabBar.addSubview(downloadBadge)
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
            let longPress = UILongPressGestureRecognizer(target: self, action: #selector(tabLongPressed(_:)))
            longPress.minimumPressDuration = 0.5
            btn.addGestureRecognizer(longPress)
            // 双击返回默认主页
            let doubleTap = UITapGestureRecognizer(target: self, action: #selector(tabDoubleTapped(_:)))
            doubleTap.numberOfTapsRequired = 2
            btn.addGestureRecognizer(doubleTap)
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
        let urlLongPress = UILongPressGestureRecognizer(target: self, action: #selector(urlFieldLongPressed(_:)))
        urlLongPress.minimumPressDuration = 0.5
        urlTextField.addGestureRecognizer(urlLongPress)
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
            translateButton.leadingAnchor.constraint(equalTo: tabButtons[1].trailingAnchor, constant: 1),
            translateButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            translateButton.widthAnchor.constraint(equalToConstant: translateButtonSize),
            translateButton.heightAnchor.constraint(equalToConstant: translateButtonSize),
            // 网址输入框：翻译按钮右边距5px，Google左边距5px
            urlTextField.leadingAnchor.constraint(equalTo: translateButton.trailingAnchor, constant: 5),
            urlTextField.trailingAnchor.constraint(equalTo: tabButtons[2].leadingAnchor, constant: -5),
            urlTextField.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            urlTextField.heightAnchor.constraint(equalToConstant: 20),
            // 右2：Google
            tabButtons[2].trailingAnchor.constraint(equalTo: tabButtons[3].leadingAnchor, constant: -2),
            tabButtons[2].centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabButtons[2].widthAnchor.constraint(equalToConstant: tabWidth),
            tabButtons[2].heightAnchor.constraint(equalToConstant: 24),
            // 右1：YouTube
            tabButtons[3].trailingAnchor.constraint(equalTo: downloadButton.leadingAnchor, constant: -2),
            tabButtons[3].centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            tabButtons[3].widthAnchor.constraint(equalToConstant: tabWidth),
            tabButtons[3].heightAnchor.constraint(equalToConstant: 24),
            // 下载按钮
            downloadButton.trailingAnchor.constraint(equalTo: tabBar.trailingAnchor, constant: -4),
            downloadButton.centerYAnchor.constraint(equalTo: tabBar.centerYAnchor),
            downloadButton.widthAnchor.constraint(equalToConstant: 22),
            downloadButton.heightAnchor.constraint(equalToConstant: 22),
            // 下载角标
            downloadBadge.topAnchor.constraint(equalTo: downloadButton.topAnchor, constant: -4),
            downloadBadge.trailingAnchor.constraint(equalTo: downloadButton.trailingAnchor, constant: 2),
            downloadBadge.widthAnchor.constraint(equalToConstant: 16),
            downloadBadge.heightAnchor.constraint(equalToConstant: 16)
        ])
    }
    // MARK: - 网址输入框
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // 搜索框按回车不关闭键盘，保持搜索状态
        if textField === findTextField {
            return true
        }
        textField.resignFirstResponder()
        guard let input = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else { return true }
        // 智能搜索：含空格/中文/无点号 → Google搜索
        let hasChinese = input.range(of: "\\p{Han}", options: .regularExpression) != nil
        let hasSpace = input.contains(" ")
        let hasDot = input.contains(".")
        if hasChinese || hasSpace || !hasDot {
            let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
            if let searchURL = URL(string: "https://www.google.com/search?q=\(encoded)") {
                currentWebView.load(URLRequest(url: searchURL))
            }
            return true
        }
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
    // MARK: - 长按手势处理
    @objc private func tabLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let btn = gesture.view as? UIButton else { return }
        switch btn.tag {
        case 0: saveBookmark()       // GitHub：收藏当前页面
        case 1: clearCurrentSiteCache() // CF：清除当前站点缓存
        case 2: manageWindows()      // Google：管理窗口配置
        case 3: openBookmarks()      // YouTube：打开书签列表
        default: break
        }
    }
    @objc private func urlFieldLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let url = currentWebView.url?.absoluteString ?? urlTextField.text ?? ""
        UIPasteboard.general.string = url
        showToast("已复制链接")
    }
    // MARK: - 书签功能
    private func saveBookmark() {
        guard let url = currentWebView.url?.absoluteString else {
            showToast("当前页面无有效链接"); return
        }
        if bookmarks.contains(url) {
            showToast("该书签已存在"); return
        }
        bookmarks.append(url)
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        showToast("已收藏：\(url.prefix(30))...")
    }
    private func openBookmarks() {
        if bookmarks.isEmpty {
            showToast("暂无书签，长按GitHub可收藏"); return
        }
        let alert = UIAlertController(title: "书签列表", message: nil, preferredStyle: .actionSheet)
        for (i, bm) in bookmarks.enumerated() {
            alert.addAction(UIAlertAction(title: bm, style: .default) { _ in
                if let url = URL(string: bm) {
                    self.currentWebView.load(URLRequest(url: url))
                }
            })
            // 支持删除
            alert.addAction(UIAlertAction(title: "删除此书签", style: .destructive) { _ in
                self.bookmarks.remove(at: i)
                UserDefaults.standard.set(self.bookmarks, forKey: self.bookmarksKey)
                self.showToast("已删除")
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = tabButtons[3]
            popover.sourceRect = tabButtons[3].bounds
        }
        present(alert, animated: true)
    }
    // MARK: - 清除当前站点缓存
    private func clearCurrentSiteCache() {
        guard let host = currentWebView.url?.host else {
            showToast("无法获取当前站点"); return
        }
        let store = currentWebView.configuration.websiteDataStore
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        store.fetchDataRecords(ofTypes: dataTypes) { records in
            let target = records.filter { $0.displayName == host || host.contains($0.displayName) }
            store.removeData(ofTypes: dataTypes, for: target) {
                DispatchQueue.main.async {
                    self.currentWebView.reload()
                    self.showToast("已清除 \(host) 缓存")
                }
            }
        }
    }
    // MARK: - 窗口管理（自定义名称和地址）
    private func manageWindows() {
        let alert = UIAlertController(title: "管理窗口", message: "修改4个窗口的名称和地址", preferredStyle: .alert)
        for i in 0..<4 {
            alert.addTextField { tf in
                tf.placeholder = "窗口\(i+1)名称"
                tf.text = self.windowTitles[i]
                tf.font = .systemFont(ofSize: 12)
            }
            alert.addTextField { tf in
                tf.placeholder = "窗口\(i+1)地址"
                tf.text = self.windowURLs[i]
                tf.font = .systemFont(ofSize: 10)
                tf.keyboardType = .URL
                tf.autocapitalizationType = .none
                tf.autocorrectionType = .no
            }
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            guard let fields = alert.textFields, fields.count == 8 else { return }
            var newTitles: [String] = []
            var newURLs: [String] = []
            for i in 0..<4 {
                let title = fields[i*2].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let url = fields[i*2+1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                newTitles.append(title.isEmpty ? self.windowTitles[i] : title)
                newURLs.append(url.isEmpty ? self.windowURLs[i] : url)
            }
            self.windowTitles = newTitles
            self.windowURLs = newURLs
            self.saveCustomConfig()
            // 更新标签按钮标题
            for (i, btn) in self.tabButtons.enumerated() {
                btn.setTitle(newTitles[i], for: .normal)
            }
            // 重新加载所有页面
            for (i, wv) in self.webViews.enumerated() {
                if let url = URL(string: newURLs[i]) {
                    wv.load(URLRequest(url: url))
                }
            }
            self.showToast("窗口配置已保存")
        })
        alert.addAction(UIAlertAction(title: "恢复默认", style: .destructive) { _ in
            self.windowTitles = ["GitHub", "CF", "Google", "YouTube"]
            self.windowURLs = ["https://github.com", "https://dash.cloudflare.com/", "https://www.google.com", "https://www.youtube.com"]
            UserDefaults.standard.removeObject(forKey: self.customTitlesKey)
            UserDefaults.standard.removeObject(forKey: self.customURLsKey)
            for (i, btn) in self.tabButtons.enumerated() {
                btn.setTitle(self.windowTitles[i], for: .normal)
            }
            for (i, wv) in self.webViews.enumerated() {
                if let url = URL(string: self.windowURLs[i]) {
                    wv.load(URLRequest(url: url))
                }
            }
            self.showToast("已恢复默认窗口")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    // MARK: - 自定义配置存取
    private func loadCustomConfig() {
        if let titles = UserDefaults.standard.stringArray(forKey: customTitlesKey), titles.count == 4 {
            windowTitles = titles
        }
        if let urls = UserDefaults.standard.stringArray(forKey: customURLsKey), urls.count == 4 {
            windowURLs = urls
        }
        if let bm = UserDefaults.standard.stringArray(forKey: bookmarksKey) {
            bookmarks = bm
        }
        // 广告拦截配置
        if UserDefaults.standard.object(forKey: adBlockKey) == nil {
            adBlockEnabled = true // 默认开启
        } else {
            adBlockEnabled = UserDefaults.standard.bool(forKey: adBlockKey)
        }
        if let custom = UserDefaults.standard.stringArray(forKey: customAdDomainsKey) {
            customAdDomains = custom
        }
        // UA配置
        currentUAIndex = UserDefaults.standard.integer(forKey: uaIndexKey)
        if currentUAIndex >= uaPresets.count { currentUAIndex = 0 }
    }
    private func saveCustomConfig() {
        UserDefaults.standard.set(windowTitles, forKey: customTitlesKey)
        UserDefaults.standard.set(windowURLs, forKey: customURLsKey)
    }
    // MARK: - Toast提示
    private func showToast(_ message: String) {
        let toast = UILabel(frame: CGRect(x: 0, y: 0, width: 250, height: 40))
        toast.center = CGPoint(x: view.bounds.width / 2, y: view.bounds.height - 120)
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        toast.textColor = .white
        toast.textAlignment = .center
        toast.font = .systemFont(ofSize: 13)
        toast.text = message
        toast.layer.cornerRadius = 20
        toast.clipsToBounds = true
        toast.numberOfLines = 2
        toast.alpha = 0
        view.addSubview(toast)
        UIView.animate(withDuration: 0.3, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.5, options: [], animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
    // MARK: - 广告&追踪拦截（带CF白名单）
    private func compileAdBlockRules() {
        // 广告/追踪域名拦截（url-filter匹配目标域名，不影响主流网站自身资源）
        let adDomains = [
            "doubleclick\\.net",
            "googleadservices\\.com",
            "googlesyndication\\.com",
            "googletagmanager\\.com",
            "google-analytics\\.com",
            "analytics\\.google\\.com",
            "pagead2\\.googlesyndication\\.com",
            "amazon-adsystem\\.com",
            "a9\\.com",
            "adnxs\\.com",
            "adform\\.net",
            "adform\\.com",
            "advertising\\.com",
            "smartadserver\\.com",
            "pubmatic\\.com",
            "openx\\.net",
            "rubiconproject\\.com",
            "casalemedia\\.com",
            "indexexchange\\.com",
            "magnite\\.com",
            "spotxchange\\.com",
            "spotx\\.tv",
            "freewheel\\.tv",
            "criteo\\.com",
            "criteo\\.net",
            "taboola\\.com",
            "outbrain\\.com",
            "mgid\\.com",
            "revcontent\\.com",
            "zergnet\\.com",
            "dianomi\\.com",
            "nativo\\.com",
            "sharethrough\\.com",
            "plista\\.com",
            "adblade\\.com",
            "scorecardresearch\\.com",
            "quantserve\\.com",
            "nr-data\\.net",
            "newrelic\\.com",
            "hotjar\\.com",
            "mouseflow\\.com",
            "clarity\\.ms",
            "adroll\\.com",
            "mathtag\\.com",
            "2mdn\\.net",
            "atdmt\\.com",
            "flashtalking\\.com",
            "moatads\\.com",
            "moat\\.com",
            "sovrn\\.com",
            "teads\\.tv",
            "thetradedesk\\.com",
            "triplelift\\.net",
            "yieldmo\\.com",
            "adsrvr\\.org",
            "bluekai\\.com",
            "chartbeat\\.com",
            "comscore\\.com",
            "crazyegg\\.com",
            "demdex\\.net",
            "eloqua\\.com",
            "everesttech\\.net",
            "heapanalytics\\.com",
            "imrworldwide\\.com",
            "krxd\\.net",
            "marketo\\.com",
            "nielsen\\.com",
            "omtrdc\\.net",
            "optimizely\\.com",
            "quantcast\\.com",
            "sailthru\\.com",
            "serving-sys\\.com",
            "sitecatalyst\\.com",
            "tapad\\.com",
            "tellapart\\.com",
            "truste\\.com",
            "turn\\.com",
            "webtrends\\.com",
            "zeotap\\.com",
            "exponential\\.com",
            "falkag\\.net",
            "innovid\\.com",
            "jivox\\.com",
            "kargo\\.com",
            "narrative\\.io",
            "onetag\\.com",
            "pixfuture\\.com",
            "seedtag\\.com",
            "zemanta\\.com",
            "agkn\\.com",
            "amgdgt\\.com",
            "bx1x\\.com",
            "coremetrics\\.com",
            "cquotient\\.com",
            "effectivemeasure\\.net",
            "episerver\\.net",
            "exelator\\.com",
            "francisdrake\\.com",
            "lendingtree\\.com",
            "liveintent\\.com",
            "lnkd\\.licdn\\.com",
            "maxmind\\.com",
            "ml314\\.com",
            "navegg\\.com",
            "px-cloud\\.net",
            "retargetly\\.com",
            "salesforce\\.com",
            "simpli\\.fi",
            "smadex\\.com",
            "stickyadstv\\.com",
            "unrulymedia\\.com",
            "veinteractive\\.com",
            "vindicosuite\\.com",
            "wunderkind\\.co",
            "yandex\\.ru",
            "2o7\\.net",
            "facebook\\.net",
            "connect\\.facebook\\.net",
            "ads\\.twitter\\.com",
            "analytics\\.twitter\\.com",
            "ct\\.pinterest\\.com",
            "sc-static\\.net",
            "tiktokcdn\\.com",
            "scontent\\.cdninstagram\\.com",
            "ljbkvoe\\.com",
            "alicdn\\.com",
            "33across\\.com",
            "abtasty\\.com",
            "adcolony\\.com",
            "addthis\\.com",
            "addthis\\.net",
            "adkernel\\.com",
            "admixer\\.net",
            "adobedtm\\.com",
            "adplex\\.com",
            "adreactor\\.com",
            "adsymptotic\\.com",
            "adtelligent\\.com",
            "adunity\\.com",
            "adversal\\.com",
            "adzerk\\.com",
            "affiliatewindow\\.com",
            "alexametrics\\.com",
            "amp-analytics\\.com",
            "aniview\\.com",
            "appboy\\.com",
            "appnexus\\.com",
            "appodeal\\.com",
            "appsflyer\\.com",
            "atlas\\.com",
            "avocarrot\\.com",
            "awin\\.com",
            "beemray\\.com",
            "bellmetric\\.com",
            "betrad\\.com",
            "bidswitch\\.net",
            "bizo\\.com",
            "bkrtx\\.com",
            "blismedia\\.com",
            "blogads\\.com",
            "blueconic\\.com",
            "bm3\\.com",
            "boomerang\\.com",
            "branch\\.io",
            "braze\\.com",
            "bridge\\.com",
            "brilig\\.com",
            "btloader\\.com",
            "burstly\\.com",
            "bytedance\\.com",
            "cauly\\.co\\.kr",
            "cedexis\\.com",
            "centro\\.net",
            "chango\\.com",
            "cint\\.com",
            "clck\\.ru",
            "clickability\\.com",
            "clickbooth\\.com",
            "clickdensity\\.com",
            "clickfire\\.com",
            "clickforensics\\.com",
            "clickpoint\\.com",
            "clicksor\\.com",
            "clicktale\\.com",
            "cloudflareinsights\\.com",
            "cobalten\\.com",
            "codefuel\\.com",
            "colossus\\.com",
            "comet\\.com",
            "commissionfactory\\.com",
            "commissionjunction\\.com",
            "compete\\.com",
            "contentad\\.net",
            "conversant\\.com",
            "cookiebot\\.com",
            "crashlytics\\.com",
            "crowdtangle\\.com",
            "crwdcntrl\\.net",
            "curalate\\.com",
            "custora\\.com",
            "dable\\.io",
            "datalogix\\.com",
            "datami\\.com",
            "dataxu\\.com",
            "dealply\\.com",
            "decibel\\.com",
            "deepintent\\.com",
            "demandbase\\.com",
            "denakop\\.com",
            "digitalriver\\.com",
            "disqus\\.com",
            "doubleclick\\.com",
            "doubleverify\\.com",
            "dstillery\\.com",
            "dtmp\\.com",
            "dynamicyield\\.com",
            "dynatrace\\.com",
            "e-planning\\.net",
            "eadv\\.com",
            "effiliation\\.com",
            "emjcd\\.com",
            "epom\\.com",
            "epsilon\\.com",
            "eraindex\\.com",
            "ero-advertising\\.com",
            "estat\\.com",
            "etracker\\.com",
            "eulerian\\.net",
            "exco\\.com",
            "exitexchange\\.com",
            "exosrv\\.com",
            "experian\\.com",
            "explorads\\.com",
            "eyeview\\.com",
            "faceit\\.com",
            "falktech\\.com",
            "fastclick\\.com",
            "feedad\\.com",
            "fetchback\\.com",
            "firstimpression\\.io",
            "flurry\\.com",
            "forter\\.com",
            "frequence\\.com",
            "fwmrm\\.net",
            "gameanalytics\\.com",
            "gammass\\.com",
            "geistm\\.com",
            "getclicky\\.com",
            "getintent\\.com",
            "giphy\\.com",
            "glome\\.com",
            "gostats\\.com",
            "gracenote\\.com",
            "graphiq\\.com",
            "gravity\\.com",
            "gravity4\\.com",
            "gumgum\\.com",
            "gwallet\\.com",
            "h-adash\\.com",
            "h-bid\\.com",
            "h-cdn\\.com",
            "habbly\\.com",
            "headr\\.com",
            "heatma\\.com",
            "helios\\.com",
            "hellobar\\.com",
            "hitbox\\.com",
            "hitwise\\.com",
            "hive\\.com",
            "hochburg\\.com",
            "hometracks\\.com",
            "hs-analytics\\.net",
            "hsadspixel\\.net",
            "hubspot\\.com",
            "hulu\\.com",
            "hunch\\.com",
            "hungama\\.com",
            "i-mobile\\.co\\.jp",
            "iab\\.com",
            "iclick\\.com",
            "icontext\\.com",
            "id5-sync\\.com",
            "id5\\.io",
            "ideo\\.com",
            "ignition\\.com",
            "imonomy\\.com",
            "impact\\.com",
            "impactradius\\.com",
            "impdesk\\.com",
            "inmobi\\.com",
            "inmobicdn\\.net",
            "innity\\.com",
            "inskin\\.com",
            "insightexpress\\.com",
            "inspectlet\\.com",
            "instana\\.com",
            "integralads\\.com",
            "intentiq\\.com",
            "intergi\\.com",
            "intowow\\.com",
            "invitemedia\\.com",
            "ipredictive\\.com",
            "iqjmp\\.com",
            "ironsrc\\.com",
            "istrack\\.com",
            "itemscale\\.com",
            "jcnielsen\\.com",
            "jdoqocy\\.com",
            "jumptap\\.com",
            "justpremium\\.com",
            "kenshoo\\.com",
            "kewego\\.com",
            "kissmetrics\\.com",
            "kissinsights\\.com",
            "klaviyo\\.com",
            "klick\\.com",
            "knorex\\.com",
            "kochava\\.com",
            "komli\\.com",
            "kraken\\.com",
            "ksmobile\\.com",
            "l90\\.com",
            "leadbolt\\.com",
            "leadfeeder\\.com",
            "leadgen\\.com",
            "leady\\.com",
            "lifecycle\\.com",
            "liftoff\\.com",
            "lightbox\\.com",
            "linksynergy\\.com",
            "livechat\\.com",
            "liveperson\\.com",
            "lockerdome\\.com",
            "loggly\\.com",
            "lognormal\\.com",
            "loopme\\.com",
            "lotame\\.com",
            "luminate\\.com",
            "luckyorange\\.com",
            "madgex\\.com",
            "marin\\.com",
            "marinsoftware\\.com",
            "maropost\\.com",
            "martini\\.com",
            "mass2\\.com",
            "match2blue\\.com",
            "maxpoint\\.com",
            "maxymiser\\.com",
            "mbridge\\.com",
            "mcanvas\\.com",
            "mcookie\\.com",
            "mdotm\\.com",
            "mediamath\\.com",
            "media\\.net",
            "mediatech\\.com",
            "meltwater\\.com",
            "merchenta\\.com",
            "microad\\.com\\.cn",
            "microad\\.co\\.jp",
            "mookie1\\.com",
            "mobilefuse\\.com",
            "mobclix\\.com",
            "mobfox\\.com",
            "mobgold\\.com",
            "mopub\\.com",
            "mookie\\.com",
            "motive\\.com",
            "mparticle\\.com",
            "mtag\\.com",
            "mtr\\.com",
            "multiply\\.com",
            "munchkin\\.com",
            "mydas\\.com",
            "myads\\.com",
            "myspace\\.com",
            "navdmp\\.com",
            "neustar\\.com",
            "ninthdecimal\\.com",
            "nimbus\\.com",
            "nitropay\\.com",
            "nobid\\.com",
            "nominum\\.com",
            "nugg\\.com",
            "nurago\\.com",
            "nurl\\.com",
            "oath\\.com",
            "objective\\.com",
            "oculus\\.com",
            "offer\\.com",
            "oflow\\.com"
        ]
        var rules: [[String: Any]] = []
        // 广告拦截总开关：关闭时移除所有规则
        guard adBlockEnabled else {
            WKContentRuleListStore.default().removeContentRuleList(forIdentifier: "AdBlockRules") { _ in
                DispatchQueue.main.async {
                    for wv in self.webViews {
                        wv.configuration.userContentController.removeAllContentRuleLists()
                    }
                }
            }
            return
        }
        // 全局图片拦截（所有网站的所有图片）
        if UserDefaults.standard.bool(forKey: globalImageBlockKey) {
            rules.append([
                "trigger": [
                    "resource-type": ["image"]
                ],
                "action": ["type": "block"]
            ])
        }
        // 合并内置黑名单 + 用户自定义域名
        let allDomains = adDomains + customAdDomains
        for domain in allDomains {
            rules.append([
                "trigger": [
                    "url-filter": domain,
                    "resource-type": ["image", "style-sheet", "script", "font", "raw"]
                ],
                "action": ["type": "block"]
            ])
        }
        // CF白名单：不拦截dash.cloudflare.com的任何资源
        rules.append([
            "trigger": [
                "url-filter": "dash\\.cloudflare\\.com",
                "resource-type": ["image", "style-sheet", "script", "font", "raw"]
            ],
            "action": ["type": "ignore-previous-rules"]
        ])
        // 序列化为JSON
        guard let jsonData = try? JSONSerialization.data(withJSONObject: rules, options: []),
              let rulesJSON = String(data: jsonData, encoding: .utf8) else {
            print("广告拦截规则JSON序列化失败")
            return
        }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "AdBlockRules", encodedContentRuleList: rulesJSON) { [weak self] ruleList, error in
            guard let ruleList = ruleList else {
                print("广告拦截规则编译失败: \(error?.localizedDescription ?? "未知")")
                return
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                for wv in self.webViews {
                    // 先移除旧规则，再添加新规则
                    wv.configuration.userContentController.removeAllContentRuleLists()
                    wv.configuration.userContentController.add(ruleList)
                }
                // 规则更新后重新加载当前页面，确保立即生效
                if self.currentWebView.url != nil {
                    self.currentWebView.reload()
                }
            }
        }
    }
    // MARK: - DNS预解析
    private func prefetchDNS(for urlString: String) {
        guard let url = URL(string: urlString) else { return }
        // 发送一个超时极短的请求触发系统DNS解析并缓存，立即取消不下载数据
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.httpMethod = "HEAD"
        let task = URLSession.shared.dataTask(with: request) { _, _, _ in }
        task.resume()
        // 200ms后取消，只需DNS解析完成
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            task.cancel()
        }
    }
    // MARK: - Pre-Connect TCP预连接
    private func preConnect(for urlString: String) {
        guard let url = URL(string: urlString), let host = url.host else { return }
        let port = url.scheme == "https" ? 443 : 80
        // 使用URLSession streamTask建立TCP/TLS连接，系统会复用连接池
        let task = URLSession.shared.streamTask(withHostName: host, port: port)
        task.resume()
        // 连接建立后立即取消，保留在连接池中
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            task.cancel()
        }
    }
    @objc private func tabTapped(_ sender: UIButton) {
        switchToTab(index: sender.tag)
    }
    /// 双击标签返回默认主页
    @objc private func tabDoubleTapped(_ gesture: UITapGestureRecognizer) {
        guard let btn = gesture.view as? UIButton else { return }
        let index = btn.tag
        switchToTab(index: index)
        guard let url = URL(string: windowURLs[index]) else { return }
        webViews[index].load(URLRequest(url: url))
        showToast("已返回\(windowTitles[index])主页")
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
        // DNS预解析 + TCP预连接（加速页面加载）
        let targetURL = windowURLs[index]
        prefetchDNS(for: targetURL)
        preConnect(for: targetURL)
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
            // 禁止媒体自动播放（需用户手动点击）
            config.mediaTypesRequiringUserActionForPlayback = .all
            config.defaultWebpagePreferences.allowsContentJavaScript = true
            // 持久化数据存储（缓存/cookie）
            config.websiteDataStore = .default()
            // 后台动画节流JS：页面不可见时暂停requestAnimationFrame
            let throttleJS = """
            (function(){var _raf=window.requestAnimationFrame;var rafQueue=[];document.addEventListener('visibilitychange',function(){if(document.hidden){window.requestAnimationFrame=function(cb){rafQueue.push(cb);return rafQueue.length;};}else{window.requestAnimationFrame=_raf;rafQueue.forEach(function(cb){_raf(cb);});rafQueue=[];}});})();
            """
            let throttleScript = WKUserScript(source: throttleJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(throttleScript)
            // 强制网页可缩放：覆盖viewport禁止缩放的限制
            let zoomJS = "(function(){var meta=document.querySelector('meta[name=viewport]');if(meta){meta.content='width=device-width,initial-scale=1.0,minimum-scale=0.5,maximum-scale=10.0,user-scalable=yes';}else{var m=document.createElement('meta');m.name='viewport';m.content='width=device-width,initial-scale=1.0,minimum-scale=0.5,maximum-scale=10.0,user-scalable=yes';document.head.appendChild(m);}})();"
            let zoomScript = WKUserScript(source: zoomJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(zoomScript)
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.allowsBackForwardNavigationGestures = false
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.scrollView.bounces = true
            webView.scrollView.delegate = self
            // 强制缩放范围
            webView.scrollView.minimumZoomScale = 0.5
            webView.scrollView.maximumZoomScale = 5.0
            webView.isHidden = (i != 0)
            webViewContainer.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: webViewContainer.topAnchor),
                webView.leadingAnchor.constraint(equalTo: webViewContainer.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: webViewContainer.trailingAnchor),
                webView.bottomAnchor.constraint(equalTo: webViewContainer.bottomAnchor)
            ])
            webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)
            // 应用自定义UA
            webView.customUserAgent = uaPresets[currentUAIndex]
            webViews.append(webView)
            setupCustomRefresh(for: webView, index: i)
        }
        // webView全部创建完成后，编译广告拦截规则
        compileAdBlockRules()
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
            // 启动时预解析所有窗口DNS
            prefetchDNS(for: urlString)
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
    // MARK: - 右边缘下滑功能菜单
    private func setupEdgeMenu() {
        // 菜单宽度：60%（约220pt），减少对网页内容遮挡
        let menuWidth = view.bounds.width * 0.60
        // 遮罩层：点击菜单外任意区域收回菜单
        edgeMenuOverlay = UIButton(type: .system)
        edgeMenuOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        edgeMenuOverlay.alpha = 0
        edgeMenuOverlay.isHidden = true
        edgeMenuOverlay.addTarget(self, action: #selector(closeEdgeMenu), for: .touchUpInside)
        edgeMenuOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edgeMenuOverlay)
        NSLayoutConstraint.activate([
            edgeMenuOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            edgeMenuOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            edgeMenuOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            edgeMenuOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        // 菜单面板（无阴影，避免隐藏时边缘露线）
        edgeMenuView = UIView()
        edgeMenuView.backgroundColor = .systemBackground
        edgeMenuView.layer.cornerRadius = 16
        edgeMenuView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        edgeMenuView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(edgeMenuView)
        
        edgeMenuLeadingConstraint = edgeMenuView.leadingAnchor.constraint(equalTo: view.trailingAnchor)
        NSLayoutConstraint.activate([
            edgeMenuLeadingConstraint,
            edgeMenuView.topAnchor.constraint(equalTo: view.topAnchor),
            edgeMenuView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            edgeMenuView.widthAnchor.constraint(equalToConstant: menuWidth)
        ])
        
        // 标题栏
        let titleLabel = UILabel()
        titleLabel.text = "功能菜单"
        titleLabel.font = .boldSystemFont(ofSize: 18)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        edgeMenuView.addSubview(titleLabel)
        
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeEdgeMenu), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        edgeMenuView.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: edgeMenuView.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: edgeMenuView.leadingAnchor, constant: 20),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: edgeMenuView.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // 功能按钮列表
        let functions: [(String, String, Selector)] = [
            ("bookmark", "增加书签", #selector(edgeMenuAddBookmark)),
            ("book", "书签列表", #selector(edgeMenuShowBookmarks)),
            ("clock", "历史记录", #selector(edgeMenuShowHistory)),
            ("square.and.arrow.down", "下载管理", #selector(edgeMenuShowDownloads)),
            ("photo", "全局图片拦截", #selector(edgeMenuToggleImageBlock)),
            ("globe", "UA 切换", #selector(edgeMenuSwitchUA)),
            ("hand.raised", "广告黑名单", #selector(edgeMenuManageAdBlock)),
            ("trash", "清空当前站点缓存", #selector(edgeMenuClearSiteCache)),
            ("trash.fill", "一键清空缓存", #selector(edgeMenuClearAllCache)),
            ("gear", "设置", #selector(edgeMenuShowSettings))
        ]
        
        var previousView: UIView = titleLabel
        for (icon, title, action) in functions {
            let button = createMenuButton(icon: icon, title: title, action: action)
            edgeMenuView.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: previousView.bottomAnchor, constant: previousView == titleLabel ? 20 : 0),
                button.leadingAnchor.constraint(equalTo: edgeMenuView.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: edgeMenuView.trailingAnchor),
                button.heightAnchor.constraint(equalToConstant: 48)
            ])
            previousView = button
        }
    }
    
    private func createMenuButton(icon: String, title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = .label
        iconView.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 16)
        label.textColor = .label
        label.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(iconView)
        button.addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 20),
            iconView.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 15),
            label.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
    
    @objc private func closeEdgeMenu() {
        setEdgeMenu(open: false)
    }
    
    // MARK: - 边缘菜单功能
    @objc private func edgeMenuAddBookmark() {
        closeEdgeMenu()
        // 调用已有的添加书签功能
        if let url = currentWebView.url?.absoluteString, let title = currentWebView.title {
            var bookmarks = UserDefaults.standard.array(forKey: "savedBookmarks") as? [[String: String]] ?? []
            bookmarks.append(["title": title, "url": url])
            UserDefaults.standard.set(bookmarks, forKey: "savedBookmarks")
            showToast("已添加书签")
        }
    }
    
    @objc private func edgeMenuShowBookmarks() {
        closeEdgeMenu()
        let bookmarks = UserDefaults.standard.array(forKey: "savedBookmarks") as? [[String: String]] ?? []
        let alert = UIAlertController(title: "书签列表", message: nil, preferredStyle: .actionSheet)
        for bm in bookmarks {
            alert.addAction(UIAlertAction(title: bm["title"] ?? bm["url"] ?? "", style: .default) { _ in
                if let url = URL(string: bm["url"] ?? "") {
                    self.currentWebView.load(URLRequest(url: url))
                }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func edgeMenuShowHistory() {
        closeEdgeMenu()
        // 显示历史记录（使用WKWebView的backForwardList）
        let history = currentWebView.backForwardList
        let alert = UIAlertController(title: "历史记录", message: "最近访问", preferredStyle: .actionSheet)
        for item in history.backList.reversed().prefix(10) {
            alert.addAction(UIAlertAction(title: item.title ?? item.url.absoluteString, style: .default) { _ in
                self.currentWebView.go(to: item)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func edgeMenuShowDownloads() {
        closeEdgeMenu()
        let panel = DownloadPanelViewController()
        panel.modalPresentationStyle = .pageSheet
        if let sheet = panel.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = false
        }
        present(panel, animated: true)
    }
    
    @objc private func edgeMenuToggleImageBlock() {
        closeEdgeMenu()
        toggleGlobalImageBlock()
    }
    
    @objc private func edgeMenuSwitchUA() {
        closeEdgeMenu()
        // 循环切换UA
        currentUAIndex = (currentUAIndex + 1) % uaPresets.count
        UserDefaults.standard.set(currentUAIndex, forKey: uaIndexKey)
        for wv in webViews {
            wv.customUserAgent = uaPresets[currentUAIndex]
        }
        showToast("UA已切换：\(uaPresets[currentUAIndex].prefix(20))...")
        currentWebView.reload()
    }
    
    @objc private func edgeMenuManageAdBlock() {
        closeEdgeMenu()
        showCustomAdManager()
    }
    
    @objc private func edgeMenuClearSiteCache() {
        closeEdgeMenu()
        if let host = currentWebView.url?.host {
            fourLevelCache.clearCacheForSite(host)
            showToast("已清理 \(host) 缓存")
            currentWebView.reload()
        }
    }
    
    @objc private func edgeMenuClearAllCache() {
        closeEdgeMenu()
        fourLevelCache.removeAllCachedResponses()
        showToast("已清空全部缓存")
    }
    
    @objc private func edgeMenuShowSettings() {
        closeEdgeMenu()
        // 显示设置菜单（复用翻译键长按菜单）
        handleTranslateLongPress(UILongPressGestureRecognizer())
    }
    
    private func setEdgeMenu(open: Bool) {
        edgeMenuIsOpen = open
        let menuWidth = view.bounds.width * 0.60
        edgeMenuLeadingConstraint.constant = open ? -menuWidth : 0
        if open {
            edgeMenuOverlay.isHidden = false
        }
        UIView.animate(withDuration: open ? 0.35 : 0.2, delay: 0,
                       usingSpringWithDamping: open ? 0.72 : 1.0,
                       initialSpringVelocity: open ? 0.8 : 0,
                       options: .curveEaseInOut) {
            self.edgeMenuOverlay.alpha = open ? 1 : 0
            self.view.layoutIfNeeded()
        } completion: { _ in
            if !open { self.edgeMenuOverlay.isHidden = true }
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
        // 双击左下角→底部，双击右下角→顶部
        let screenDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleScreenDoubleTap(_:)))
        screenDoubleTap.numberOfTapsRequired = 2
        screenDoubleTap.cancelsTouchesInView = false
        screenDoubleTap.delegate = self
        view.addGestureRecognizer(screenDoubleTap)
        // 双击翻译按钮→刷新当前网页
        let translateDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleTranslateDoubleTap(_:)))
        translateDoubleTap.numberOfTapsRequired = 2
        translateButton.addGestureRecognizer(translateDoubleTap)
        // 长按翻译按钮0.8秒→弹出设置菜单
        let translateLongPress = UILongPressGestureRecognizer(target: self, action: #selector(handleTranslateLongPress(_:)))
        translateLongPress.minimumPressDuration = 0.8
        translateButton.addGestureRecognizer(translateLongPress)
        // 右边缘下滑→功能菜单
        let edgePan = UIPanGestureRecognizer(target: self, action: #selector(handleEdgeMenuPan(_:)))
        edgePan.delegate = self
        edgePan.cancelsTouchesInView = false
        view.addGestureRecognizer(edgePan)
        // 屏幕底部中央双击→网页内文字搜索
        let bottomCenterDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleBottomCenterDoubleTap(_:)))
        bottomCenterDoubleTap.numberOfTapsRequired = 2
        bottomCenterDoubleTap.cancelsTouchesInView = false
        bottomCenterDoubleTap.delegate = self
        view.addGestureRecognizer(bottomCenterDoubleTap)
    }
    // MARK: - 双击手势：左下角到底部，右下角到顶部
    @objc private func handleScreenDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let bottomThreshold: CGFloat = view.bounds.height * 0.75
        let horizontalMid = view.bounds.width / 2
        guard location.y > bottomThreshold else { return }
        if location.x > horizontalMid {
            // 右下角→顶部
            currentWebView.scrollView.setContentOffset(CGPoint(x: 0, y: -currentWebView.scrollView.contentInset.top), animated: true)
        } else {
            // 左下角→底部
            let bottomOffset = CGPoint(x: 0, y: currentWebView.scrollView.contentSize.height - currentWebView.scrollView.bounds.height + currentWebView.scrollView.contentInset.bottom)
            currentWebView.scrollView.setContentOffset(bottomOffset, animated: true)
        }
    }
    // MARK: - 双击翻译按钮→刷新
    @objc private func handleTranslateDoubleTap(_ gesture: UITapGestureRecognizer) {
        currentWebView.reload()
        showToast("已刷新")
    }
    // MARK: - 长按翻译按钮→设置菜单
    @objc private func handleTranslateLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let alert = UIAlertController(title: "浏览器设置", message: nil, preferredStyle: .actionSheet)
        // 广告拦截开关
        let adBlockTitle = adBlockEnabled ? "广告拦截：已开启（点击关闭）" : "广告拦截：已关闭（点击开启）"
        alert.addAction(UIAlertAction(title: adBlockTitle, style: .default) { _ in
            self.toggleAdBlock()
        })
        // 自定义广告域名
        alert.addAction(UIAlertAction(title: "自定义广告黑名单", style: .default) { _ in
            self.manageCustomAdDomains()
        })
        // UA切换
        let uaTitle = "UA切换（当前：\(uaNames[currentUAIndex])）"
        alert.addAction(UIAlertAction(title: uaTitle, style: .default) { _ in
            self.switchUA()
        })
        // 权限设置
        alert.addAction(UIAlertAction(title: "🔐 权限设置（一键开启全部）", style: .default) { _ in
            self.showPermissionManager()
        })
        // 第三方登录跳转确认开关
        let loginConfirm = UserDefaults.standard.object(forKey: self.loginConfirmKey) as? Bool ?? true
        let loginTitle = loginConfirm ? "🔗 登录跳转确认：已开启（点击关闭）" : "🔗 登录跳转确认：已关闭（点击开启）"
        alert.addAction(UIAlertAction(title: loginTitle, style: .default) { _ in
            let current = UserDefaults.standard.object(forKey: self.loginConfirmKey) as? Bool ?? true
            UserDefaults.standard.set(!current, forKey: self.loginConfirmKey)
            self.showToast(!current ? "登录跳转确认已开启" : "已开启静默跳转")
        })
        // 全局图片拦截开关
        let globalImageBlock = UserDefaults.standard.bool(forKey: self.globalImageBlockKey)
        let globalImageTitle = globalImageBlock ? "🖼 全局图片拦截：已开启（点击关闭）" : "🖼 全局拦截所有图片"
        alert.addAction(UIAlertAction(title: globalImageTitle, style: .default) { _ in
            self.toggleGlobalImageBlock()
        })
        // 四级缓存管理
        alert.addAction(UIAlertAction(title: "💾 缓存管理（四级缓存）", style: .default) { _ in
            self.showCacheManager()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
            popover.sourceRect = translateButton.bounds
        }
        present(alert, animated: true)
    }
    // MARK: - 广告拦截开关
    private func toggleAdBlock() {
        adBlockEnabled.toggle()
        UserDefaults.standard.set(adBlockEnabled, forKey: adBlockKey)
        compileAdBlockRules()
        showToast(adBlockEnabled ? "广告拦截已开启" : "广告拦截已关闭")
    }
    // MARK: - 自定义广告域名管理
    private func manageCustomAdDomains() {
        showCustomAdManager()
    }
    // MARK: - 全局图片拦截
    private func toggleGlobalImageBlock() {
        let current = UserDefaults.standard.bool(forKey: globalImageBlockKey)
        UserDefaults.standard.set(!current, forKey: globalImageBlockKey)
        compileAdBlockRules()
        if !current {
            showToast("已开启全局图片拦截，刷新后生效")
            currentWebView.reload()
        } else {
            showToast("已关闭全局图片拦截")
        }
    }
    // MARK: - 四级缓存管理
    private func showCacheManager() {
        let sizes = fourLevelCache.cacheSize()
        let tempMB = Double(sizes.temp) / 1024 / 1024
        let staticMB = Double(sizes.static) / 1024 / 1024
        let alert = UIAlertController(
            title: "💾 四级缓存管理",
            message: String(format: "一级内存：80MB上限\n二级瞬时缓存：%.1fMB（30分钟过期）\n三级持久缓存：%.1fMB（7天过期）", tempMB, staticMB),
            preferredStyle: .actionSheet
        )
        alert.addAction(UIAlertAction(title: "🗑 清理全部缓存", style: .destructive) { _ in
            self.fourLevelCache.removeAllCachedResponses()
            self.showToast("已清理全部四级缓存")
        })
        alert.addAction(UIAlertAction(title: "⚡ 仅清理内存缓存", style: .default) { _ in
            self.fourLevelCache.clearMemoryCache()
            self.showToast("已清理一级内存缓存")
        })
        alert.addAction(UIAlertAction(title: "📄 仅清理动态页面缓存", style: .default) { _ in
            self.fourLevelCache.clearTempCache()
            self.showToast("已清理二级瞬时缓存")
        })
        alert.addAction(UIAlertAction(title: "🖼 仅清理静态资源缓存", style: .default) { _ in
            self.fourLevelCache.clearStaticCache()
            self.showToast("已清理三级持久缓存")
        })
        if let host = currentWebView.url?.host {
            alert.addAction(UIAlertAction(title: "📍 清理当前站点缓存（\(host)）", style: .default) { _ in
                self.fourLevelCache.clearCacheForSite(host)
                self.showToast("已清理 \(host) 缓存")
                self.currentWebView.reload()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
            popover.sourceRect = translateButton.bounds
        }
        present(alert, animated: true)
    }
    /// 统一的自定义黑名单管理界面：列表+添加+删除+清空
    private func showCustomAdManager() {
        let alert = UIAlertController(
            title: "自定义广告黑名单",
            message: "共 \(customAdDomains.count) 条，支持域名/完整路径/通配符*",
            preferredStyle: .actionSheet
        )
        // 域名列表（显示可读格式，点击弹出编辑/删除菜单）
        for (i, domain) in customAdDomains.enumerated() {
            let readable = domain.replacingOccurrences(of: "\\.", with: ".").replacingOccurrences(of: ".*", with: "*")
            alert.addAction(UIAlertAction(title: "✏️ \(readable)", style: .default) { _ in
                self.showEditDomainAlert(index: i, original: domain, readable: readable)
            })
        }
        // 添加新域名
        alert.addAction(UIAlertAction(title: "➕ 添加新域名", style: .default) { _ in
            self.showAddDomainAlert()
        })
        // 清空全部
        if !customAdDomains.isEmpty {
            alert.addAction(UIAlertAction(title: "🗑 清空全部", style: .destructive) { _ in
                let confirm = UIAlertController(title: "确认清空", message: "将删除全部 \(self.customAdDomains.count) 条自定义域名", preferredStyle: .alert)
                confirm.addAction(UIAlertAction(title: "确认清空", style: .destructive) { _ in
                    self.customAdDomains.removeAll()
                    UserDefaults.standard.set(self.customAdDomains, forKey: self.customAdDomainsKey)
                    self.compileAdBlockRules()
                    self.showToast("已清空全部自定义域名")
                })
                confirm.addAction(UIAlertAction(title: "取消", style: .cancel))
                self.present(confirm, animated: true)
            })
        }
        alert.addAction(UIAlertAction(title: "完成", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
            popover.sourceRect = translateButton.bounds
        }
        present(alert, animated: true)
    }
    /// 编辑/删除域名弹窗
    private func showEditDomainAlert(index: Int, original: String, readable: String) {
        let alert = UIAlertController(title: "编辑规则", message: "修改或删除该拦截规则", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = readable
            tf.font = .systemFont(ofSize: 14)
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "保存修改", style: .default) { _ in
            guard let input = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else {
                self.showCustomAdManager()
                return
            }
            // 重新解析输入
            var raw = input.lowercased()
            raw = raw.replacingOccurrences(of: "https://", with: "")
            raw = raw.replacingOccurrences(of: "http://", with: "")
            if raw.hasPrefix("www.") { raw = String(raw.dropFirst(4)) }
            if let colonRange = raw.range(of: ":"), let slashRange = raw.range(of: "/") {
                if colonRange.lowerBound < slashRange.lowerBound {
                    raw = String(raw[..<colonRange.lowerBound]) + String(raw[slashRange.lowerBound...])
                }
            }
            raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            var domainPart = raw
            var pathPart = ""
            if let slashRange = raw.range(of: "/") {
                domainPart = String(raw[..<slashRange.lowerBound])
                pathPart = String(raw[slashRange.lowerBound...])
            }
            guard domainPart.contains(".") else {
                self.showToast("无效输入")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showEditDomainAlert(index: index, original: original, readable: readable) }
                return
            }
            domainPart = domainPart.replacingOccurrences(of: ".", with: "\\.")
            if !pathPart.isEmpty {
                pathPart = pathPart.replacingOccurrences(of: ".", with: "\\.")
                pathPart = pathPart.replacingOccurrences(of: "*", with: ".*")
            }
            let newRule = domainPart + pathPart
            self.customAdDomains[index] = newRule
            UserDefaults.standard.set(self.customAdDomains, forKey: self.customAdDomainsKey)
            self.compileAdBlockRules()
            self.showToast("规则已更新")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showCustomAdManager()
            }
        })
        alert.addAction(UIAlertAction(title: "删除此规则", style: .destructive) { _ in
            self.customAdDomains.remove(at: index)
            UserDefaults.standard.set(self.customAdDomains, forKey: self.customAdDomainsKey)
            self.compileAdBlockRules()
            self.showToast("已删除：\(readable)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showCustomAdManager()
            }
        })
        alert.addAction(UIAlertAction(title: "返回列表", style: .cancel) { _ in
            self.showCustomAdManager()
        })
        present(alert, animated: true)
    }
    /// 编辑已有域名规则
    private func showEditDomainAlert(at index: Int, original: String, readable: String) {
        let alert = UIAlertController(title: "编辑规则", message: "修改后将替换原规则", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = readable
            tf.font = .systemFont(ofSize: 14)
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            guard let input = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else {
                self.showCustomAdManager()
                return
            }
            // 智能解析（与添加时相同）
            var raw = input.lowercased()
            raw = raw.replacingOccurrences(of: "https://", with: "")
            raw = raw.replacingOccurrences(of: "http://", with: "")
            if raw.hasPrefix("www.") { raw = String(raw.dropFirst(4)) }
            if let colonRange = raw.range(of: ":"), let slashRange = raw.range(of: "/") {
                if colonRange.lowerBound < slashRange.lowerBound {
                    raw = String(raw[..<colonRange.lowerBound]) + String(raw[slashRange.lowerBound...])
                }
            }
            raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            var domainPart = raw
            var pathPart = ""
            if let slashRange = raw.range(of: "/") {
                domainPart = String(raw[..<slashRange.lowerBound])
                pathPart = String(raw[slashRange.lowerBound...])
            }
            guard domainPart.contains(".") else {
                self.showToast("无效输入")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showEditDomainAlert(at: index, original: original, readable: readable) }
                return
            }
            domainPart = domainPart.replacingOccurrences(of: ".", with: "\\.")
            if !pathPart.isEmpty {
                pathPart = pathPart.replacingOccurrences(of: ".", with: "\\.")
                pathPart = pathPart.replacingOccurrences(of: "*", with: ".*")
            }
            let finalRule = domainPart + pathPart
            self.customAdDomains[index] = finalRule
            UserDefaults.standard.set(self.customAdDomains, forKey: self.customAdDomainsKey)
            self.compileAdBlockRules()
            let newReadable = finalRule.replacingOccurrences(of: "\\.", with: ".").replacingOccurrences(of: ".*", with: "*")
            self.showToast("已更新：\(newReadable)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showCustomAdManager() }
        })
        alert.addAction(UIAlertAction(title: "删除此规则", style: .destructive) { _ in
            self.customAdDomains.remove(at: index)
            UserDefaults.standard.set(self.customAdDomains, forKey: self.customAdDomainsKey)
            self.compileAdBlockRules()
            self.showToast("已删除：\(readable)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showCustomAdManager() }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in
            self.showCustomAdManager()
        })
        present(alert, animated: true)
    }
    /// 添加域名弹窗
    private func showAddDomainAlert() {
        let alert = UIAlertController(title: "添加域名", message: "可直接粘贴完整URL，自动清洗", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "域名或完整URL，如 ads.com/track/*"
            tf.font = .systemFont(ofSize: 14)
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
            tf.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "添加", style: .default) { _ in
            guard let input = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !input.isEmpty else {
                self.showCustomAdManager()
                return
            }
            // 智能解析：支持纯域名 和 域名+完整路径
            var raw = input.lowercased()
            raw = raw.replacingOccurrences(of: "https://", with: "")
            raw = raw.replacingOccurrences(of: "http://", with: "")
            if raw.hasPrefix("www.") { raw = String(raw.dropFirst(4)) }
            // 去掉端口号（域名后的:端口）
            if let colonRange = raw.range(of: ":"), let slashRange = raw.range(of: "/") {
                if colonRange.lowerBound < slashRange.lowerBound {
                    raw = String(raw[..<colonRange.lowerBound]) + String(raw[slashRange.lowerBound...])
                }
            }
            raw = raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            // 分离域名和路径
            var domainPart = raw
            var pathPart = ""
            if let slashRange = raw.range(of: "/") {
                domainPart = String(raw[..<slashRange.lowerBound])
                pathPart = String(raw[slashRange.lowerBound...])
            }
            guard domainPart.contains(".") else {
                self.showToast("无效输入，请输入域名或完整URL")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showAddDomainAlert() }
                return
            }
            // 转义域名中的点号
            domainPart = domainPart.replacingOccurrences(of: ".", with: "\\.")
            // 路径中的通配符*转换为正则.*，点号转义
            if !pathPart.isEmpty {
                pathPart = pathPart.replacingOccurrences(of: ".", with: "\\.")
                pathPart = pathPart.replacingOccurrences(of: "*", with: ".*")
            }
            // 组合最终正则：域名 + 路径（如有）
            let finalRule = domainPart + pathPart
            if !self.customAdDomains.contains(finalRule) {
                self.customAdDomains.append(finalRule)
                UserDefaults.standard.set(self.customAdDomains, forKey: self.customAdDomainsKey)
                self.compileAdBlockRules()
                let readable = finalRule.replacingOccurrences(of: "\\.", with: ".").replacingOccurrences(of: ".*", with: "*")
                self.showToast("已添加：\(readable)")
            } else {
                self.showToast("该规则已存在")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.showCustomAdManager()
            }
        })
        alert.addAction(UIAlertAction(title: "返回列表", style: .cancel) { _ in
            self.showCustomAdManager()
        })
        present(alert, animated: true)
    }
    // MARK: - 权限管理
    private func showPermissionManager() {
        let alert = UIAlertController(title: "权限管理", message: "一键开启所有浏览器所需权限", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "🚀 一键开启全部权限", style: .default) { _ in
            self.requestAllPermissions()
        })
        alert.addAction(UIAlertAction(title: "📷 相机/麦克风/相册", style: .default) { _ in
            self.requestMediaPermissions()
        })
        alert.addAction(UIAlertAction(title: "📍 定位权限", style: .default) { _ in
            self.requestLocationPermission()
        })
        alert.addAction(UIAlertAction(title: "🔔 通知权限", style: .default) { _ in
            self.requestNotificationPermission()
        })
        alert.addAction(UIAlertAction(title: "🎙 语音识别", style: .default) { _ in
            self.requestSpeechPermission()
        })
        alert.addAction(UIAlertAction(title: "📡 蓝牙/本地网络", style: .default) { _ in
            self.requestBluetoothPermission()
        })
        alert.addAction(UIAlertAction(title: "👤 追踪/通讯录/日历", style: .default) { _ in
            self.requestOtherPermissions()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
            popover.sourceRect = translateButton.bounds
        }
        present(alert, animated: true)
    }
    private func requestAllPermissions() {
        let group = DispatchGroup()
        var results: [String] = []
        // 相机
        group.enter()
        AVCaptureDevice.requestAccess(for: .video) { granted in
            results.append("相机: \(granted ? "✓" : "✗")")
            group.leave()
        }
        // 麦克风
        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            results.append("麦克风: \(granted ? "✓" : "✗")")
            group.leave()
        }
        // 相册
        group.enter()
        PHPhotoLibrary.requestAuthorization { status in
            results.append("相册: \(status == .authorized ? "✓" : "✗")")
            group.leave()
        }
        // 通知
        group.enter()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            results.append("通知: \(granted ? "✓" : "✗")")
            group.leave()
        }
        // 语音识别
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            results.append("语音识别: \(status == .authorized ? "✓" : "✗")")
            group.leave()
        }
        // 追踪
        group.enter()
        ATTrackingManager.requestTrackingAuthorization { status in
            results.append("追踪: \(status == .authorized ? "✓" : "✗")")
            group.leave()
        }
        // 通讯录
        group.enter()
        CNContactStore().requestAccess(for: .contacts) { granted, _ in
            results.append("通讯录: \(granted ? "✓" : "✗")")
            group.leave()
        }
        // 日历
        group.enter()
        EKEventStore().requestAccess(to: .event) { granted, _ in
            results.append("日历: \(granted ? "✓" : "✗")")
            group.leave()
        }
        // 提醒事项
        group.enter()
        EKEventStore().requestAccess(to: .reminder) { granted, _ in
            results.append("提醒: \(granted ? "✓" : "✗")")
            group.leave()
        }
        group.notify(queue: .main) {
            let summary = results.joined(separator: "\n")
            let resultAlert = UIAlertController(title: "权限申请结果", message: summary, preferredStyle: .alert)
            resultAlert.addAction(UIAlertAction(title: "确定", style: .default))
            self.present(resultAlert, animated: true)
        }
        // 定位（异步，不阻塞group）
        requestLocationPermission()
        // 蓝牙（异步）
        requestBluetoothPermission()
    }
    private func requestMediaPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        PHPhotoLibrary.requestAuthorization { _ in }
        showToast("已申请相机/麦克风/相册权限")
    }
    private func requestLocationPermission() {
        let locationManager = CLLocationManager()
        locationManager.requestWhenInUseAuthorization()
        showToast("已申请定位权限")
    }
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
        showToast("已申请通知权限")
    }
    private func requestSpeechPermission() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        showToast("已申请语音识别权限")
    }
    private func requestBluetoothPermission() {
        // 蓝牙权限通过CBCentralManager初始化时自动触发
        _ = CBCentralManager()
        showToast("已申请蓝牙/本地网络权限")
    }
    private func requestOtherPermissions() {
        ATTrackingManager.requestTrackingAuthorization { _ in }
        CNContactStore().requestAccess(for: .contacts) { _, _ in }
        EKEventStore().requestAccess(to: .event) { _, _ in }
        EKEventStore().requestAccess(to: .reminder) { _, _ in }
        showToast("已申请追踪/通讯录/日历权限")
    }
    // MARK: - UA切换
    private func switchUA() {
        let alert = UIAlertController(title: "选择User-Agent", message: "注意：切换Safari UA可能触发Cloudflare人机验证", preferredStyle: .actionSheet)
        for (i, name) in uaNames.enumerated() {
            let check = i == currentUAIndex ? " ✓" : ""
            alert.addAction(UIAlertAction(title: "\(name)\(check)", style: .default) { _ in
                self.currentUAIndex = i
                UserDefaults.standard.set(i, forKey: self.uaIndexKey)
                let ua = self.uaPresets[i]
                for wv in self.webViews {
                    wv.customUserAgent = ua
                }
                self.currentWebView.reload()
                self.showToast("已切换为：\(name)")
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
            popover.sourceRect = translateButton.bounds
        }
        present(alert, animated: true)
    }
    // MARK: - 底部中央双击→网页内文字搜索
    @objc private func handleBottomCenterDoubleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let bottomThreshold: CGFloat = view.bounds.height * 0.8
        let centerRange: CGFloat = view.bounds.width * 0.2
        let centerX = view.bounds.width / 2
        guard location.y > bottomThreshold,
              abs(location.x - centerX) < centerRange else { return }
        showFindBar()
    }
    // MARK: - 自定义搜索栏（跟随键盘）
    private func showFindBar() {
        if findBarView != nil {
            findTextField?.becomeFirstResponder()
            return
        }
        // 监听键盘
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        // 创建搜索栏
        let bar = UIView()
        bar.backgroundColor = .secondarySystemBackground
        bar.layer.cornerRadius = 12
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOffset = CGSize(width: 0, height: -2)
        bar.layer.shadowRadius = 8
        bar.layer.shadowOpacity = 0.15
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        findBarView = bar
        // 搜索输入框
        let tf = UITextField()
        tf.placeholder = "搜索网页"
        tf.font = .systemFont(ofSize: 16)
        tf.borderStyle = .roundedRect
        tf.backgroundColor = .tertiarySystemBackground
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        tf.returnKeyType = .search
        tf.clearButtonMode = .whileEditing
        tf.delegate = self
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.addTarget(self, action: #selector(findTextChanged(_:)), for: .editingChanged)
        bar.addSubview(tf)
        findTextField = tf
        // 计数标签
        let countLabel = UILabel()
        countLabel.font = .systemFont(ofSize: 12, weight: .medium)
        countLabel.textColor = .secondaryLabel
        countLabel.textAlignment = .center
        countLabel.text = "0/0"
        countLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(countLabel)
        findCountLabel = countLabel
        // 上一个按钮（↑箭头）
        let prevBtn = UIButton(type: .system)
        prevBtn.setImage(UIImage(systemName: "chevron.up"), for: .normal)
        prevBtn.tintColor = .systemBlue
        prevBtn.translatesAutoresizingMaskIntoConstraints = false
        prevBtn.addTarget(self, action: #selector(findPrevTapped), for: .touchUpInside)
        bar.addSubview(prevBtn)
        // 下一个按钮（↓箭头）
        let nextBtn = UIButton(type: .system)
        nextBtn.setImage(UIImage(systemName: "chevron.down"), for: .normal)
        nextBtn.tintColor = .systemBlue
        nextBtn.translatesAutoresizingMaskIntoConstraints = false
        nextBtn.addTarget(self, action: #selector(findNextTapped), for: .touchUpInside)
        bar.addSubview(nextBtn)
        // 完成按钮
        let doneBtn = UIButton(type: .system)
        doneBtn.setTitle("完成", for: .normal)
        doneBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        doneBtn.tintColor = .systemBlue
        doneBtn.translatesAutoresizingMaskIntoConstraints = false
        doneBtn.addTarget(self, action: #selector(findDoneTapped), for: .touchUpInside)
        bar.addSubview(doneBtn)
        // 布局
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            bar.heightAnchor.constraint(equalToConstant: 44),
            tf.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 8),
            tf.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            tf.widthAnchor.constraint(equalToConstant: 140),
            tf.heightAnchor.constraint(equalToConstant: 32),
            countLabel.leadingAnchor.constraint(equalTo: tf.trailingAnchor, constant: 8),
            countLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            countLabel.widthAnchor.constraint(equalToConstant: 45),
            prevBtn.leadingAnchor.constraint(equalTo: countLabel.trailingAnchor, constant: 4),
            prevBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            prevBtn.widthAnchor.constraint(equalToConstant: 32),
            prevBtn.heightAnchor.constraint(equalToConstant: 32),
            nextBtn.leadingAnchor.constraint(equalTo: prevBtn.trailingAnchor, constant: 2),
            nextBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            nextBtn.widthAnchor.constraint(equalToConstant: 32),
            nextBtn.heightAnchor.constraint(equalToConstant: 32),
            doneBtn.leadingAnchor.constraint(equalTo: nextBtn.trailingAnchor, constant: 4),
            doneBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -8),
            doneBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            doneBtn.widthAnchor.constraint(equalToConstant: 50)
        ])
        // 初始位置在底部
        findBottomConstraint = bar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: 100)
        findBottomConstraint?.isActive = true
        view.layoutIfNeeded()
        // 弹出动画
        DispatchQueue.main.async {
            self.findBottomConstraint?.constant = -8
            UIView.animate(withDuration: 0.25) {
                self.view.layoutIfNeeded()
            }
        }
        // 自动聚焦
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            tf.becomeFirstResponder()
        }
    }
    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let keyboardHeight = keyboardFrame.height
        findBottomConstraint?.constant = -keyboardHeight - 8
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    @objc private func keyboardWillHide(_ notification: Notification) {
        findBottomConstraint?.constant = -8
        UIView.animate(withDuration: 0.25) {
            self.view.layoutIfNeeded()
        }
    }
    @objc private func findTextChanged(_ textField: UITextField) {
        guard let keyword = textField.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
        findKeyword = keyword
        if keyword.isEmpty {
            clearFindHighlight()
            findCountLabel?.text = "0/0"
            return
        }
        findInPage(keyword: keyword)
    }
    @objc private func findPrevTapped() {
        findPrev()
    }
    @objc private func findNextTapped() {
        findNext()
    }
    @objc private func findDoneTapped() {
        hideFindBar()
    }
    private func hideFindBar() {
        findTextField?.resignFirstResponder()
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardWillHideNotification, object: nil)
        findBottomConstraint?.constant = 100
        UIView.animate(withDuration: 0.25, animations: {
            self.view.layoutIfNeeded()
        }) { _ in
            self.findBarView?.removeFromSuperview()
            self.findBarView = nil
            self.findTextField = nil
            self.findCountLabel = nil
            self.clearFindHighlight()
        }
    }
    // 禁止点击搜索栏外部关闭（用户没点完成前不可关闭）
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if findBarView != nil {
            // 搜索栏显示时，不关闭
            return
        }
        super.touchesBegan(touches, with: event)
    }
    private func findInPage(keyword: String) {
        currentFindIndex = 0
        let escaped = keyword.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            document.querySelectorAll('.__browser_find_highlight__').forEach(function(el) {
                var parent = el.parentNode;
                while (el.firstChild) parent.insertBefore(el.firstChild, el);
                parent.removeChild(el);
                parent.normalize();
            });
            if (!'\(escaped)' || '\(escaped)'.length === 0) return 0;
            var count = 0;
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, null, false);
            var nodes = [];
            while (walker.nextNode()) {
                if (walker.currentNode.nodeValue && walker.currentNode.nodeValue.toLowerCase().indexOf('\(escaped)'.toLowerCase()) !== -1) {
                    nodes.push(walker.currentNode);
                }
            }
            nodes.forEach(function(node) {
                var text = node.nodeValue;
                var lower = text.toLowerCase();
                var kw = '\(escaped)'.toLowerCase();
                var idx = 0;
                var frag = document.createDocumentFragment();
                while ((idx = lower.indexOf(kw, idx)) !== -1) {
                    frag.appendChild(document.createTextNode(text.substring(0, idx)));
                    var mark = document.createElement('mark');
                    mark.className = '__browser_find_highlight__';
                    mark.setAttribute('data-find-index', count);
                    mark.style.backgroundColor = count === 0 ? '#ff9800' : '#ffeb3b';
                    mark.style.color = '#000';
                    mark.style.borderRadius = '2px';
                    mark.appendChild(document.createTextNode(text.substring(idx, idx + '\(escaped)'.length)));
                    frag.appendChild(mark);
                    text = text.substring(idx + '\(escaped)'.length);
                    lower = text.toLowerCase();
                    idx = 0;
                    count++;
                }
                frag.appendChild(document.createTextNode(text));
                node.parentNode.replaceChild(frag, node);
            });
            var first = document.querySelector('.__browser_find_highlight__');
            if (first) first.scrollIntoView({behavior: 'smooth', block: 'center'});
            return count;
        })();
        """.replacingOccurrences(of: "\(escaped)", with: escaped)
        currentWebView.evaluateJavaScript(js) { [weak self] result, error in
            if let count = result as? Int {
                self?.totalFindCount = count
                self?.currentFindIndex = 0
                DispatchQueue.main.async {
                    self?.findCountLabel?.text = count > 0 ? "1/\(count)" : "0/0"
                }
            }
        }
    }
    private func findNext() {
        guard totalFindCount > 0 else { return }
        currentFindIndex = (currentFindIndex + 1) % totalFindCount
        scrollToFindIndex()
    }
    private func findPrev() {
        guard totalFindCount > 0 else { return }
        currentFindIndex = (currentFindIndex - 1 + totalFindCount) % totalFindCount
        scrollToFindIndex()
    }
    private func scrollToFindIndex() {
        let idx = currentFindIndex
        let js = """
        (function() {
            var all = document.querySelectorAll('.__browser_find_highlight__');
            all.forEach(function(el) { el.style.backgroundColor = '#ffeb3b'; });
            if (all.length > 0 && \(idx) >= 0 && \(idx) < all.length) {
                var target = all[\(idx)];
                target.style.backgroundColor = '#ff9800';
                target.scrollIntoView({behavior: 'smooth', block: 'center'});
            }
            return String(all.length);
        })();
        """
        currentWebView.evaluateJavaScript(js) { [weak self] result, _ in
            DispatchQueue.main.async {
                self?.findCountLabel?.text = "\((self?.currentFindIndex ?? 0)+1)/\(self?.totalFindCount ?? 0)"
            }
        }
    }
    private func clearFindHighlight() {
        let js = """
        document.querySelectorAll('.__browser_find_highlight__').forEach(function(el) {
            var parent = el.parentNode;
            while (el.firstChild) parent.insertBefore(el.firstChild, el);
            parent.removeChild(el);
            parent.normalize();
        });
        """
        currentWebView.evaluateJavaScript(js, completionHandler: nil)
        currentFindIndex = 0
        totalFindCount = 0
    }
    // MARK: - 下载功能
    @objc func downloadButtonTapped() {
        let panel = DownloadPanelViewController()
        panel.modalPresentationStyle = .pageSheet
        if let sheet = panel.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = false
        }
        present(panel, animated: true)
    }
    
    func updateDownloadBadge() {
        let count = DownloadManager.shared.activeCount()
        if count > 0 {
            downloadBadge.text = "\(count)"
            downloadBadge.isHidden = false
            // 呼吸动画
            UIView.animate(withDuration: 0.8, delay: 0, options: [.autoreverse, .repeat], animations: {
                self.downloadBadge.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            }, completion: nil)
        } else {
            downloadBadge.isHidden = true
            downloadBadge.layer.removeAllAnimations()
        }
    }
    
    // MARK: - 下载确认条
    func showDownloadConfirm(url: String, fileName: String) {
        hideDownloadConfirm()
        pendingDownloadURL = url
        pendingDownloadName = fileName
        
        let bar = UIView()
        bar.backgroundColor = .secondarySystemBackground
        bar.layer.cornerRadius = 14
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOffset = CGSize(width: 0, height: -2)
        bar.layer.shadowRadius = 10
        bar.layer.shadowOpacity = 0.18
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        confirmBar = bar
        
        let icon = UIImageView(image: UIImage(systemName: "arrow.down.circle.fill"))
        icon.tintColor = .systemBlue
        icon.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(icon)
        
        let nameLabel = UILabel()
        nameLabel.text = fileName
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(nameLabel)
        
        let pathLabel = UILabel()
        pathLabel.text = "保存到：文件 App → 本应用 → Downloads"
        pathLabel.font = .systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabel
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(pathLabel)
        
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("取消", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        cancelBtn.tintColor = .systemGray
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancelDownloadConfirm), for: .touchUpInside)
        bar.addSubview(cancelBtn)
        
        let downloadBtn = UIButton(type: .system)
        downloadBtn.setTitle("下载", for: .normal)
        downloadBtn.titleLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        downloadBtn.tintColor = .systemBlue
        downloadBtn.translatesAutoresizingMaskIntoConstraints = false
        downloadBtn.addTarget(self, action: #selector(confirmDownload), for: .touchUpInside)
        bar.addSubview(downloadBtn)
        
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 64),
            
            icon.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            icon.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            
            nameLabel.topAnchor.constraint(equalTo: bar.topAnchor, constant: 8),
            nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -8),
            
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            cancelBtn.trailingAnchor.constraint(equalTo: downloadBtn.leadingAnchor, constant: -12),
            cancelBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            cancelBtn.widthAnchor.constraint(equalToConstant: 44),
            
            downloadBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            downloadBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            downloadBtn.widthAnchor.constraint(equalToConstant: 44),
        ])
        
        // 弹出动画
        bar.transform = CGAffineTransform(translationX: 0, y: 80)
        UIView.animate(withDuration: 0.3) {
            bar.transform = .identity
        }
    }
    
    @objc private func cancelDownloadConfirm() {
        hideDownloadConfirm()
    }
    
    @objc private func confirmDownload() {
        guard let url = pendingDownloadURL, let name = pendingDownloadName else { return }
        DownloadManager.shared.startDownload(url: url, fileName: name)
        hideDownloadConfirm()
        showToast("开始下载：\(name)")
    }
    
    func hideDownloadConfirm() {
        guard let bar = confirmBar else { return }
        UIView.animate(withDuration: 0.2, animations: {
            bar.transform = CGAffineTransform(translationX: 0, y: 80)
        }) { _ in
            bar.removeFromSuperview()
        }
        confirmBar = nil
        pendingDownloadURL = nil
        pendingDownloadName = nil
    }
    
    // MARK: - 下载链接判断
    func isDownloadURL(_ url: URL, mimeType: String?) -> Bool {
        let downloadExtensions = ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "zip", "rar", "7z", "mp3", "mp4", "mov", "avi", "mkv", "apk", "exe", "dmg", "pkg", "csv", "txt", "epub", "mobi"]
        let ext = url.pathExtension.lowercased()
        if downloadExtensions.contains(ext) { return true }
        if let mime = mimeType?.lowercased() {
            if mime.contains("application/octet-stream") || mime.contains("application/pdf") || mime.contains("application/zip") || mime.contains("application/x-rar") || mime.contains("video/") || mime.contains("audio/") {
                return true
            }
        }
        return false
    }
    // MARK: - 第三方登录跳转
    private func handleThirdPartyLogin(url: URL, platform: ThirdPartyPlatform) {
        let needConfirm = UserDefaults.standard.object(forKey: loginConfirmKey) as? Bool ?? true
        if !needConfirm {
            performThirdPartyOpen(url: url, platform: platform)
            return
        }
        showLoginConfirmBar(url: url, platform: platform)
    }
    private func showLoginConfirmBar(url: URL, platform: ThirdPartyPlatform) {
        hideLoginConfirmBar()
        pendingLoginURL = url
        pendingLoginPlatform = platform
        let bar = UIView()
        bar.backgroundColor = .secondarySystemBackground
        bar.layer.cornerRadius = 14
        bar.layer.shadowColor = UIColor.black.cgColor
        bar.layer.shadowOffset = CGSize(width: 0, height: -2)
        bar.layer.shadowRadius = 10
        bar.layer.shadowOpacity = 0.18
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)
        loginConfirmBar = bar
        let iconView = UIImageView(image: UIImage(systemName: platform.iconName))
        iconView.tintColor = platform.color
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(iconView)
        let titleLabel = UILabel()
        titleLabel.text = "即将跳转至\(platform.name)"
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(titleLabel)
        let subtitleLabel = UILabel()
        let installed = ThirdPartyLoginManager.shared.isAppInstalled(platform)
        subtitleLabel.text = installed ? "检测到\(platform.name)App，将唤起App授权" : "未检测到App，将使用网页授权"
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(subtitleLabel)
        let cancelBtn = UIButton(type: .system)
        cancelBtn.setTitle("取消", for: .normal)
        cancelBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        cancelBtn.tintColor = .systemGray
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        cancelBtn.addTarget(self, action: #selector(cancelLoginRedirect), for: .touchUpInside)
        bar.addSubview(cancelBtn)
        let continueBtn = UIButton(type: .system)
        continueBtn.setTitle("继续跳转", for: .normal)
        continueBtn.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        continueBtn.tintColor = .systemBlue
        continueBtn.translatesAutoresizingMaskIntoConstraints = false
        continueBtn.addTarget(self, action: #selector(confirmLoginRedirect), for: .touchUpInside)
        bar.addSubview(continueBtn)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            bar.heightAnchor.constraint(equalToConstant: 68),
            iconView.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14),
            iconView.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            titleLabel.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: cancelBtn.leadingAnchor, constant: -8),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            cancelBtn.trailingAnchor.constraint(equalTo: continueBtn.leadingAnchor, constant: -14),
            cancelBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            cancelBtn.widthAnchor.constraint(equalToConstant: 50),
            continueBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14),
            continueBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            continueBtn.widthAnchor.constraint(equalToConstant: 70),
        ])
        bar.transform = CGAffineTransform(translationX: 0, y: 100)
        UIView.animate(withDuration: 0.3) { bar.transform = .identity }
    }
    @objc private func cancelLoginRedirect() {
        hideLoginConfirmBar()
        showToast("已取消跳转")
    }
    @objc private func confirmLoginRedirect() {
        guard let url = pendingLoginURL, let platform = pendingLoginPlatform else { return }
        hideLoginConfirmBar()
        performThirdPartyOpen(url: url, platform: platform)
    }
    private func performThirdPartyOpen(url: URL, platform: ThirdPartyPlatform) {
        isLoginRedirecting = true
        showToast("正在跳转至\(platform.name)...")
        ThirdPartyLoginManager.shared.openApp(url: url) { [weak self] success in
            DispatchQueue.main.async {
                self?.isLoginRedirecting = false
                if success {
                    self?.showToast("已唤起\(platform.name)")
                } else {
                    if let appStoreURL = platform.appStoreURL,
                       let storeURL = URL(string: appStoreURL) {
                        let alert = UIAlertController(
                            title: "未检测到\(platform.name)App",
                            message: "是否前往App Store下载？或使用网页版授权",
                            preferredStyle: .alert
                        )
                        alert.addAction(UIAlertAction(title: "网页授权", style: .default) { _ in
                            self?.currentWebView.load(URLRequest(url: url))
                        })
                        alert.addAction(UIAlertAction(title: "下载App", style: .default) { _ in
                            UIApplication.shared.open(storeURL)
                        })
                        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                        self?.present(alert, animated: true)
                    } else {
                        self?.currentWebView.load(URLRequest(url: url))
                    }
                }
            }
        }
    }
    private func hideLoginConfirmBar() {
        guard let bar = loginConfirmBar else { return }
        UIView.animate(withDuration: 0.2, animations: {
            bar.transform = CGAffineTransform(translationX: 0, y: 100)
        }) { _ in bar.removeFromSuperview() }
        loginConfirmBar = nil
        pendingLoginURL = nil
        pendingLoginPlatform = nil
    }

    @objc private func handleEdgeMenuPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let menuWidth = view.bounds.width * 0.75
        let edgeThreshold: CGFloat = 44
        let horizontalThreshold: CGFloat = 30
        let triggerThreshold: CGFloat = 20
        let openThreshold: CGFloat = 60
        let fastVelocity: CGFloat = 500
        
        switch gesture.state {
        case .began:
            // 检查起始点是否在右边缘
            if view.bounds.width - location.x <= edgeThreshold {
                edgeMenuStartX = edgeMenuLeadingConstraint.constant
                edgeMenuPanStart = location
            } else {
                gesture.isEnabled = false
                gesture.isEnabled = true
            }
        case .changed:
            // 检查是否满足触发条件
            let dx = edgeMenuPanStart.x - location.x // 向左为正
            let dy = location.y - edgeMenuPanStart.y // 向下为正
            
            if !edgeMenuIsOpen && dx >= horizontalThreshold && dy >= triggerThreshold {
                // 跟手阶段：菜单从右侧滑入
                let progress = min(dy / 200, 1.0)
                edgeMenuLeadingConstraint.constant = -menuWidth * progress
            } else if edgeMenuIsOpen {
                // 菜单已打开，左滑收起
                let progress = min(max(-translation.x / menuWidth, 0), 1)
                edgeMenuLeadingConstraint.constant = -menuWidth + menuWidth * progress
            }
        case .ended:
            let dy = location.y - edgeMenuPanStart.y
            let dx = edgeMenuPanStart.x - location.x
            
            if !edgeMenuIsOpen {
                // 快速下滑或下滑距离足够→展开
                if velocity.y > fastVelocity || (dx >= horizontalThreshold && dy >= openThreshold) {
                    setEdgeMenu(open: true)
                } else {
                    setEdgeMenu(open: false)
                }
            } else {
                // 快速左滑或左滑距离足够→收起
                if velocity.x < -fastVelocity || translation.x > openThreshold {
                    setEdgeMenu(open: false)
                } else {
                    setEdgeMenu(open: true)
                }
            }
        default:
            break
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
            translateButton.backgroundColor = UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0)
            translateButton.setTitle("译", for: .normal)
            translateButton.layer.shadowColor = UIColor(red: 0.4, green: 0.7, blue: 1.0, alpha: 1.0).cgColor
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
        let mime = response.mimeType ?? ""
        // 显示底部下载确认条
        DispatchQueue.main.async {
            self.showDownloadConfirm(url: downloadURL.absoluteString, fileName: fileName)
        }
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
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        // 拦截第三方登录/唤起URL
        let (isThirdParty, platform) = ThirdPartyLoginManager.shared.isThirdPartyURL(url)
        if isThirdParty, let platform = platform {
            decisionHandler(.cancel)
            handleThirdPartyLogin(url: url, platform: platform)
            return
        }
        // 拦截tel:、sms:、mailto:等系统URL
        let scheme = url.scheme?.lowercased() ?? ""
        if ["tel", "sms", "mailto"].contains(scheme) {
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
            return
        }
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
        let location = pan.location(in: view)
        let velocity = pan.velocity(in: view)
        // 右边缘下滑手势：起始点在右边缘44pt内，且垂直下滑
        let isRightEdge = view.bounds.width - location.x <= 44
        if isRightEdge && velocity.y > 100 {
            return true
        }
        // 普通水平滑动手势（前进/后退）
        return abs(velocity.x) > abs(velocity.y) * 1.2
    }
}
