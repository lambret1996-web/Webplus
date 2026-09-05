//
//  CacheManagerViewController.swift
//  轻量浏览器 - 全屏四级缓存管理（卡片式）
//
//  功能：
//  - 右滑屏幕30%返回浏览器
//  - 卡片形式展示四级缓存
//  - 删除后实时刷新缓存总量
//  - 删除时显示进度条动画
//  - 长按深度清理按钮 → 全部删除全部缓存
//

import UIKit

// 用于给离线条目按钮关联 OfflineItem 对象
private var offlineItemKey: UInt8 = 0

class CacheManagerViewController: UIViewController, UIGestureRecognizerDelegate {

    // MARK: - UI 元素
    private let scrollView = UIScrollView()
    private let contentView = UIView()

    // 标题
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()

    // 设备存储卡片
    private let storageCard = UIView()
    private let storageTitleLabel = UILabel()
    private let storageProgressView = UIProgressView(progressViewStyle: .default)
    private let storageDetailLabel = UILabel()

    // 缓存总览卡片
    private let overviewCard = UIView()
    private let overviewTitleLabel = UILabel()
    private let overviewTotalLabel = UILabel()
    private let overviewCleanableLabel = UILabel()
    private let overviewValidLabel = UILabel()

    // 四级缓存卡片数组
    private var cacheCards: [UIView] = []
    private var cacheNameLabels: [UILabel] = []
    private var cacheSizeLabels: [UILabel] = []
    private var cacheDescLabels: [UILabel] = []
    private var cacheCleanButtons: [UIButton] = []
    private var cacheProgressViews: [UIProgressView] = []

    // 底部按钮
    private let quickCleanButton = UIButton(type: .system)
    private let deepCleanButton = UIButton(type: .system)

    // 删除进度遮罩
    private let progressOverlay = UIView()
    private let progressIndicator = UIActivityIndicatorView(style: .large)
    private let progressLabel = UILabel()
    private let progressBar = UIProgressView(progressViewStyle: .default)

