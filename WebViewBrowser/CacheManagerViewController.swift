//
//  CacheManagerViewController.swift
//  轻量浏览器 - 全屏四级缓存管理
//

import UIKit

class CacheManagerViewController: UIViewController {
    
    // MARK: - 数据模型
    struct CacheLevelInfo {
        let level: Int
        let name: String
        let description: String
        var size: Int64
        let color: UIColor
        let canOneKeyClear: Bool
    }
    
    // MARK: - 属性
    private var cacheLevels: [CacheLevelInfo] = []
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    // MARK: - 生命周期
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadCacheData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
    // MARK: - UI 设置
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // 滚动视图
        scrollView.translatesAutoresizingMaskIntoConstraints = false
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
        
        setupHeader()
        setupDeviceStorageCard()
        setupCacheOverviewCard()
        setupCacheLevelList()
        setupBottomButtons()
    }
    
    // MARK: - 顶部标题
    private func setupHeader() {
        let headerView = UIView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(headerView)
        
        // 关闭按钮
        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .secondaryLabel
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        headerView.addSubview(closeButton)
        
        // 标题
        let titleLabel = UILabel()
        titleLabel.text = "缓存资源管理中心"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(titleLabel)
        
        // 副标题
        let subtitleLabel = UILabel()
        subtitleLabel.text = "四级分层缓存 · 精准清理不丢有效资源"
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        headerView.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            headerView.heightAnchor.constraint(equalToConstant: 70),
            
            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 32),
            closeButton.heightAnchor.constraint(equalToConstant: 32),
            
            titleLabel.topAnchor.constraint(equalTo: headerView.topAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor)
        ])
    }
    
    // MARK: - 设备存储卡片
    private func setupDeviceStorageCard() {
        let card = createCardView()
        contentView.addSubview(card)
        
        let titleLabel = UILabel()
        titleLabel.text = "📱 设备存储状态"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        
        // 进度条
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.trackTintColor = .secondarySystemBackground
        card.addSubview(progressView)
        
        // 存储信息
        let infoLabel = UILabel()
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.textColor = .secondaryLabel
        infoLabel.numberOfLines = 0
        infoLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(infoLabel)
        
        // 状态提示
        let statusLabel = UILabel()
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.textAlignment = .right
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(statusLabel)
        
        // 获取存储信息
        let storage = getDeviceStorage()
        let usedPercent = storage.total > 0 ? Float(storage.used) / Float(storage.total) : 0
        progressView.progress = usedPercent
        
        if usedPercent > 0.9 {
            progressView.progressTintColor = .systemRed
            statusLabel.text = "⚠️ 空间不足"
            statusLabel.textColor = .systemRed
        } else if usedPercent > 0.7 {
            progressView.progressTintColor = .systemOrange
            statusLabel.text = "⚡ 空间一般"
            statusLabel.textColor = .systemOrange
        } else {
            progressView.progressTintColor = .systemGreen
            statusLabel.text = "✅ 空间充足"
            statusLabel.textColor = .systemGreen
        }
        
        infoLabel.text = "总容量：\(formatBytes(storage.total))\n已使用：\(formatBytes(storage.used))\n剩余可用：\(formatBytes(storage.free))"
        
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 100),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            statusLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            
            progressView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            progressView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            progressView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            progressView.heightAnchor.constraint(equalToConstant: 8),
            
            infoLabel.topAnchor.constraint(equalTo: progressView.bottomAnchor, constant: 12),
            infoLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            infoLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            infoLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        
        card.tag = 100
    }
    
    // MARK: - 缓存总览卡片
    private func setupCacheOverviewCard() {
        let card = createCardView()
        contentView.addSubview(card)
        
        let titleLabel = UILabel()
        titleLabel.text = "📦 浏览器缓存总览"
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(titleLabel)
        
        // 总缓存大小
        let totalSizeLabel = UILabel()
        totalSizeLabel.font = .systemFont(ofSize: 28, weight: .bold)
        totalSizeLabel.textColor = .systemBlue
        totalSizeLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(totalSizeLabel)
        
        // 分类信息
        let junkLabel = UILabel()
        junkLabel.font = .systemFont(ofSize: 13)
        junkLabel.textColor = .secondaryLabel
        junkLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(junkLabel)
        
        let usefulLabel = UILabel()
        usefulLabel.font = .systemFont(ofSize: 13)
        usefulLabel.textColor = .secondaryLabel
        usefulLabel.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(usefulLabel)
        
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 260),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            totalSizeLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            totalSizeLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            junkLabel.topAnchor.constraint(equalTo: totalSizeLabel.bottomAnchor, constant: 8),
            junkLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            
            usefulLabel.topAnchor.constraint(equalTo: junkLabel.bottomAnchor, constant: 4),
            usefulLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            usefulLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
        
        card.tag = 101
    }
    
    // MARK: - 四级缓存列表
    private func setupCacheLevelList() {
        let sectionLabel = UILabel()
        sectionLabel.text = "📋 四级缓存明细"
        sectionLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        sectionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sectionLabel)
        
        NSLayoutConstraint.activate([
            sectionLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 400),
            sectionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20)
        ])
        
        var previousView: UIView = sectionLabel
        
        for (index, level) in cacheLevels.enumerated() {
            let row = createCacheLevelRow(level: level, index: index)
            contentView.addSubview(row)
            
            NSLayoutConstraint.activate([
                row.topAnchor.constraint(equalTo: previousView.bottomAnchor, constant: index == 0 ? 12 : 8),
                row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
                row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
                row.heightAnchor.constraint(equalToConstant: 90)
            ])
            
            previousView = row
        }
        
        // 更新contentView底部约束
        if let last = contentView.subviews.last(where: { $0 is CacheLevelRow }) {
            NSLayoutConstraint.activate([
                last.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -100)
            ])
        }
    }
    
    // MARK: - 创建缓存行
    private func createCacheLevelRow(level: CacheLevelInfo, index: Int) -> CacheLevelRow {
        let row = CacheLevelRow()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.configure(with: level)
        row.clearButton.tag = index
        row.clearButton.addTarget(self, action: #selector(clearLevelTapped(_:)), for: .touchUpInside)
        return row
    }
    
    // MARK: - 底部按钮
    private func setupBottomButtons() {
        let buttonContainer = UIView()
        buttonContainer.translatesAutoresizingMaskIntoConstraints = false
        buttonContainer.backgroundColor = .systemBackground
        view.addSubview(buttonContainer)
        
        // 一键清理垃圾缓存
        let junkButton = createActionButton(
            title: "🗑 一键清理垃圾",
            subtitle: "清理一级+二级缓存",
            color: .systemOrange
        )
        junkButton.addTarget(self, action: #selector(clearJunkTapped), for: .touchUpInside)
        buttonContainer.addSubview(junkButton)
        
        // 深度清理全部缓存
        let deepButton = createActionButton(
            title: "🧹 深度清理全部",
            subtitle: "清理一/二/三级，保留离线资源",
            color: .systemRed
        )
        deepButton.addTarget(self, action: #selector(clearAllTapped), for: .touchUpInside)
        buttonContainer.addSubview(deepButton)
        
        NSLayoutConstraint.activate([
            buttonContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            buttonContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            buttonContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            buttonContainer.heightAnchor.constraint(equalToConstant: 120),
            
            junkButton.leadingAnchor.constraint(equalTo: buttonContainer.leadingAnchor, constant: 16),
            junkButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: 12),
            junkButton.widthAnchor.constraint(equalTo: buttonContainer.widthAnchor, multiplier: 0.5, constant: -24),
            junkButton.heightAnchor.constraint(equalToConstant: 50),
            
            deepButton.trailingAnchor.constraint(equalTo: buttonContainer.trailingAnchor, constant: -16),
            deepButton.topAnchor.constraint(equalTo: buttonContainer.topAnchor, constant: 12),
            deepButton.widthAnchor.constraint(equalTo: buttonContainer.widthAnchor, multiplier: 0.5, constant: -24),
            deepButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }
    
    // MARK: - 创建操作按钮
    private func createActionButton(title: String, subtitle: String, color: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.backgroundColor = color
        button.layer.cornerRadius = 12
        button.tintColor = .white
        
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(titleLabel)
        
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.font = .systemFont(ofSize: 10)
        subtitleLabel.textColor = .white.withAlphaComponent(0.8)
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(subtitleLabel)
        
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: button.topAnchor, constant: 8),
            titleLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.centerXAnchor.constraint(equalTo: button.centerXAnchor)
        ])
        
        return button
    }
    
    // MARK: - 创建卡片
    private func createCardView() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        return card
    }
    
    // MARK: - 加载缓存数据
    private func loadCacheData() {
        // 四级缓存信息
        cacheLevels = [
            CacheLevelInfo(
                level: 1,
                name: "一级 · 实时临时缓存",
                description: "网页实时临时碎片，关闭App自动释放",
                size: 80 * 1024 * 1024, // 内存上限80MB
                color: .systemBlue,
                canOneKeyClear: true
            ),
            CacheLevelInfo(
                level: 2,
                name: "二级 · 本次会话缓存",
                description: "本次浏览所有临时资源，重启即失效",
                size: getDirectorySize(path: "TempWebCache"),
                color: .systemTeal,
                canOneKeyClear: true
            ),
            CacheLevelInfo(
                level: 3,
                name: "三级 · 持久资源缓存",
                description: "常用网站静态资源，提升重复打开速度",
                size: getDirectorySize(path: "StaticWebCache"),
                color: .systemGreen,
                canOneKeyClear: true
            ),
            CacheLevelInfo(
                level: 4,
                name: "四级 · 离线留存缓存",
                description: "离线网页、保存资源（个人有效数据）",
                size: 0,
                color: .systemPurple,
                canOneKeyClear: false
            )
        ]
        
        // 更新总览卡片
        updateOverviewCard()
        
        // 更新列表
        for (index, row) in contentView.subviews.enumerated() {
            if let cacheRow = row as? CacheLevelRow, index < cacheLevels.count + 5 {
                cacheRow.configure(with: cacheLevels[index - 5])
            }
        }
    }
    
    // MARK: - 更新总览卡片
    private func updateOverviewCard() {
        let totalSize = cacheLevels.reduce(0) { $0 + $1.size }
        let junkSize = cacheLevels.filter { $0.canOneKeyClear }.reduce(0) { $0 + $1.size }
        let usefulSize = cacheLevels.filter { !$0.canOneKeyClear }.reduce(0) { $0 + $1.size }
        
        for subview in contentView.subviews {
            if subview.tag == 101 {
                for label in subview.subviews {
                    if let label = label as? UILabel {
                        if label.font == .systemFont(ofSize: 28, weight: .bold) {
                            label.text = formatBytes(totalSize)
                        } else if label.text?.contains("可清理") == true || label.text?.contains("垃圾") == true {
                            label.text = "🗑 可清理垃圾缓存：\(formatBytes(junkSize))"
                        } else if label.text?.contains("有效") == true || label.text?.contains("保留") == true {
                            label.text = "💾 有效保留资源：\(formatBytes(usefulSize))"
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 获取目录大小
    private func getDirectorySize(path: String) -> Int64 {
        let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowserCache", isDirectory: true)
            .appendingPathComponent(path, isDirectory: true)
        
        var totalSize: Int64 = 0
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheBase, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        }
        return totalSize
    }
    
    // MARK: - 获取设备存储
    private func getDeviceStorage() -> (total: Int64, used: Int64, free: Int64) {
        let fileManager = FileManager.default
        if let attrs = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            let total = attrs[.systemSize] as? Int64 ?? 0
            let free = attrs[.systemFreeSize] as? Int64 ?? 0
            return (total, total - free, free)
        }
        return (0, 0, 0)
    }
    
    // MARK: - 格式化字节
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", Double(bytes) / 1024 / 1024 / 1024)
        } else if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return "\(bytes) B"
        }
    }
    
    // MARK: - 按钮动作
    @objc private func closeTapped() {
        dismiss(animated: true)
    }
    
    @objc private func clearLevelTapped(_ sender: UIButton) {
        let index = sender.tag
        guard index < cacheLevels.count else { return }
        let level = cacheLevels[index]
        
        let alert = UIAlertController(
            title: "确认清理",
            message: "确定要清理「\(level.name)」吗？\n将释放 \(formatBytes(level.size)) 空间",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清理", style: .destructive) { [weak self] _ in
            self?.clearCacheLevel(index: index)
        })
        present(alert, animated: true)
    }
    
    @objc private func clearJunkTapped() {
        let junkSize = cacheLevels.filter { $0.canOneKeyClear }.reduce(0) { $0 + $1.size }
        
        let alert = UIAlertController(
            title: "一键清理垃圾缓存",
            message: "将清理一级+二级缓存（纯垃圾，不伤及有效资源）\n预计释放 \(formatBytes(junkSize))",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "开始清理", style: .default) { [weak self] _ in
            self?.clearJunkCache()
        })
        present(alert, animated: true)
    }
    
    @objc private func clearAllTapped() {
        let alert = UIAlertController(
            title: "深度清理全部缓存",
            message: "将清理一/二/三级缓存，保留四级离线个人资源\n确定要继续吗？",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "深度清理", style: .destructive) { [weak self] _ in
            self?.clearAllCache()
        })
        present(alert, animated: true)
    }
    
    // MARK: - 清理操作
    private func clearCacheLevel(index: Int) {
        let level = cacheLevels[index]
        
        if level.level == 1 {
            // 一级：清理内存缓存
            URLCache.shared.removeAllCachedResponses()
        } else if level.level == 2 || level.level == 3 {
            // 二/三级：清理磁盘缓存
            let cacheBase = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("BrowserCache", isDirectory: true)
            let path = level.level == 2 ? "TempWebCache" : "StaticWebCache"
            let dir = cacheBase.appendingPathComponent(path, isDirectory: true)
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        
        cacheLevels[index].size = 0
        loadCacheData()
        showToast("「\(level.name)」清理完成")
    }
    
    private func clearJunkCache() {
        for i in 0..<cacheLevels.count where cacheLevels[i].canOneKeyClear {
            clearCacheLevel(index: i)
        }
        showToast("垃圾缓存清理完成")
    }
    
    private func clearAllCache() {
        for i in 0..<cacheLevels.count where cacheLevels[i].level != 4 {
            clearCacheLevel(index: i)
        }
        showToast("深度清理完成，离线资源已保留")
    }
    
    // MARK: - Toast提示
    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        toast.textColor = .white
        toast.textAlignment = .center
        toast.font = .systemFont(ofSize: 14)
        toast.layer.cornerRadius = 20
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -150),
            toast.heightAnchor.constraint(equalToConstant: 40),
            toast.widthAnchor.constraint(equalToConstant: 250)
        ])
        
        UIView.animate(withDuration: 0.3, delay: 1.5, options: .curveEaseOut) {
            toast.alpha = 0
        } completion: { _ in
            toast.removeFromSuperview()
        }
    }
}

