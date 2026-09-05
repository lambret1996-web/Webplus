import UIKit
import WebKit
import NetworkExtension
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
    private var tabBarTopConstraint: NSLayoutConstraint!
    private var tabBarBottomConstraint: NSLayoutConstraint!
    private var webViewTopConstraint: NSLayoutConstraint!
    private var webViewBottomConstraint: NSLayoutConstraint!
    private var edgeMenuIsOpen = false
    private var edgeMenuStartX: CGFloat = 0
    private var edgeMenuPanStart: CGPoint = .zero
    private var edgeMenuDidTrigger = false
    // 菜单功能项排序
    private var edgeMenuFunctions: [(icon: String, title: String, action: Selector)] = []
    private var edgeMenuSortMode = false
    private var draggingIndex: Int?
    private var draggingStartY: CGFloat = 0
    private let edgeMenuOrderKey = "edgeMenuOrder"
    // UA预设
    private let uaPresetsExtended = [
        ("iPhone Safari", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"),
        ("iPad Safari", "Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"),
        ("Chrome iOS", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.6099.119 Mobile/15E148 Safari/604.1"),
        ("Firefox iOS", "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) FxiOS/121.0 Mobile/15E148 Safari/605.1.15"),
        ("桌面版 Safari (Mac)", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"),
        ("Chrome (Windows)", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"),
        ("Edge (Windows)", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0"),
        ("自定义 UA", "")
    ]
    private let customUAKey = "customUserAgent"
    // 历史记录存储
    private let historyKey = "browserHistory"
    private var browserHistory: [[String: String]] {
        get { UserDefaults.standard.array(forKey: historyKey) as? [[String: String]] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: historyKey) }
    }
    // 圈X导入的广告域名（与手动添加的分开管理）
    private let importedAdDomainsKey = "importedAdDomains"
    private var importedAdDomains: [String] {
        get { UserDefaults.standard.array(forKey: importedAdDomainsKey) as? [String] ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: importedAdDomainsKey) }
    }
    // App-Proxy 代理控制
    private let proxyExcludeKey = "proxyExcludeDomains"
    private var proxyExcludeDomains: String {
        get { UserDefaults.standard.string(forKey: proxyExcludeKey) ?? "github.com,cloudflare.com" }
        set { UserDefaults.standard.set(newValue, forKey: proxyExcludeKey) }
    }
    private var proxyStatsTimer: Timer? 
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
        applyToolbarPosition() // 应用工具栏位置（顶部/底部）
        setupWebViews()
        setupProgressView()
        setupGestures()
        setupEdgeMenu()
        // 定制网页长按菜单（汉化复制/粘贴等）
        UIMenuController.shared.menuItems = [
            UIMenuItem(title: "复制", action: #selector(customCopy(_:))),
            UIMenuItem(title: "粘贴", action: #selector(customPaste(_:))),
            UIMenuItem(title: "剪切", action: #selector(customCut(_:))),
            UIMenuItem(title: "全选", action: #selector(customSelectAllText(_:)))
        ]
        switchToTab(index: 0)
        loadInitialPages()
        // 预创建下载文件夹，确保在Files App中可见
        createDownloadsFolder()
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
        tabBarTopConstraint = tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        tabBarBottomConstraint = tabBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        NSLayoutConstraint.activate([
            tabBarTopConstraint,
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
            let engine = UserDefaults.standard.string(forKey: "searchEngine") ?? "Google"
            let searchURLString: String
            switch engine {
            case "百度":
                searchURLString = "https://www.baidu.com/s?wd=\(encoded)"
            case "Bing":
                searchURLString = "https://www.bing.com/search?q=\(encoded)"
            case "DuckDuckGo":
                searchURLString = "https://duckduckgo.com/?q=\(encoded)"
            default:
                searchURLString = "https://www.google.com/search?q=\(encoded)"
            }
            if let searchURL = URL(string: searchURLString) {
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
        let allDomains = adDomains + customAdDomains + importedAdDomains
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
        webViewTopConstraint = webViewContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
        webViewBottomConstraint = webViewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            webViewTopConstraint,
            webViewContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webViewContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webViewBottomConstraint
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
        // 菜单宽度：40%
        let menuWidth = view.bounds.width * 0.50
        // 遮罩层：点击菜单外任意区域收回菜单
        edgeMenuOverlay = UIButton(type: .system)
        edgeMenuOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.10)
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
        
        // 菜单面板
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
        
        // 右上角三横线按钮：切换排序模式
        let sortButton = UIButton(type: .system)
        sortButton.setImage(UIImage(systemName: "line.horizontal.3"), for: .normal)
        sortButton.tag = 999
        sortButton.addTarget(self, action: #selector(toggleEdgeMenuSortMode), for: .touchUpInside)
        sortButton.translatesAutoresizingMaskIntoConstraints = false
        edgeMenuView.addSubview(sortButton)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: edgeMenuView.safeAreaLayoutGuide.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: edgeMenuView.leadingAnchor, constant: 20),
            sortButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            sortButton.trailingAnchor.constraint(equalTo: edgeMenuView.trailingAnchor, constant: -20),
            sortButton.widthAnchor.constraint(equalToConstant: 30),
            sortButton.heightAnchor.constraint(equalToConstant: 30)
        ])
        
        // 初始化功能列表（从UserDefaults读取排序）
        let defaultFunctions: [(String, String, Selector)] = [
            ("bookmark", "增加书签", #selector(edgeMenuAddBookmark)),
            ("book", "书签列表", #selector(edgeMenuShowBookmarks)),
            ("clock", "历史记录", #selector(edgeMenuShowHistory)),
            ("square.and.arrow.down", "下载管理", #selector(edgeMenuShowDownloads)),
            ("photo", "全局图片拦截", #selector(edgeMenuToggleImageBlock)),
            ("globe", "UA 切换", #selector(edgeMenuSwitchUA)),
            ("hand.raised", "广告黑名单", #selector(edgeMenuManageAdBlock)),
            ("internaldrive", "缓存管理", #selector(edgeMenuShowCacheManager)),
            ("network", "高级代理(AppProxy)", #selector(edgeMenuShowProxy)),
            ("gear", "设置", #selector(edgeMenuShowSettings))
        ]
        // 读取保存的排序
        if let savedOrder = UserDefaults.standard.array(forKey: edgeMenuOrderKey) as? [Int] {
            var ordered: [(String, String, Selector)] = []
            for idx in savedOrder where idx < defaultFunctions.count {
                ordered.append(defaultFunctions[idx])
            }
            if ordered.count == defaultFunctions.count {
                edgeMenuFunctions = ordered
            } else {
                edgeMenuFunctions = defaultFunctions
            }
        } else {
            edgeMenuFunctions = defaultFunctions
        }
        
        // 渲染功能按钮
        renderEdgeMenuButtons(after: titleLabel)
    }
    
    private func renderEdgeMenuButtons(after titleLabel: UILabel) {
        // 移除旧按钮
        for subview in edgeMenuView.subviews {
            if subview.tag >= 100 && subview.tag < 200 {
                subview.removeFromSuperview()
            }
        }
        var previousView: UIView = titleLabel
        for (idx, item) in edgeMenuFunctions.enumerated() {
            let button = createMenuButton(icon: item.icon, title: item.title, action: item.action)
            button.tag = 100 + idx
            edgeMenuView.addSubview(button)
            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: previousView.bottomAnchor, constant: previousView == titleLabel ? 20 : 0),
                button.leadingAnchor.constraint(equalTo: edgeMenuView.leadingAnchor),
                button.trailingAnchor.constraint(equalTo: edgeMenuView.trailingAnchor),
                button.heightAnchor.constraint(equalToConstant: 48)
            ])
            // 排序模式下添加三横线拖拽手柄
            if edgeMenuSortMode {
                let handle = UIImageView(image: UIImage(systemName: "line.horizontal.3"))
                handle.tintColor = .systemGray2
                handle.tag = 400 + idx
                handle.isUserInteractionEnabled = true
                handle.translatesAutoresizingMaskIntoConstraints = false
                button.addSubview(handle)
                NSLayoutConstraint.activate([
                    handle.centerYAnchor.constraint(equalTo: button.centerYAnchor),
                    handle.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -15),
                    handle.widthAnchor.constraint(equalToConstant: 20),
                    handle.heightAnchor.constraint(equalToConstant: 20)
                ])
                // 长按手柄开始拖拽
                let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleMenuDrag(_:)))
                longPress.minimumPressDuration = 0.2
                handle.addGestureRecognizer(longPress)
            }
            previousView = button
        }
    }
    
    @objc private func handleMenuDrag(_ gesture: UILongPressGestureRecognizer) {
        guard let handle = gesture.view, let button = handle.superview else { return }
        let idx = button.tag - 100
        let location = gesture.location(in: edgeMenuView)
        
        switch gesture.state {
        case .began:
            draggingIndex = idx
            draggingStartY = location.y
            button.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.15)
        case .changed:
            guard let dragIdx = draggingIndex else { return }
            let itemHeight: CGFloat = 48
            let startY = edgeMenuView.safeAreaLayoutGuide.layoutFrame.minY + 60
            let relativeY = location.y - startY
            var targetIdx = Int(relativeY / itemHeight)
            targetIdx = max(0, min(edgeMenuFunctions.count - 1, targetIdx))
            
            if targetIdx != dragIdx {
                edgeMenuFunctions.swapAt(dragIdx, targetIdx)
                draggingIndex = targetIdx
                if let titleLabel = edgeMenuView.subviews.first(where: { ($0 as? UILabel)?.text == "功能菜单" }) as? UILabel {
                    renderEdgeMenuButtons(after: titleLabel)
                }
            }
        case .ended, .cancelled:
            draggingIndex = nil
            button.backgroundColor = .clear
            saveMenuOrder()
        default:
            break
        }
    }
    
    private func saveMenuOrder() {
        let defaultTitles = ["增加书签", "书签列表", "历史记录", "下载管理", "全局图片拦截", "UA 切换", "广告黑名单", "缓存管理", "高级代理", "设置"]
        var order: [Int] = []
        for item in edgeMenuFunctions {
            if let idx = defaultTitles.firstIndex(of: item.title) {
                order.append(idx)
            }
        }
        UserDefaults.standard.set(order, forKey: edgeMenuOrderKey)
    }

    @objc private func toggleEdgeMenuSortMode() {
        edgeMenuSortMode.toggle()
        if let sortBtn = edgeMenuView.viewWithTag(999) as? UIButton {
            sortBtn.tintColor = edgeMenuSortMode ? .systemBlue : .label
        }
        if let titleLabel = edgeMenuView.subviews.first(where: { ($0 as? UILabel)?.text == "功能菜单" }) as? UILabel {
            renderEdgeMenuButtons(after: titleLabel)
        }
        if !edgeMenuSortMode {
            // 保存排序
            let defaultTitles = ["增加书签", "书签列表", "历史记录", "下载管理", "全局图片拦截", "UA 切换", "广告黑名单", "缓存管理", "高级代理", "设置"]
            var order: [Int] = []
            for item in edgeMenuFunctions {
                if let idx = defaultTitles.firstIndex(of: item.title) {
                    order.append(idx)
                }
            }
            UserDefaults.standard.set(order, forKey: edgeMenuOrderKey)
            showToast("菜单排序已保存")
        } else {
            showToast("排序模式：点击上下箭头调整")
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
        showBookmarkManager()
    }
    
    private func showBookmarkManager() {
        let bookmarks = UserDefaults.standard.array(forKey: "savedBookmarks") as? [[String: String]] ?? []
        let alert = UIAlertController(title: "书签管理（\(bookmarks.count)条）", message: "点击书签跳转，长按可编辑/删除", preferredStyle: .actionSheet)
        for (idx, bm) in bookmarks.enumerated() {
            let title = bm["title"] ?? bm["url"] ?? ""
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                // 点击跳转
                if let url = URL(string: bm["url"] ?? "") {
                    self.currentWebView.load(URLRequest(url: url))
                }
            })
            // 编辑按钮
            alert.addAction(UIAlertAction(title: "✏️ 编辑：\(title)", style: .default) { _ in
                self.editBookmark(at: idx)
            })
            // 删除按钮
            alert.addAction(UIAlertAction(title: "🗑 删除：\(title)", style: .destructive) { _ in
                self.deleteBookmark(at: idx)
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func editBookmark(at index: Int) {
        var bookmarks = UserDefaults.standard.array(forKey: "savedBookmarks") as? [[String: String]] ?? []
        guard index < bookmarks.count else { return }
        let bm = bookmarks[index]
        let alert = UIAlertController(title: "编辑书签", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = bm["title"]
            tf.placeholder = "书签名称"
        }
        alert.addTextField { tf in
            tf.text = bm["url"]
            tf.placeholder = "网址"
            tf.keyboardType = .URL
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            let newTitle = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces) ?? ""
            let newURL = alert.textFields?[1].text?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !newTitle.isEmpty, !newURL.isEmpty else {
                self.showToast("名称和网址不能为空")
                return
            }
            bookmarks[index] = ["title": newTitle, "url": newURL]
            UserDefaults.standard.set(bookmarks, forKey: "savedBookmarks")
            self.showToast("书签已更新")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func deleteBookmark(at index: Int) {
        var bookmarks = UserDefaults.standard.array(forKey: "savedBookmarks") as? [[String: String]] ?? []
        guard index < bookmarks.count else { return }
        let title = bookmarks[index]["title"] ?? ""
        let alert = UIAlertController(title: "确认删除", message: "确定删除书签「\(title)」？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            bookmarks.remove(at: index)
            UserDefaults.standard.set(bookmarks, forKey: "savedBookmarks")
            self.showToast("书签已删除")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func edgeMenuShowHistory() {
        closeEdgeMenu()
        showBrowserHistory()
    }
    
    private func showBrowserHistory() {
        let history = browserHistory
        let alert = UIAlertController(title: "历史记录（\(history.count)条）", message: "点击跳转，底部可清除", preferredStyle: .actionSheet)
        if history.isEmpty {
            alert.message = "暂无历史记录"
        } else {
            // 按时间倒序显示最近30条
            for item in history.prefix(30) {
                let title = item["title"] ?? item["url"] ?? ""
                let url = item["url"] ?? ""
                // 显示标题，副标题显示域名
                let displayTitle = title.count > 40 ? String(title.prefix(40)) + "..." : title
                alert.addAction(UIAlertAction(title: displayTitle, style: .default) { _ in
                    if let targetURL = URL(string: url) {
                        self.currentWebView.load(URLRequest(url: targetURL))
                    }
                })
            }
            // 清除历史记录
            alert.addAction(UIAlertAction(title: "🗑 清除全部历史记录", style: .destructive) { _ in
                self.clearBrowserHistory()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func clearBrowserHistory() {
        let alert = UIAlertController(title: "确认清除", message: "确定清除全部历史记录？此操作不可恢复", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            UserDefaults.standard.removeObject(forKey: self.historyKey)
            self.showToast("历史记录已清除")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func edgeMenuShowDownloads() {
        closeEdgeMenu()
        let panel = DownloadPanelViewController()
        panel.modalPresentationStyle = .pageSheet
        if #available(iOS 15.0, *) {
            if let sheet = panel.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = false
            }
        }
        present(panel, animated: true)
    }
    
    @objc private func edgeMenuToggleImageBlock() {
        closeEdgeMenu()
        toggleGlobalImageBlock()
    }
    
    @objc private func edgeMenuSwitchUA() {
        closeEdgeMenu()
        showUASelector()
    }
    
    private func showUASelector() {
        let alert = UIAlertController(title: "选择 User-Agent", message: "点击切换，立即生效", preferredStyle: .actionSheet)
        for (name, ua) in uaPresetsExtended {
            let isCurrent = (currentWebView.customUserAgent == ua) || (name == "自定义 UA" && UserDefaults.standard.string(forKey: customUAKey) != nil)
            let title = isCurrent ? "✓ \(name)" : name
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                if name == "自定义 UA" {
                    self.showCustomUAInput()
                } else {
                    self.applyUA(ua, name: name)
                }
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showCustomUAInput() {
        let alert = UIAlertController(title: "自定义 UA", message: "输入自定义 User-Agent 字符串", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = UserDefaults.standard.string(forKey: self.customUAKey)
            tf.placeholder = "Mozilla/5.0 ..."
            tf.autocapitalizationType = .none
            tf.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "应用", style: .default) { _ in
            if let ua = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces), !ua.isEmpty {
                UserDefaults.standard.set(ua, forKey: self.customUAKey)
                self.applyUA(ua, name: "自定义 UA")
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func applyUA(_ ua: String, name: String) {
        for wv in self.webViews {
            wv.customUserAgent = ua
        }
        self.showToast("UA已切换：\(name)")
        self.currentWebView.reload()
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
    
    @objc private func edgeMenuShowProxy() {
        closeEdgeMenu()
        showProxySettings()
    }
    
    private func showProxySettings() {
        let alert = UIAlertController(title: "高级代理 (App-Proxy)", message: "内置本地代理，HTTP请求重定向+广告域名拦截+请求头修改", preferredStyle: .actionSheet)
        
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            let isRunning = managers?.contains(where: { $0.localizedDescription == "LightBrowserProxy" && $0.connection.status == .connected }) ?? false
            let defaults = UserDefaults(suiteName: "group.ab6938971b3fa793.1")
            let total = defaults?.integer(forKey: "totalRequests") ?? 0
            let blocked = defaults?.integer(forKey: "blocked") ?? 0
            let redirected = defaults?.integer(forKey: "redirected") ?? 0
            alert.message = "状态: \(isRunning ? "运行中" : "未启动")\n请求: \(total) 拦截: \(blocked) 重定向: \(redirected)"
        }
        
        alert.addAction(UIAlertAction(title: "开启代理(直连模式)", style: .default) { _ in
            self.startBrowserProxy(useVLESS: false)
        })
        alert.addAction(UIAlertAction(title: "开启代理(VLESS模式)", style: .default) { _ in
            self.startBrowserProxy(useVLESS: true)
        })
        alert.addAction(UIAlertAction(title: "关闭代理", style: .default) { _ in
            self.stopBrowserProxy()
        })
        alert.addAction(UIAlertAction(title: "VLESS节点管理", style: .default) { _ in
            self.showVLESSNodeManager()
        })
        alert.addAction(UIAlertAction(title: "设置排除域名", style: .default) { _ in
            self.showProxyExcludeSettings()
        })
        alert.addAction(UIAlertAction(title: "删除VPN配置", style: .destructive) { _ in
            self.removeProxyConfig()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func showProxyExcludeSettings() {
        let alert = UIAlertController(title: "排除域名", message: "这些域名不走代理，逗号分隔", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = self.proxyExcludeDomains
            tf.placeholder = "github.com,cloudflare.com"
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "保存", style: .default) { _ in
            if let text = alert.textFields?.first?.text {
                self.proxyExcludeDomains = text
                self.showToast("排除域名已保存")
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func startBrowserProxy(useVLESS: Bool) {
        if useVLESS && VLESSNodeManager.shared.currentNode == nil {
            showToast("请先添加VLESS节点")
            showVLESSNodeManager()
            return
        }
        showToast("正在启动代理...")
        // 先删除所有旧的LightBrowserProxy配置，避免"需要更新"问题
        NETunnelProviderManager.loadAllFromPreferences { [weak self] oldManagers, _ in
            let group = DispatchGroup()
            for oldManager in oldManagers ?? [] {
                if oldManager.localizedDescription == "LightBrowserProxy" {
                    group.enter()
                    oldManager.removeFromPreferences { _ in
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                // 旧配置删除完成后，延迟0.5秒再创建新配置，确保系统完全清理
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self?.createAndStartProxy(useVLESS: useVLESS)
                }
            }
        }
    }
    
    private func createAndStartProxy(useVLESS: Bool) {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, error in
            if let error = error {
                self?.showToast("启动失败: \(error.localizedDescription)")
                return
            }
            let manager = NETunnelProviderManager()
            manager.localizedDescription = "LightBrowserProxy"
            let proto = NETunnelProviderProtocol()
            proto.providerBundleIdentifier = "app.silver9175.tomato8924.AppProxyExtension"
            // 修复: 使用节点地址代替127.0.0.1，避免"需要更新"提示
            if useVLESS, let node = VLESSNodeManager.shared.currentNode {
                proto.serverAddress = "\(node.host):\(node.port)"
            } else {
                proto.serverAddress = "proxy.local"
            }
            var providerConfig: [String: Any] = [
                "excludeDomains": self?.proxyExcludeDomains ?? "",
                "rules": "browser-proxy",
                "useVLESS": useVLESS
            ]
            if useVLESS, let node = VLESSNodeManager.shared.currentNode {
                providerConfig["vlessConfig"] = [
                    "uuid": node.uuid,
                    "host": node.host,
                    "port": node.port,
                    "wsPath": node.wsPath,
                    "wsHost": node.wsHost ?? "",
                    "tls": node.tls,
                    "name": node.name
                ]
            }
            proto.providerConfiguration = providerConfig
            manager.protocolConfiguration = proto
            manager.isEnabled = true
            manager.saveToPreferences { error in
                if let error = error {
                    self?.showToast("保存失败: \(error.localizedDescription)")
                    return
                }
                manager.loadFromPreferences { _ in
                    do {
                        try manager.connection.startVPNTunnel()
                        self?.showToast(useVLESS ? "VLESS代理已启动" : "代理已启动")
                    } catch {
                        self?.showToast("启动失败: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func stopBrowserProxy() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            if let manager = managers?.first(where: { $0.localizedDescription == "LightBrowserProxy" }) {
                manager.connection.stopVPNTunnel()
                self?.showToast("代理已停止")
            }
        }
    }
    
    private func removeProxyConfig() {
        NETunnelProviderManager.loadAllFromPreferences { [weak self] managers, _ in
            for manager in managers ?? [] {
                if manager.localizedDescription == "LightBrowserProxy" {
                    manager.removeFromPreferences { _ in
                        self?.showToast("VPN配置已删除")
                    }
                }
            }
        }
    }
    
    private func showVLESSNodeManager() {
        let nodes = VLESSNodeManager.shared.nodes
        let alert = UIAlertController(title: "VLESS节点管理", message: "当前节点: \(VLESSNodeManager.shared.currentNode?.name ?? "未选择")", preferredStyle: .actionSheet)
        
        for (i, node) in nodes.enumerated() {
            let isCurrent = VLESSNodeManager.shared.currentNode?.uuid == node.uuid
            alert.addAction(UIAlertAction(title: "\(isCurrent ? "✓ " : "")\(node.name) - \(node.host):\(node.port)", style: .default) { _ in
                VLESSNodeManager.shared.currentNode = node
                self.showToast("已切换到: \(node.name)")
            })
        }
        
        alert.addAction(UIAlertAction(title: "➕ 添加节点(粘贴vless://链接)", style: .default) { _ in
            self.showAddVLESSNode()
        })
        
        alert.addAction(UIAlertAction(title: "📊 测试节点延迟", style: .default) { _ in
            self.testAllNodes()
        })

        alert.addAction(UIAlertAction(title: "📡 订阅管理", style: .default) { _ in
            self.showSubscriptionManager()
        })
        
        alert.addAction(UIAlertAction(title: "🔄 更新所有订阅", style: .default) { _ in
            self.updateAllSubscriptions()
        })
        
        alert.addAction(UIAlertAction(title: "🗑 删除节点", style: .destructive) { _ in
            self.showDeleteVLESSNode()
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func showAddVLESSNode() {
        let alert = UIAlertController(title: "添加VLESS节点", message: "粘贴vless://格式的订阅链接", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "vless://uuid@host:port?path=/&security=tls&type=ws#节点名"
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "添加", style: .default) { _ in
            if let text = alert.textFields?.first?.text, !text.isEmpty {
                if let node = VLESSNodeManager.shared.parseVLESSURL(text) {
                    VLESSNodeManager.shared.addNode(node)
                    if VLESSNodeManager.shared.currentNode == nil {
                        VLESSNodeManager.shared.currentNode = node
                    }
                    self.showToast("节点添加成功: \(node.name)")
                } else {
                    self.showToast("链接格式错误")
                }
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func testAllNodes() {
        let nodes = VLESSNodeManager.shared.nodes
        guard !nodes.isEmpty else {
            showToast("暂无节点，请先添加")
            return
        }
        
        let alert = UIAlertController(title: "测试节点延迟", message: "正在测试 0/\(nodes.count) 个节点...", preferredStyle: .alert)
        present(alert, animated: true)
        
        NodeTester.shared.testAllNodes(nodes, timeout: 5, progress: { current, total in
            DispatchQueue.main.async {
                alert.message = "正在测试 \(current)/\(total) 个节点..."
            }
        }) { results in
            DispatchQueue.main.async {
                alert.dismiss(animated: true) {
                    self.showNodeTestResults(results)
                }
            }
        }
    }
    
    private func showNodeTestResults(_ results: [NodeTestResult]) {
        let alert = UIAlertController(title: "节点测试结果", message: nil, preferredStyle: .actionSheet)
        
        // 按延迟排序，成功的在前
        let sorted = results.sorted { r1, r2 in
            if r1.success && r2.success {
                return (r1.latency ?? Int.max) < (r2.latency ?? Int.max)
            }
            return r1.success && !r2.success
        }
        
        var message = "共 \(results.count) 个节点\n"
        message += "可用: \(results.filter { $0.success }.count) | 失败: \(results.filter { !$0.success }.count)\n\n"
        
        for (i, result) in sorted.enumerated() {
            let status = result.success ? "✓" : "✗"
            let latency = NodeTester.formatLatency(result.latency)
            message += "\(i+1). \(status) \(result.node.name)\n   \(result.node.host):\(result.node.port) - \(latency)\n"
        }
        
        alert.message = message
        
        // 快速切换到最快节点
        if let fastest = sorted.first(where: { $0.success }) {
            alert.addAction(UIAlertAction(title: "⚡ 切换到最快节点: \(fastest.node.name)", style: .default) { _ in
                VLESSNodeManager.shared.currentNode = fastest.node
                self.showToast("已切换到: \(fastest.node.name)")
            })
        }
        
        alert.addAction(UIAlertAction(title: "重新测试", style: .default) { _ in
            self.testAllNodes()
        })
        
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func showDeleteVLESSNode() {
        let nodes = VLESSNodeManager.shared.nodes
        guard !nodes.isEmpty else {
            showToast("没有可删除的节点")
            return
        }
        let alert = UIAlertController(title: "删除节点", message: nil, preferredStyle: .actionSheet)
        for (i, node) in nodes.enumerated() {
            alert.addAction(UIAlertAction(title: node.name, style: .destructive) { _ in
                VLESSNodeManager.shared.removeNode(at: i)
                if VLESSNodeManager.shared.currentNode?.uuid == node.uuid {
                    VLESSNodeManager.shared.currentNode = nil
                }
                self.showToast("已删除: \(node.name)")
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func showSubscriptionManager() {
        let subs = SubscriptionManager.shared.subscriptions
        let alert = UIAlertController(title: "订阅管理", message: "当前\(subs.count)个订阅", preferredStyle: .actionSheet)
        
        for (i, sub) in subs.enumerated() {
            alert.addAction(UIAlertAction(title: "\(sub.name) - \(sub.url.prefix(30))...", style: .default) { _ in
                self.showSubscriptionOptions(index: i)
            })
        }
        
        alert.addAction(UIAlertAction(title: "➕ 添加订阅", style: .default) { _ in
            self.showAddSubscription()
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func showSubscriptionOptions(index: Int) {
        let sub = SubscriptionManager.shared.subscriptions[index]
        let alert = UIAlertController(title: sub.name, message: sub.url, preferredStyle: .actionSheet)
        
        alert.addAction(UIAlertAction(title: "立即更新", style: .default) { _ in
            self.updateSubscription(at: index)
        })
        
        alert.addAction(UIAlertAction(title: "删除订阅", style: .destructive) { _ in
            SubscriptionManager.shared.removeSubscription(at: index)
            self.showToast("订阅已删除")
        })
        
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func showAddSubscription() {
        let alert = UIAlertController(title: "添加订阅", message: "输入订阅链接（支持小火箭/Shadowrocket格式）", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https://example.com/sub?token=xxx"
            tf.autocapitalizationType = .none
        }
        alert.addTextField { tf in
            tf.placeholder = "订阅名称（可选）"
        }
        alert.addAction(UIAlertAction(title: "添加并更新", style: .default) { _ in
            if let url = alert.textFields?.first?.text, !url.isEmpty {
                let name = alert.textFields?.last?.text ?? "订阅\(SubscriptionManager.shared.subscriptions.count + 1)"
                SubscriptionManager.shared.addSubscription(url: url, name: name)
                self.showToast("订阅已添加，正在更新...")
                self.updateSubscription(at: SubscriptionManager.shared.subscriptions.count - 1)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func updateSubscription(at index: Int) {
        let sub = SubscriptionManager.shared.subscriptions[index]
        showToast("正在更新订阅...")
        SubscriptionManager.shared.fetchNodes(from: sub.url) { nodes, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.showToast("更新失败: \(error.localizedDescription)")
                    return
                }
                var newCount = 0
                for node in nodes {
                    if !VLESSNodeManager.shared.nodes.contains(where: { $0.uuid == node.uuid && $0.host == node.host }) {
                        VLESSNodeManager.shared.addNode(node)
                        newCount += 1
                    }
                }
                self.showToast("更新完成，新增\(newCount)个节点")
            }
        }
    }
    
    private func updateAllSubscriptions() {
        showToast("正在更新所有订阅...")
        SubscriptionManager.shared.updateAllSubscriptions { newCount in
            DispatchQueue.main.async {
                self.showToast("全部更新完成，新增\(newCount)个节点")
            }
        }
    }
    
    @objc private func edgeMenuShowSettings() {
        closeEdgeMenu()
        showAppSettings()
    }
    
    @objc private func edgeMenuShowCacheManager() {
        closeEdgeMenu()
        showCacheManagerWithStorage()
    }
    
    // MARK: - 独立设置页面
    private func showAppSettings() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let currentEngine = UserDefaults.standard.string(forKey: "searchEngine") ?? "Google"
        let addressPos = UserDefaults.standard.string(forKey: "addressBarPosition") ?? "顶部"
        
        let alert = UIAlertController(title: "⚙️ 浏览器设置", message: "版本 v\(version)", preferredStyle: .actionSheet)
        
        // 版本号
        alert.addAction(UIAlertAction(title: "ℹ️ 当前版本：v\(version)", style: .default) { _ in
            self.showToast("当前版本：v\(version)")
        })
        
        // 搜索引擎
        alert.addAction(UIAlertAction(title: "🔍 搜索引擎（当前：\(currentEngine)）", style: .default) { _ in
            self.showSearchEngineSelector()
        })
        
        // 地址栏位置
        alert.addAction(UIAlertAction(title: "📍 地址栏位置（当前：\(addressPos)）", style: .default) { _ in
            self.showAddressBarPositionSelector()
        })
        
        // 默认浏览器
        alert.addAction(UIAlertAction(title: "🌐 设置为默认浏览器", style: .default) { _ in
            self.setAsDefaultBrowser()
        })
        
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func setEdgeMenu(open: Bool, duration: TimeInterval = 1.0) {
        edgeMenuIsOpen = open
        let menuWidth = view.bounds.width * 0.50
        edgeMenuLeadingConstraint.constant = open ? -menuWidth : 0
        if open {
            edgeMenuOverlay.isHidden = false
        }
        UIView.animate(withDuration: duration, delay: 0,
                       usingSpringWithDamping: open ? 0.5 : 1.0,
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
        // 地址栏双击→复制当前URL
        let urlDoubleTap = UITapGestureRecognizer(target: self, action: #selector(handleUrlDoubleTap(_:)))
        urlDoubleTap.numberOfTapsRequired = 2
        urlTextField.addGestureRecognizer(urlDoubleTap)
    }
    
    @objc private func handleUrlDoubleTap(_ gesture: UITapGestureRecognizer) {
        if let url = currentWebView.url?.absoluteString, !url.isEmpty {
            UIPasteboard.general.string = url
            showToast("链接已复制")
        }
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
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
            popover.sourceRect = translateButton.bounds
        }
        present(alert, animated: true)
    }
    // MARK: - 搜索引擎切换
    private func showSearchEngineSelector() {
        let alert = UIAlertController(title: "选择搜索引擎", message: nil, preferredStyle: .actionSheet)
        let engines = ["Google", "百度", "Bing", "DuckDuckGo"]
        let current = UserDefaults.standard.string(forKey: "searchEngine") ?? "Google"
        for engine in engines {
            let title = engine == current ? "✓ \(engine)" : engine
            alert.addAction(UIAlertAction(title: title, style: .default) { _ in
                UserDefaults.standard.set(engine, forKey: "searchEngine")
                self.showToast("搜索引擎已切换为：\(engine)")
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    // MARK: - 地址栏位置切换
    private func showAddressBarPositionSelector() {
        let alert = UIAlertController(title: "地址栏位置", message: "重启后生效", preferredStyle: .actionSheet)
        let current = UserDefaults.standard.string(forKey: "addressBarPosition") ?? "顶部"
        alert.addAction(UIAlertAction(title: current == "顶部" ? "✓ 顶部" : "顶部", style: .default) { _ in
            UserDefaults.standard.set("顶部", forKey: "addressBarPosition")
            self.showToast("地址栏位置：顶部（重启生效）")
        })
        alert.addAction(UIAlertAction(title: current == "底部" ? "✓ 底部" : "底部", style: .default) { _ in
            UserDefaults.standard.set("底部", forKey: "addressBarPosition")
            self.showToast("地址栏位置：底部（重启生效）")
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    // MARK: - 设置默认浏览器
    // MARK: - 设置默认浏览器
    private func setAsDefaultBrowser() {
        let alert = UIAlertController(
            title: "默认浏览器说明",
            message: "⚠️ 当前为 TrollStore 免签名版本，受 iOS 系统限制，无法设置为默认浏览器。\n\n如需使用默认浏览器功能，需要使用正规 Apple 开发者证书打包安装。\n\n本应用已在 Info.plist 中注册了 HTTP/HTTPS 链接处理能力，正规签名后即可在系统设置中出现「默认浏览器」选项。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "我知道了", style: .default))
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
    
    // MARK: - 缓存管理（含存储状态）
    private func showCacheManagerWithStorage() {
        // 获取手机存储状态
        let fileManager = FileManager.default
        var totalSpace: Int64 = 0
        var freeSpace: Int64 = 0
        if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            totalSpace = attrs[.systemSize] as? Int64 ?? 0
            freeSpace = attrs[.systemFreeSize] as? Int64 ?? 0
        }
        let usedSpace = totalSpace - freeSpace
        let totalGB = Double(totalSpace) / 1024 / 1024 / 1024
        let usedGB = Double(usedSpace) / 1024 / 1024 / 1024
        let freeGB = Double(freeSpace) / 1024 / 1024 / 1024
        
        // 获取浏览器缓存大小
        let sizes = fourLevelCache.cacheSize()
        let cacheTotal = sizes.temp + sizes.static
        let cacheMB = Double(cacheTotal) / 1024 / 1024
        let tempMB = Double(sizes.temp) / 1024 / 1024
        let staticMB = Double(sizes.static) / 1024 / 1024
        
        let message = String(format: """
        📱 手机存储状态
        总容量：%.1f GB
        已使用：%.1f GB
        剩余：%.1f GB
        
        📦 浏览器缓存
        缓存总计：%.1f MB
        动态页面：%.1f MB
        静态资源：%.1f MB
        """, totalGB, usedGB, freeGB, cacheMB, tempMB, staticMB)
        
        let alert = UIAlertController(title: "💾 缓存管理", message: message, preferredStyle: .actionSheet)
        
        // 清空当前站点缓存
        if let host = currentWebView.url?.host {
            alert.addAction(UIAlertAction(title: "📍 清空当前站点缓存（\(host)）", style: .default) { _ in
                self.fourLevelCache.clearCacheForSite(host)
                self.currentWebView.reload()
                self.showToast("已清空 \(host) 缓存")
            })
        }
        
        // 一键清空全部缓存
        alert.addAction(UIAlertAction(title: "🗑 一键清空浏览器全部缓存", style: .destructive) { _ in
            self.fourLevelCache.removeAllCachedResponses()
            self.showToast("已清空全部缓存")
        })
        
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
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
        // 圈X规则导入
        alert.addAction(UIAlertAction(title: "📥 导入圈X/AdGuard规则", style: .default) { _ in
            self.showQuantumultXImport()
        })
        // 管理导入的规则
        if !self.importedAdDomains.isEmpty {
            alert.addAction(UIAlertAction(title: "📋 已导入规则（\(self.importedAdDomains.count)条）", style: .default) { _ in
                self.showImportedDomainsManager()
            })
        }
        // 导出当前黑名单
        alert.addAction(UIAlertAction(title: "📤 导出为圈X格式", style: .default) { _ in
            self.exportAdRules()
        })
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
    // MARK: - 圈X/AdGuard规则导入
    private func showQuantumultXImport() {
        let alert = UIAlertController(title: "导入广告规则", message: "支持圈X、Shadowrocket、AdGuard域名黑名单格式", preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "🔗 从订阅链接导入", style: .default) { _ in
            self.showSubscriptionImport()
        })
        alert.addAction(UIAlertAction(title: "📝 粘贴规则文本", style: .default) { _ in
            self.showTextImport()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
        }
        present(alert, animated: true)
    }
    
    private func showSubscriptionImport() {
        let alert = UIAlertController(title: "订阅链接导入", message: "输入圈X/AdGuard规则订阅URL", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "https://example.com/blocklist.txt"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "开始导入", style: .default) { _ in
            guard let urlStr = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  let url = URL(string: urlStr) else {
                self.showToast("无效链接")
                return
            }
            self.showToast("正在下载规则...")
            URLSession.shared.dataTask(with: url) { data, _, error in
                DispatchQueue.main.async {
                    if let data = data, let text = String(data: data, encoding: .utf8) {
                        self.importRulesFromText(text)
                    } else {
                        self.showToast("下载失败：\(error?.localizedDescription ?? "未知")")
                    }
                }
            }.resume()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    private func showTextImport() {
        let alert = UIAlertController(title: "粘贴规则文本", message: "支持host、DOMAIN、DOMAIN-SET等格式，每行一条", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "doubleclick.net\ngooglesyndication.com\n..."
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "导入", style: .default) { _ in
            if let text = alert.textFields?.first?.text {
                self.importRulesFromText(text)
            }
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    /// 圈X规则解析器：提取域名，自动过滤不支持的指令
    private func importRulesFromText(_ text: String) {
        var extractedDomains: Set<String> = []
        let lines = text.components(separatedBy: .newlines)
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // 跳过注释和空行
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("!") || trimmed.hasPrefix("//") || trimmed.hasPrefix(";") {
                continue
            }
            // 跳过浏览器不支持的指令
            let unsupportedKeywords = ["rewrite", "script", "http-request", "http-response", 
                                        "mitm", "hostname", "server", "proxy", "filter", 
                                        "url 302", "url reject", "response-body", "request-body"]
            let lowerLine = trimmed.lowercased()
            if unsupportedKeywords.contains(where: { lowerLine.contains($0) }) {
                continue
            }
            
            var domain: String?
            
            // 格式1: host = example.com
            if lowerLine.hasPrefix("host") {
                if let eqRange = trimmed.range(of: "=") {
                    domain = String(trimmed[eqRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                }
            }
            // 格式2: DOMAIN,example.com
            else if lowerLine.hasPrefix("domain,") || lowerLine.hasPrefix("domain-suffix,") || lowerLine.hasPrefix("domain-keyword,") {
                let parts = trimmed.components(separatedBy: ",")
                if parts.count >= 2 {
                    domain = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            // 格式3: DOMAIN-SET,https://... (跳过，需要单独下载)
            else if lowerLine.hasPrefix("domain-set") {
                continue
            }
            // 格式4: 纯域名（包含点号，不含空格和特殊字符）
            else if trimmed.contains(".") && !trimmed.contains(" ") && !trimmed.contains("://") {
                // 过滤掉IP地址和路径
                if trimmed.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) == nil {
                    domain = trimmed
                }
            }
            // 格式5: 0.0.0.0 example.com (hosts文件格式)
            else if trimmed.hasPrefix("0.0.0.0") || trimmed.hasPrefix("127.0.0.1") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 2 {
                    domain = parts[1]
                }
            }
            
            // 清理域名
            if var d = domain {
                d = d.lowercased()
                d = d.replacingOccurrences(of: "https://", with: "")
                d = d.replacingOccurrences(of: "http://", with: "")
                if d.hasPrefix("www.") { d = String(d.dropFirst(4)) }
                // 去掉路径
                if let slashRange = d.range(of: "/") {
                    d = String(d[..<slashRange.lowerBound])
                }
                // 去掉端口
                if let colonRange = d.range(of: ":") {
                    d = String(d[..<colonRange.lowerBound])
                }
                d = d.trimmingCharacters(in: CharacterSet(charactersIn: "."))
                // 验证是有效域名
                if d.contains(".") && d.count > 3 {
                    // 转义点号为正则格式
                    let escaped = d.replacingOccurrences(of: ".", with: "\\.")
                    extractedDomains.insert(escaped)
                }
            }
        }
        
        // 合并到已导入列表（去重）
        var current = importedAdDomains
        let beforeCount = current.count
        for d in extractedDomains {
            if !current.contains(d) {
                current.append(d)
            }
        }
        importedAdDomains = current
        let addedCount = current.count - beforeCount
        
        // 重新编译规则
        compileAdBlockRules()
        showToast("导入完成：新增\(addedCount)条，共\(current.count)条导入规则")
    }
    
    private func showImportedDomainsManager() {
        let alert = UIAlertController(title: "已导入规则（\(importedAdDomains.count)条）", message: "点击删除单条，或清空全部导入规则", preferredStyle: .actionSheet)
        for (i, domain) in importedAdDomains.enumerated() {
            let readable = domain.replacingOccurrences(of: "\\.", with: ".")
            alert.addAction(UIAlertAction(title: "🗑 \(readable)", style: .destructive) { _ in
                var list = self.importedAdDomains
                list.remove(at: i)
                self.importedAdDomains = list
                self.compileAdBlockRules()
                self.showToast("已删除")
            })
        }
        alert.addAction(UIAlertAction(title: "🗑 清空全部导入规则", style: .destructive) { _ in
            self.importedAdDomains.removeAll()
            self.compileAdBlockRules()
            self.showToast("已清空导入规则")
        })
        alert.addAction(UIAlertAction(title: "完成", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = translateButton
        }
        present(alert, animated: true)
    }
    
    private func exportAdRules() {
        var exportText = "# 轻浏览广告黑名单导出\n"
        exportText += "# 手动添加（\(customAdDomains.count)条）：\n"
        for d in customAdDomains {
            exportText += d.replacingOccurrences(of: "\\.", with: ".") + "\n"
        }
        exportText += "# 导入规则（\(importedAdDomains.count)条）：\n"
        for d in importedAdDomains {
            exportText += d.replacingOccurrences(of: "\\.", with: ".") + "\n"
        }
        // 复制到剪贴板
        UIPasteboard.general.string = exportText
        showToast("已复制到剪贴板（共\(customAdDomains.count + importedAdDomains.count)条）")
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
        if #available(iOS 15.0, *) {
            if let sheet = panel.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = false
            }
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
    @objc private func handleEdgeMenuPan(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: view)
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let menuWidth = view.bounds.width * 0.50
        // 右边缘检测区域
        let edgeThreshold: CGFloat = 60
        // 触发阈值：水平偏移15pt + 垂直下滑10pt 同时满足
        let horizontalThreshold: CGFloat = 15
        let triggerThreshold: CGFloat = 10
        // 左滑收起阈值
        let closeThreshold: CGFloat = 45
        // 快速滑动速度阈值
        let fastVelocity: CGFloat = 400

        switch gesture.state {
        case .began:
            // 检查起始点是否在右边缘
            if view.bounds.width - location.x <= edgeThreshold {
                edgeMenuStartX = edgeMenuLeadingConstraint.constant
                edgeMenuPanStart = location
                edgeMenuDidTrigger = false
            } else {
                gesture.isEnabled = false
                gesture.isEnabled = true
            }
        case .changed:
            let dx = edgeMenuPanStart.x - location.x // 向左为正
            let dy = location.y - edgeMenuPanStart.y // 向下为正
            let speed = sqrt(velocity.x * velocity.x + velocity.y * velocity.y)

            if edgeMenuIsOpen {
                // 菜单已打开：左滑超过阈值立即收起
                if translation.x > closeThreshold || velocity.x > fastVelocity {
                    edgeMenuDidTrigger = true
                    setEdgeMenu(open: false)
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                }
            } else {
                // 快速轻扫（速度≥400pt/s）：短距离直接呼出
                let fastSwipe = speed >= fastVelocity && dy > 5
                // 慢速滑动：需要达到位移阈值
                let slowTrigger = dx >= horizontalThreshold && dy >= triggerThreshold
                
                if !edgeMenuDidTrigger && (fastSwipe || slowTrigger) {
                    edgeMenuDidTrigger = true
                    // 弹出速度跟随手指速度：越快动画越短
                    let animDuration = max(0.1, 0.3 - speed / 3000)
                    setEdgeMenu(open: true, duration: animDuration)
                    // 结束当前手势，由动画接管弹出
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                }
            }
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.view === currentWebView else { return }
        let translation = gesture.translation(in: view)
        let screenWidth = view.bounds.width
        let threshold = screenWidth * 0.5 // 拖拽50%触发前进/后退
        
        switch gesture.state {
        case .began:
            gestureStartPoint = gesture.location(in: view)
        case .changed:
            // 跟手：页面跟随手指水平平移
            let dx = translation.x
            if abs(dx) > abs(translation.y) * 1.2 {
                let limitedDx = max(-screenWidth * 0.5, min(screenWidth * 0.5, dx))
                currentWebView.transform = CGAffineTransform(translationX: limitedDx, y: 0)
            }
        case .ended:
            let dx = translation.x
            // 回弹动画
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.5, options: .curveEaseOut) {
                self.currentWebView.transform = .identity
            }
            // 右滑（手指从左往右）→ 网页后退
            if dx > threshold {
                if currentWebView.canGoBack {
                    currentWebView.goBack()
                }
            }
            // 左滑（手指从右往左）→ 网页前进
            else if dx < -threshold {
                if currentWebView.canGoForward {
                    currentWebView.goForward()
                }
            }
        case .cancelled:
            UIView.animate(withDuration: 0.25) {
                self.currentWebView.transform = .identity
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
        if #available(iOS 15.0, *) {
            // iOS 15+：使用WKWebView原生下载，保留完整请求上下文（Cookie、认证、重定向）
            decisionHandler(.download)
        } else {
            // iOS 14及以下：先取消导航，显示确认面板，用户确认后用URLSession下载
            decisionHandler(.cancel)
            DispatchQueue.main.async {
                self.showDownloadConfirm(url: downloadURL.absoluteString, fileName: fileName)
            }
        }
    }

    // iOS 15+：导航响应变为下载时调用，必须设置 delegate 才能开始下载
    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
        print("[Download] 导航响应已转换为下载任务")
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
        // 记录历史记录（跨标签页、持久化、去重）
        if let url = webView.url, !url.absoluteString.hasPrefix("about:") {
            let title = webView.title ?? url.absoluteString
            addToHistory(url: url.absoluteString, title: title)
        }
    }
    
    private func addToHistory(url: String, title: String) {
        var history = browserHistory
        // 去重：移除相同URL的旧记录
        history.removeAll { $0["url"] == url }
        // 插入到最前面（最新）
        let entry = ["url": url, "title": title, "time": String(Date().timeIntervalSince1970)]
        history.insert(entry, at: 0)
        // 最多保留200条
        if history.count > 200 {
            history = Array(history.prefix(200))
        }
        browserHistory = history
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

    // MARK: - 菜单汉化
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // 过滤系统菜单，保留常用操作
        let systemActions: Set<Selector> = [
            #selector(cut(_:)),
            #selector(copy(_:)),
            #selector(paste(_:)),
            #selector(select(_:)),
            #selector(selectAll(_:))
        ]
        if systemActions.contains(action) {
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }
    
    override func cut(_ sender: Any?) {
        UIPasteboard.general.string = urlTextField.text
        urlTextField.text = ""
        showToast("已剪切")
    }
    
    override func copy(_ sender: Any?) {
        if let text = urlTextField.text, !text.isEmpty {
            UIPasteboard.general.string = text
            showToast("已复制")
        } else if let url = currentWebView.url?.absoluteString {
            UIPasteboard.general.string = url
            showToast("链接已复制")
        }
    }
    
    override func paste(_ sender: Any?) {
        if let text = UIPasteboard.general.string {
            urlTextField.text = text
            showToast("已粘贴")
        }
    }
    
    override func select(_ sender: Any?) {
        urlTextField.selectedTextRange = urlTextField.textRange(from: urlTextField.beginningOfDocument, to: urlTextField.endOfDocument)
    }
    
    override func selectAll(_ sender: Any?) {
        urlTextField.selectedTextRange = urlTextField.textRange(from: urlTextField.beginningOfDocument, to: urlTextField.endOfDocument)
    }

    deinit {
        for webView in webViews {
            webView.removeObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress))
        }
    }
    // MARK: - 图片长按菜单
    @objc private func handleImageLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let webView = gesture.view as? WKWebView else { return }
        let point = gesture.location(in: webView)
        let js = """
        (function() {
            var el = document.elementFromPoint(\(point.x), \(point.y));
            while (el && el.tagName !== 'IMG') { el = el.parentElement; }
            return el ? el.src : '';
        })();
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self = self, let url = result as? String, !url.isEmpty else { return }
            self.showImageMenu(url: url, in: webView)
        }
    }
    
    private func showImageMenu(url: String, in webView: WKWebView) {
        let alert = UIAlertController(title: nil, message: url, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "访问图片", style: .default) { _ in
            if let index = self.webViews.firstIndex(of: webView) {
                self.switchToTab(index: index)
                webView.load(URLRequest(url: URL(string: url)!))
            }
        })
        alert.addAction(UIAlertAction(title: "保存照片", style: .default) { _ in
            self.saveImageToAlbum(url: url)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 0, height: 0)
        }
        present(alert, animated: true)
    }
    
    private func saveImageToAlbum(url: String) {
        guard let imageURL = URL(string: url) else { return }
        showToast("正在保存图片...")
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.imageSaved(_:didFinishSavingWithError:contextInfo:)), nil)
            } else {
                DispatchQueue.main.async {
                    self.showToast("图片保存失败")
                }
            }
        }.resume()
    }

    // MARK: - 工具栏位置切换
    private func applyToolbarPosition() {
        let position = UserDefaults.standard.string(forKey: "addressBarPosition") ?? "顶部"
        if position == "底部" {
            tabBarTopConstraint.isActive = false
            tabBarBottomConstraint.isActive = true
            webViewTopConstraint.isActive = false
            webViewBottomConstraint.isActive = false
            webViewTopConstraint = webViewContainer.topAnchor.constraint(equalTo: view.topAnchor)
            webViewBottomConstraint = webViewContainer.bottomAnchor.constraint(equalTo: tabBar.topAnchor)
            webViewTopConstraint.isActive = true
            webViewBottomConstraint.isActive = true
        } else {
            tabBarBottomConstraint.isActive = false
            tabBarTopConstraint.isActive = true
            webViewTopConstraint.isActive = false
            webViewBottomConstraint.isActive = false
            webViewTopConstraint = webViewContainer.topAnchor.constraint(equalTo: tabBar.bottomAnchor)
            webViewBottomConstraint = webViewContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            webViewTopConstraint.isActive = true
            webViewBottomConstraint.isActive = true
        }
    }

    // MARK: - 自定义菜单（汉化）
    @objc private func customCopy(_ sender: Any) {
        currentWebView.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            if let text = result as? String {
                UIPasteboard.general.string = text
            }
        }
    }
    @objc private func customPaste(_ sender: Any) {
        currentWebView.evaluateJavaScript("document.execCommand('paste')") { _, _ in }
    }
    @objc private func customCut(_ sender: Any) {
        currentWebView.evaluateJavaScript("document.execCommand('cut')") { _, _ in }
    }
    @objc private func customSelectAllText(_ sender: Any) {
        currentWebView.evaluateJavaScript("document.execCommand('selectAll')") { _, _ in }
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
    // MARK: - 下载文件夹管理
    private func createDownloadsFolder() {
        let fileManager = FileManager.default
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let downloadsDir = docsDir.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: downloadsDir.path) {
            do {
                try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            } catch {
                print("创建Downloads文件夹失败: \(error)")
            }
        }
    }
    
    @objc private func openDownloadsFolder() {
        let fileManager = FileManager.default
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let downloadsDir = docsDir.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: downloadsDir.path) {
            try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        }
        let url = URL(string: "shareddocuments://\(downloadsDir.path)")!
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    self.showToast("文件App → 我的iPhone → 轻浏览 → Downloads")
                }
            }
        } else {
            showToast("文件App → 我的iPhone → 轻浏览 → Downloads")
        }
    }

    
    @objc private func imageSaved(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        DispatchQueue.main.async {
            if error == nil {
                self.showToast("图片已保存到相册")
            } else {
                self.showToast("保存失败，请检查相册权限")
            }
        }
    }
}

// MARK: - WKDownloadDelegate (iOS 15+)
@available(iOS 15.0, *)
extension ViewController: WKDownloadDelegate {
    
    @objc func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let fileManager = FileManager.default
        let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsDir = docsDir.appendingPathComponent("Downloads", isDirectory: true)
        // 确保目录存在
        try? fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
        // 处理文件名，避免非法字符
        var fileName = suggestedFilename
        fileName = fileName.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "_")
        if fileName.isEmpty { fileName = "download_\(Int(Date().timeIntervalSince1970))" }
        var destURL = downloadsDir.appendingPathComponent(fileName)
        // 避免重名，自动重命名
        var counter = 1
        while fileManager.fileExists(atPath: destURL.path) {
            let ext = (fileName as NSString).pathExtension
            let base = (fileName as NSString).deletingPathExtension
            if ext.isEmpty {
                fileName = "\(base)_\(counter)"
            } else {
                fileName = "\(base)_\(counter).\(ext)"
            }
            destURL = downloadsDir.appendingPathComponent(fileName)
            counter += 1
        }
        print("[Download] 目标路径: \(destURL.path)")
        // 保存目标路径，供下载完成后使用
        DownloadManager.shared.setDestinationURL(destURL, for: download)
        completionHandler(destURL)
    }
    
    @objc func downloadDidFinish(_ download: WKDownload) {
        print("[Download] 下载完成")
        DownloadManager.shared.completeWKDownload(download: download)
        DispatchQueue.main.async {
            self.showToast("下载完成，已保存到 Downloads 文件夹")
        }
    }
    
    @objc func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        print("[Download] 下载失败: \(error.localizedDescription)")
        DownloadManager.shared.failWKDownload(download: download, error: error)
        DispatchQueue.main.async {
            self.showToast("下载失败：\(error.localizedDescription)")
        }
    }

}