    // MARK: - 缓存数据
    private let cacheNames = ["一级·实时临时缓存", "二级·本次会话缓存", "三级·持久资源缓存", "四级·离线留存缓存"]
    private let cacheDescs = [
        "当前页面正在使用的临时数据，关闭页面即失效",
        "本次启动期间的页面缓存，退出App后自动清理",
        "图片/JS/CSS等静态资源，24小时后自动过期",
        "用户主动保存的离线页面，永久保留不自动清理"
    ]
    private let cacheColors: [UIColor] = [
        UIColor(red: 0.20, green: 0.60, blue: 0.93, alpha: 1.0),
        UIColor(red: 0.35, green: 0.75, blue: 0.45, alpha: 1.0),
        UIColor(red: 0.95, green: 0.65, blue: 0.15, alpha: 1.0),
        UIColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1.0)
    ]

    private var cacheSizes: [Int64] = [0, 0, 0, 0]
    private var isCleaning = false
    private var offlineListStack: UIStackView!

    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0)

        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self

        setupUI()
        setupBackButton()
        refreshCacheData()
    }

    private func setupBackButton() {
        let backButton = UIButton(type: .system)
        backButton.setImage(UIImage(systemName: "chevron.left"), for: .normal)
        backButton.setTitle(" 返回", for: .normal)
        backButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
        backButton.tintColor = .systemBlue
        backButton.backgroundColor = UIColor.white.withAlphaComponent(0.9)
        backButton.layer.cornerRadius = 16
        backButton.layer.shadowColor = UIColor.black.cgColor
        backButton.layer.shadowOpacity = 0.1
        backButton.layer.shadowOffset = CGSize(width: 0, height: 2)
        backButton.layer.shadowRadius = 4
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    @objc private func backTapped() {
        navigationController?.popViewController(animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // 重新激活导航侧滑返回手势（解决自定义返回按钮导致手势失效）
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        navigationController?.interactivePopGestureRecognizer?.delegate = self
        // 每次进入页面刷新设备存储状态（实时更新）
        refreshCacheData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // 离开页面时解绑代理，防止影响浏览器主页手势
        navigationController?.interactivePopGestureRecognizer?.delegate = nil
    }
    
    // 导航栈深度大于1才允许侧滑返回
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        return nav.viewControllers.count > 1
    }

    // MARK: - 设置UI
    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        // 标题
        titleLabel.text = "缓存资源管理中心"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 22)
        titleLabel.textColor = .darkText
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        subtitleLabel.text = "右滑屏幕30%返回浏览器"
        subtitleLabel.font = UIFont.systemFont(ofSize: 13)
        subtitleLabel.textColor = .gray
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)

        // 设备存储卡片
        setupCard(storageCard)
        storageTitleLabel.text = "📱 设备存储状态"
        storageTitleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        storageTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        storageCard.addSubview(storageTitleLabel)

        storageProgressView.progressTintColor = UIColor(red: 0.20, green: 0.60, blue: 0.93, alpha: 1.0)
        storageProgressView.trackTintColor = UIColor(white: 0.9, alpha: 1.0)
        storageProgressView.layer.cornerRadius = 4
        storageProgressView.clipsToBounds = true
        storageProgressView.translatesAutoresizingMaskIntoConstraints = false
        storageCard.addSubview(storageProgressView)

        storageDetailLabel.font = UIFont.systemFont(ofSize: 13)
        storageDetailLabel.textColor = .gray
        storageDetailLabel.numberOfLines = 0
        storageDetailLabel.translatesAutoresizingMaskIntoConstraints = false
        storageCard.addSubview(storageDetailLabel)

        contentView.addSubview(storageCard)

        // 缓存总览卡片
        setupCard(overviewCard)
        overviewTitleLabel.text = "📦 浏览器缓存总览"
        overviewTitleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        overviewTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        overviewCard.addSubview(overviewTitleLabel)

        overviewTotalLabel.font = UIFont.boldSystemFont(ofSize: 28)
        overviewTotalLabel.textColor = UIColor(red: 0.20, green: 0.60, blue: 0.93, alpha: 1.0)
        overviewTotalLabel.translatesAutoresizingMaskIntoConstraints = false
        overviewCard.addSubview(overviewTotalLabel)

        overviewCleanableLabel.font = UIFont.systemFont(ofSize: 13)
        overviewCleanableLabel.textColor = UIColor(red: 0.90, green: 0.45, blue: 0.25, alpha: 1.0)
        overviewCleanableLabel.translatesAutoresizingMaskIntoConstraints = false
        overviewCard.addSubview(overviewCleanableLabel)

        overviewValidLabel.font = UIFont.systemFont(ofSize: 13)
        overviewValidLabel.textColor = UIColor(red: 0.35, green: 0.75, blue: 0.45, alpha: 1.0)
        overviewValidLabel.translatesAutoresizingMaskIntoConstraints = false
        overviewCard.addSubview(overviewValidLabel)

        contentView.addSubview(overviewCard)

        // 四级缓存卡片
        for i in 0..<4 {
            let card = UIView()
            setupCard(card)
            contentView.addSubview(card)
            cacheCards.append(card)

            let colorBar = UIView()
            colorBar.backgroundColor = cacheColors[i]
            colorBar.layer.cornerRadius = 2
            colorBar.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(colorBar)

            let nameLabel = UILabel()
            nameLabel.text = cacheNames[i]
            nameLabel.font = UIFont.boldSystemFont(ofSize: 15)
            nameLabel.textColor = .darkText
            nameLabel.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(nameLabel)
            cacheNameLabels.append(nameLabel)

            let sizeLabel = UILabel()
            sizeLabel.font = UIFont.boldSystemFont(ofSize: 20)
            sizeLabel.textColor = cacheColors[i]
            sizeLabel.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(sizeLabel)
            cacheSizeLabels.append(sizeLabel)

            let descLabel = UILabel()
            descLabel.text = cacheDescs[i]
            descLabel.font = UIFont.systemFont(ofSize: 12)
            descLabel.textColor = .gray
            descLabel.numberOfLines = 0
            descLabel.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(descLabel)
            cacheDescLabels.append(descLabel)

            let progressView = UIProgressView(progressViewStyle: .default)
            progressView.progressTintColor = cacheColors[i]
            progressView.trackTintColor = UIColor(white: 0.9, alpha: 1.0)
            progressView.isHidden = true
            progressView.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(progressView)
            cacheProgressViews.append(progressView)

            let cleanButton = UIButton(type: .system)
            cleanButton.setTitle(i == 3 ? "🔒 已保护" : "🗑 清理", for: .normal)
            cleanButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
            cleanButton.backgroundColor = i == 3 ? UIColor(white: 0.9, alpha: 1.0) : cacheColors[i]
            cleanButton.setTitleColor(i == 3 ? .gray : .white, for: .normal)
            cleanButton.layer.cornerRadius = 8
            cleanButton.tag = i
            cleanButton.isEnabled = i != 3
            cleanButton.addTarget(self, action: #selector(cleanSingleCache(_:)), for: .touchUpInside)
            cleanButton.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(cleanButton)
            cacheCleanButtons.append(cleanButton)

            // 四级卡片：离线网页列表容器
            if i == 3 {
                let stack = UIStackView()
                stack.axis = .vertical
                stack.spacing = 6
                stack.translatesAutoresizingMaskIntoConstraints = false
                card.addSubview(stack)
                offlineListStack = stack
            }

            NSLayoutConstraint.activate([
                colorBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                colorBar.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
                colorBar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
                colorBar.widthAnchor.constraint(equalToConstant: 4),
                nameLabel.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 10),
                nameLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
                sizeLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                sizeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
                descLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
                descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
                descLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                progressView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
                progressView.trailingAnchor.constraint(equalTo: cleanButton.leadingAnchor, constant: -10),
                progressView.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
                progressView.heightAnchor.constraint(equalToConstant: 6),
                cleanButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                cleanButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),
                cleanButton.widthAnchor.constraint(equalToConstant: 70),
                cleanButton.heightAnchor.constraint(equalToConstant: 30)
            ])

            // 离线列表约束（仅四级卡片）
            if i == 3, let stack = offlineListStack {
                NSLayoutConstraint.activate([
                    stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                    stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                    stack.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 8),
                    stack.bottomAnchor.constraint(lessThanOrEqualTo: cleanButton.topAnchor, constant: -8)
                ])
            }
        }

        // 底部按钮
        quickCleanButton.setTitle("🗑 一键清理垃圾", for: .normal)
        quickCleanButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        quickCleanButton.backgroundColor = UIColor(red: 0.20, green: 0.60, blue: 0.93, alpha: 1.0)
        quickCleanButton.setTitleColor(.white, for: .normal)
        quickCleanButton.layer.cornerRadius = 12
        quickCleanButton.addTarget(self, action: #selector(quickClean), for: .touchUpInside)
        quickCleanButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(quickCleanButton)

        deepCleanButton.setTitle("🧹 深度清理（长按全部删除）", for: .normal)
        deepCleanButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 15)
        deepCleanButton.backgroundColor = UIColor(red: 0.90, green: 0.45, blue: 0.25, alpha: 1.0)
        deepCleanButton.setTitleColor(.white, for: .normal)
        deepCleanButton.layer.cornerRadius = 12
        deepCleanButton.addTarget(self, action: #selector(deepClean), for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(deepCleanLongPress(_:)))
        longPress.minimumPressDuration = 1.0
        deepCleanButton.addGestureRecognizer(longPress)
        deepCleanButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(deepCleanButton)

        // 删除进度遮罩
        progressOverlay.backgroundColor = UIColor(white: 0, alpha: 0.6)
        progressOverlay.isHidden = true
        progressOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progressOverlay)

        let progressBox = UIView()
        progressBox.backgroundColor = .white
        progressBox.layer.cornerRadius = 16
        progressBox.translatesAutoresizingMaskIntoConstraints = false
        progressOverlay.addSubview(progressBox)

        progressIndicator.color = .gray
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        progressBox.addSubview(progressIndicator)

        progressLabel.text = "正在清理缓存..."
        progressLabel.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        progressLabel.textAlignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        progressBox.addSubview(progressLabel)

        progressBar.progressTintColor = UIColor(red: 0.20, green: 0.60, blue: 0.93, alpha: 1.0)
        progressBar.trackTintColor = UIColor(white: 0.9, alpha: 1.0)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        progressBox.addSubview(progressBar)

        NSLayoutConstraint.activate([
            progressOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            progressOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progressOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            progressBox.centerXAnchor.constraint(equalTo: progressOverlay.centerXAnchor),
            progressBox.centerYAnchor.constraint(equalTo: progressOverlay.centerYAnchor),
            progressBox.widthAnchor.constraint(equalToConstant: 240),
            progressBox.heightAnchor.constraint(equalToConstant: 140),
            progressIndicator.topAnchor.constraint(equalTo: progressBox.topAnchor, constant: 24),
            progressIndicator.centerXAnchor.constraint(equalTo: progressBox.centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 12),
            progressLabel.leadingAnchor.constraint(equalTo: progressBox.leadingAnchor, constant: 16),
            progressLabel.trailingAnchor.constraint(equalTo: progressBox.trailingAnchor, constant: -16),
            progressBar.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 16),
            progressBar.leadingAnchor.constraint(equalTo: progressBox.leadingAnchor, constant: 20),
            progressBar.trailingAnchor.constraint(equalTo: progressBox.trailingAnchor, constant: -20),
            progressBar.heightAnchor.constraint(equalToConstant: 6)
        ])

        // 整体布局
        var lastView: UIView = titleLabel
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 70),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
        ])
        lastView = subtitleLabel

        NSLayoutConstraint.activate([
            storageCard.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 16),
            storageCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            storageCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            storageTitleLabel.topAnchor.constraint(equalTo: storageCard.topAnchor, constant: 14),
            storageTitleLabel.leadingAnchor.constraint(equalTo: storageCard.leadingAnchor, constant: 16),
            storageProgressView.topAnchor.constraint(equalTo: storageTitleLabel.bottomAnchor, constant: 12),
            storageProgressView.leadingAnchor.constraint(equalTo: storageCard.leadingAnchor, constant: 16),
            storageProgressView.trailingAnchor.constraint(equalTo: storageCard.trailingAnchor, constant: -16),
            storageProgressView.heightAnchor.constraint(equalToConstant: 8),
            storageDetailLabel.topAnchor.constraint(equalTo: storageProgressView.bottomAnchor, constant: 10),
            storageDetailLabel.leadingAnchor.constraint(equalTo: storageCard.leadingAnchor, constant: 16),
            storageDetailLabel.trailingAnchor.constraint(equalTo: storageCard.trailingAnchor, constant: -16),
            storageDetailLabel.bottomAnchor.constraint(equalTo: storageCard.bottomAnchor, constant: -14)
        ])
        lastView = storageCard

        NSLayoutConstraint.activate([
            overviewCard.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 12),
            overviewCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            overviewCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            overviewTitleLabel.topAnchor.constraint(equalTo: overviewCard.topAnchor, constant: 14),
            overviewTitleLabel.leadingAnchor.constraint(equalTo: overviewCard.leadingAnchor, constant: 16),
            overviewTotalLabel.topAnchor.constraint(equalTo: overviewTitleLabel.bottomAnchor, constant: 8),
            overviewTotalLabel.leadingAnchor.constraint(equalTo: overviewCard.leadingAnchor, constant: 16),
            overviewCleanableLabel.topAnchor.constraint(equalTo: overviewTotalLabel.bottomAnchor, constant: 6),
            overviewCleanableLabel.leadingAnchor.constraint(equalTo: overviewCard.leadingAnchor, constant: 16),
            overviewValidLabel.topAnchor.constraint(equalTo: overviewCleanableLabel.bottomAnchor, constant: 4),
            overviewValidLabel.leadingAnchor.constraint(equalTo: overviewCard.leadingAnchor, constant: 16),
            overviewValidLabel.bottomAnchor.constraint(equalTo: overviewCard.bottomAnchor, constant: -14)
        ])
        lastView = overviewCard

        for (i, card) in cacheCards.enumerated() {
            NSLayoutConstraint.activate([
                card.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 12),
                card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                card.heightAnchor.constraint(greaterThanOrEqualToConstant: 90)
            ])
            lastView = card
        }

        NSLayoutConstraint.activate([
            quickCleanButton.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 20),
            quickCleanButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            quickCleanButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            quickCleanButton.heightAnchor.constraint(equalToConstant: 48),
            deepCleanButton.topAnchor.constraint(equalTo: quickCleanButton.bottomAnchor, constant: 12),
            deepCleanButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            deepCleanButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            deepCleanButton.heightAnchor.constraint(equalToConstant: 48),
            deepCleanButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -40)
        ])
    }

    private func setupCard(_ card: UIView) {
        card.backgroundColor = .white
        card.layer.cornerRadius = 14
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.06
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowRadius = 8
        card.translatesAutoresizingMaskIntoConstraints = false
    }

    // MARK: - 刷新缓存数据（实时更新）
    private func refreshCacheData() {
        let fileManager = FileManager.default
        if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            let totalSpace = attrs[.systemSize] as? Int64 ?? 0
            let freeSpace = attrs[.systemFreeSize] as? Int64 ?? 0
            let usedSpace = totalSpace - freeSpace
            let usagePercent = totalSpace > 0 ? Float(usedSpace) / Float(totalSpace) : 0
            storageProgressView.setProgress(usagePercent, animated: true)
            storageDetailLabel.text = "总容量: \(formatSize(totalSpace))  |  已使用: \(formatSize(usedSpace))  |  剩余: \(formatSize(freeSpace))"
        }

        cacheSizes[0] = calculateMemoryCacheSize()
        cacheSizes[1] = calculateSessionCacheSize()
        cacheSizes[2] = calculatePersistentCacheSize()
        cacheSizes[3] = calculateOfflineCacheSize()

        for i in 0..<4 {
            cacheSizeLabels[i].text = formatSize(cacheSizes[i])
        }

        let total = cacheSizes.reduce(0, +)
        let cleanable = cacheSizes[0] + cacheSizes[1] + cacheSizes[2]
        let valid = cacheSizes[3]

        overviewTotalLabel.text = formatSize(total)
        overviewCleanableLabel.text = "🗑 可清理垃圾: \(formatSize(cleanable))"
        overviewValidLabel.text = "✅ 有效保留: \(formatSize(valid))"
        // 刷新四级离线网页列表
        rebuildOfflineList()
    }

    // MARK: - 离线网页列表
    private func rebuildOfflineList() {
        guard let stack = offlineListStack else { return }
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
        let items = OfflineCacheManager.shared.allItems()
        if items.isEmpty {
            let emptyLabel = UILabel()
            emptyLabel.text = "暂无离线网页\n切后台自动保存 / 点击工具栏「存」手动保存"
            emptyLabel.font = .systemFont(ofSize: 12)
            emptyLabel.textColor = .gray
            emptyLabel.textAlignment = .center
            emptyLabel.numberOfLines = 0
            stack.addArrangedSubview(emptyLabel)
            return
        }
        for item in items {
            stack.addArrangedSubview(makeOfflineRow(item: item))
        }
    }

    private func makeOfflineRow(item: OfflineCacheManager.OfflineItem) -> UIView {
        let row = UIView()
        row.backgroundColor = UIColor(white: 0.96, alpha: 1.0)
        row.layer.cornerRadius = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        // 标题
        let titleLabel = UILabel()
        titleLabel.text = item.pageTitle
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        titleLabel.textColor = .darkText
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(titleLabel)

        // 来源+时间
        let metaLabel = UILabel()
        let typeTag = item.saveType == "manual" ? "手动" : "自动"
        let statusTag = item.saveStatus == "pending" ? "·待补全" : ""
        let timeStr = DateFormatter.localizedString(from: Date(timeIntervalSince1970: item.saveTimestamp), dateStyle: .short, timeStyle: .short)
        metaLabel.text = "[\(typeTag)] \(timeStr)\(statusTag)"
        metaLabel.font = .systemFont(ofSize: 10)
        metaLabel.textColor = .gray
        metaLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(metaLabel)

        // 打开按钮
        let openButton = UIButton(type: .system)
        openButton.setTitle("打开", for: .normal)
        openButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        openButton.setTitleColor(.white, for: .normal)
        openButton.backgroundColor = UIColor(red: 0.55, green: 0.45, blue: 0.85, alpha: 1.0)
        openButton.layer.cornerRadius = 6
        openButton.tag = 0
        openButton.translatesAutoresizingMaskIntoConstraints = false
        openButton.addTarget(self, action: #selector(openOfflineItem(_:)), for: .touchUpInside)
        row.addSubview(openButton)
        // 存uuid到按钮的关联
        objc_setAssociatedObject(openButton, &offlineItemKey, item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        // 删除按钮
        let deleteButton = UIButton(type: .system)
        deleteButton.setTitle("删除", for: .normal)
        deleteButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .medium)
        deleteButton.setTitleColor(.white, for: .normal)
        deleteButton.backgroundColor = UIColor(red: 0.90, green: 0.45, blue: 0.25, alpha: 1.0)
        deleteButton.layer.cornerRadius = 6
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        deleteButton.addTarget(self, action: #selector(deleteOfflineItem(_:)), for: .touchUpInside)
        row.addSubview(deleteButton)
        objc_setAssociatedObject(deleteButton, &offlineItemKey, item, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            titleLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),

            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            openButton.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            openButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            openButton.widthAnchor.constraint(equalToConstant: 42),
            openButton.heightAnchor.constraint(equalToConstant: 26),

            deleteButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -6),
            deleteButton.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 42),
            deleteButton.heightAnchor.constraint(equalToConstant: 26),

            row.heightAnchor.constraint(equalToConstant: 56),
            metaLabel.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -6)
        ])
        return row
    }

    // MARK: - 离线网页操作
    @objc private func openOfflineItem(_ sender: UIButton) {
        guard let item = objc_getAssociatedObject(sender, &offlineItemKey) as? OfflineCacheManager.OfflineItem,
              let localURL = OfflineCacheManager.shared.localURL(for: item) else {
            showToast("离线文件不存在")
            return
        }
        // push 方式打开，返回用 pop；通知主控制器加载本地离线网页
        navigationController?.popViewController(animated: true)
        NotificationCenter.default.post(name: NSNotification.Name("OpenOfflinePage"), object: nil, userInfo: ["url": localURL.absoluteString])
    }

    @objc private func deleteOfflineItem(_ sender: UIButton) {
        guard let item = objc_getAssociatedObject(sender, &offlineItemKey) as? OfflineCacheManager.OfflineItem else { return }
        let alert = UIAlertController(title: "删除离线网页", message: "将解除保护并删除：\(item.pageTitle)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { _ in
            _ = OfflineCacheManager.shared.deleteItem(uuid: item.uuid)
            self.refreshCacheData()
            self.showToast("已删除")
        })
        present(alert, animated: true)
    }

    private func calculateMemoryCacheSize() -> Int64 {
        let memCapacity = Int64(URLCache.shared.memoryCapacity)
        return min(memCapacity, 80 * 1024 * 1024)
    }

    private func calculateSessionCacheSize() -> Int64 {
        return 12 * 1024 * 1024
    }

    private func calculatePersistentCacheSize() -> Int64 {
        let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""
        return folderSize(atPath: cacheDir)
    }

    private func calculateOfflineCacheSize() -> Int64 {
        return OfflineCacheManager.shared.totalSize()
    }

    private func folderSize(atPath path: String) -> Int64 {
        let fileManager = FileManager.default
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

    private func formatSize(_ size: Int64) -> String {
        if size >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", Double(size) / 1024.0 / 1024.0 / 1024.0)
        } else if size >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(size) / 1024.0 / 1024.0)
        } else if size >= 1024 {
            return String(format: "%.1f KB", Double(size) / 1024.0)
        } else {
            return "\(size) B"
        }
    }

    // MARK: - 清理单个缓存（带进度条，完成后实时刷新）
    @objc private func cleanSingleCache(_ sender: UIButton) {
        guard !isCleaning else { return }
        let index = sender.tag
        guard index != 3 else {
            showToast("四级离线缓存已保护，禁止清理")
            return
        }

        isCleaning = true
        showProgressOverlay("正在清理\(cacheNames[index])...")

        cacheProgressViews[index].isHidden = false
        cacheProgressViews[index].setProgress(0, animated: false)

        var progress: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            progress += 0.05
            self.cacheProgressViews[index].setProgress(progress, animated: true)
            self.progressBar.setProgress(progress, animated: true)
            if progress >= 1.0 {
                timer.invalidate()
                self.performClean(forLevel: index)
                self.cacheSizes[index] = 0
                self.cacheSizeLabels[index].text = "0 B"
                self.cacheProgressViews[index].isHidden = true
                self.refreshCacheData() // 实时刷新总量
                self.hideProgressOverlay()
                self.isCleaning = false
                self.showToast("\(self.cacheNames[index]) 已清理")
            }
        }
    }

    private func performClean(forLevel level: Int) {
        switch level {
        case 0:
            URLCache.shared.removeAllCachedResponses()
        case 1:
            break
        case 2:
            let cacheDir = NSSearchPathForDirectoriesInDomains(.cachesDirectory, .userDomainMask, true).first ?? ""
            try? FileManager.default.removeItem(atPath: cacheDir)
            try? FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
        case 3:
            let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? ""
            let offlineDir = (docsDir as NSString).appendingPathComponent("offline")
            try? FileManager.default.removeItem(atPath: offlineDir)
        default:
            break
        }
    }

    @objc private func quickClean() {
        guard !isCleaning else { return }
        isCleaning = true
        showProgressOverlay("正在一键清理垃圾...")

        var progress: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            progress += 0.04
            self.progressBar.setProgress(progress, animated: true)
            if progress >= 1.0 {
                timer.invalidate()
                self.performClean(forLevel: 0)
                self.performClean(forLevel: 1)
                self.cacheSizes[0] = 0
                self.cacheSizes[1] = 0
                self.refreshCacheData()
                self.hideProgressOverlay()
                self.isCleaning = false
                self.showToast("一键清理完成")
            }
        }
    }

    @objc private func deepClean() {
        guard !isCleaning else { return }
        isCleaning = true
        showProgressOverlay("正在深度清理...")

        var progress: Float = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            progress += 0.03
            self.progressBar.setProgress(progress, animated: true)
            if progress >= 1.0 {
                timer.invalidate()
                for i in 0...2 {
                    self.performClean(forLevel: i)
                    self.cacheSizes[i] = 0
                }
                self.refreshCacheData()
                self.hideProgressOverlay()
                self.isCleaning = false
                self.showToast("深度清理完成，离线资源已保留")
            }
        }
    }

    // MARK: - 长按深度清理 → 全部删除（包括四级）
    @objc private func deepCleanLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            guard !isCleaning else { return }

            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()

            let alert = UIAlertController(
                title: "⚠️ 全部删除确认",
                message: "长按触发全部删除！将清空所有四级缓存，包括受保护的离线资源，此操作不可恢复！",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "取消", style: .cancel))
            alert.addAction(UIAlertAction(title: "全部删除", style: .destructive) { _ in
                self.isCleaning = true
                self.showProgressOverlay("正在全部删除...")

                var progress: Float = 0
                Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
                    progress += 0.025
                    self.progressBar.setProgress(progress, animated: true)
                    if progress >= 1.0 {
                        timer.invalidate()
                        for i in 0...3 {
                            self.performClean(forLevel: i)
                            self.cacheSizes[i] = 0
                        }
                        self.refreshCacheData()
                        self.hideProgressOverlay()
                        self.isCleaning = false
                        self.showToast("全部缓存已删除")
                    }
                }
            })
            present(alert, animated: true)
        }
    }

    private func showProgressOverlay(_ text: String) {
        progressLabel.text = text
        progressOverlay.isHidden = false
        progressIndicator.startAnimating()
        progressBar.setProgress(0, animated: false)
    }

    private func hideProgressOverlay() {
        progressOverlay.isHidden = true
        progressIndicator.stopAnimating()
    }

    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.backgroundColor = UIColor(white: 0, alpha: 0.75)
        toast.textColor = .white
        toast.font = UIFont.systemFont(ofSize: 14)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 10
        toast.clipsToBounds = true
        toast.numberOfLines = 0
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -100),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 280),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        ])

        UIView.animate(withDuration: 0.3, delay: 1.5, options: .curveEaseOut, animations: {
            toast.alpha = 0
        }, completion: { _ in
            toast.removeFromSuperview()
        })
    }
}