// MARK: - 缓存行视图
class CacheLevelRow: UIView {
    let clearButton = UIButton(type: .system)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        
        // 颜色指示器
        let colorIndicator = UIView()
        colorIndicator.translatesAutoresizingMaskIntoConstraints = false
        colorIndicator.layer.cornerRadius = 4
        colorIndicator.tag = 1
        addSubview(colorIndicator)
        
        // 名称
        let nameLabel = UILabel()
        nameLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        nameLabel.tag = 2
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(nameLabel)
        
        // 描述
        let descLabel = UILabel()
        descLabel.font = .systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabel
        descLabel.numberOfLines = 0
        descLabel.tag = 3
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(descLabel)
        
        // 大小
        let sizeLabel = UILabel()
        sizeLabel.font = .systemFont(ofSize: 16, weight: .bold)
        sizeLabel.textColor = .systemBlue
        sizeLabel.textAlignment = .right
        sizeLabel.tag = 4
        sizeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sizeLabel)
        
        // 清理按钮
        clearButton.setTitle("清理", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        clearButton.backgroundColor = .systemGray5
        clearButton.layer.cornerRadius = 8
        clearButton.tintColor = .label
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)
        
        NSLayoutConstraint.activate([
            colorIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            colorIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            colorIndicator.widthAnchor.constraint(equalToConstant: 6),
            colorIndicator.heightAnchor.constraint(equalToConstant: 40),
            
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            nameLabel.leadingAnchor.constraint(equalTo: colorIndicator.trailingAnchor, constant: 10),
            
            descLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            descLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            descLabel.trailingAnchor.constraint(equalTo: sizeLabel.leadingAnchor, constant: -8),
            
            sizeLabel.topAnchor.constraint(equalTo: topAnchor, constant: 14),
            sizeLabel.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -10),
            
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 50),
            clearButton.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    func configure(with level: CacheManagerViewController.CacheLevelInfo) {
        if let colorIndicator = viewWithTag(1) as? UIView {
            colorIndicator.backgroundColor = level.color
        }
        if let nameLabel = viewWithTag(2) as? UILabel {
            nameLabel.text = level.name
        }
        if let descLabel = viewWithTag(3) as? UILabel {
            descLabel.text = level.description
        }
        if let sizeLabel = viewWithTag(4) as? UILabel {
            sizeLabel.text = formatBytes(level.size)
        }
        
        if !level.canOneKeyClear {
            clearButton.setTitle("保护", for: .normal)
            clearButton.backgroundColor = .systemGreen.withAlphaComponent(0.2)
            clearButton.tintColor = .systemGreen
            clearButton.isEnabled = false
        } else {
            clearButton.setTitle("清理", for: .normal)
            clearButton.backgroundColor = .systemGray5
            clearButton.tintColor = .label
            clearButton.isEnabled = true
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        if bytes >= 1024 * 1024 * 1024 {
            return String(format: "%.2f GB", Double(bytes) / 1024 / 1024 / 1024)
        } else if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return "\(bytes) B"
        }
    }
}
