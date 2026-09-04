import UIKit

// MARK: - 下载管理面板（Bottom Sheet）
class DownloadPanelViewController: UIViewController {
    private var tableView: UITableView!
    private var segmentControl: UISegmentedControl!
    private var searchBar: UISearchBar!
    private var filterButton: UIButton!
    private var editButton: UIButton!
    private var currentTab: Int = 0 // 0=进行中, 1=已完成
    private var currentFilter: DownloadTask.FileType? = nil
    private var searchText: String = ""
    private var isEditingMode: Bool = false
    private var selectedIds: Set<String> = []
    
    var onDismiss: (() -> Void)?
    
    private var filteredTasks: [DownloadTask] {
        var list = DownloadManager.shared.allTasks()
        if currentTab == 0 {
            list = list.filter { $0.status == .downloading || $0.status == .paused }
        } else {
            list = list.filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
        }
        if let filter = currentFilter {
            list = list.filter { $0.fileType == filter }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.fileName.lowercased().contains(searchText.lowercased()) }
        }
        return list.sorted { $0.startTime > $1.startTime }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        DownloadManager.shared.onProgress = { [weak self] _ in
            DispatchQueue.main.async { self?.tableView.reloadData() }
        }
        DownloadManager.shared.onStatusChanged = { [weak self] _ in
            DispatchQueue.main.async { self?.tableView.reloadData() }
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        view.layer.cornerRadius = 16
        view.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        
        // 顶部把手
        let handle = UIView()
        handle.backgroundColor = .systemGray4
        handle.layer.cornerRadius = 3
        handle.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(handle)
        
        // 标题
        let titleLabel = UILabel()
        titleLabel.text = "下载内容"
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
        
        // 编辑按钮
        editButton = UIButton(type: .system)
        editButton.setTitle("编辑", for: .normal)
        editButton.titleLabel?.font = .systemFont(ofSize: 16)
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.addTarget(self, action: #selector(toggleEdit), for: .touchUpInside)
        view.addSubview(editButton)
        
        // 打开文件夹按钮
        let folderBtn = UIButton(type: .system)
        folderBtn.setImage(UIImage(systemName: "folder"), for: .normal)
        folderBtn.tintColor = .systemBlue
        folderBtn.translatesAutoresizingMaskIntoConstraints = false
        folderBtn.addTarget(self, action: #selector(openDownloadsFolder), for: .touchUpInside)
        view.addSubview(folderBtn)
        
        // 关闭按钮
        let closeBtn = UIButton(type: .system)
        closeBtn.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeBtn.tintColor = .systemGray3
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        view.addSubview(closeBtn)
        
        // Segment
        segmentControl = UISegmentedControl(items: ["进行中", "已完成"])
        segmentControl.selectedSegmentIndex = 0
        segmentControl.translatesAutoresizingMaskIntoConstraints = false
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        view.addSubview(segmentControl)
        
        // 搜索栏
        searchBar = UISearchBar()
        searchBar.placeholder = "搜索下载文件"
        searchBar.searchBarStyle = .minimal
        searchBar.delegate = self
        searchBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(searchBar)
        
        // 筛选按钮
        filterButton = UIButton(type: .system)
        filterButton.setTitle("全部类型 ▾", for: .normal)
        filterButton.titleLabel?.font = .systemFont(ofSize: 14)
        filterButton.translatesAutoresizingMaskIntoConstraints = false
        filterButton.addTarget(self, action: #selector(showFilterMenu), for: .touchUpInside)
        view.addSubview(filterButton)
        
        // 表格
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(DownloadCell.self, forCellReuseIdentifier: "DownloadCell")
        tableView.rowHeight = 70
        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.allowsMultipleSelectionDuringEditing = true
        view.addSubview(tableView)
        
        // 批量删除按钮（编辑模式显示）
        let batchDeleteBtn = UIButton(type: .system)
        batchDeleteBtn.setTitle("删除选中", for: .normal)
        batchDeleteBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .medium)
        batchDeleteBtn.backgroundColor = .systemRed
        batchDeleteBtn.setTitleColor(.white, for: .normal)
        batchDeleteBtn.layer.cornerRadius = 8
        batchDeleteBtn.translatesAutoresizingMaskIntoConstraints = false
        batchDeleteBtn.isHidden = true
        batchDeleteBtn.tag = 999
        batchDeleteBtn.addTarget(self, action: #selector(batchDelete), for: .touchUpInside)
        view.addSubview(batchDeleteBtn)
        
        NSLayoutConstraint.activate([
            handle.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            handle.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            handle.widthAnchor.constraint(equalToConstant: 40),
            handle.heightAnchor.constraint(equalToConstant: 6),
            
            titleLabel.topAnchor.constraint(equalTo: handle.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            
            editButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            editButton.trailingAnchor.constraint(equalTo: closeBtn.leadingAnchor, constant: -12),
            
            closeBtn.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeBtn.widthAnchor.constraint(equalToConstant: 30),
            closeBtn.heightAnchor.constraint(equalToConstant: 30),
            
            segmentControl.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            segmentControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            
            searchBar.topAnchor.constraint(equalTo: segmentControl.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: filterButton.leadingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 44),
            
            filterButton.centerYAnchor.constraint(equalTo: searchBar.centerYAnchor),
            filterButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            filterButton.widthAnchor.constraint(equalToConstant: 90),
            
            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: batchDeleteBtn.topAnchor, constant: -8),
            
            batchDeleteBtn.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            batchDeleteBtn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            batchDeleteBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            batchDeleteBtn.heightAnchor.constraint(equalToConstant: 44),
        ])
    }
    
    @objc private func closeTapped() {
        dismiss(animated: true) { self.onDismiss?() }
    }
    
    @objc private func segmentChanged() {
        currentTab = segmentControl.selectedSegmentIndex
        tableView.reloadData()
    }
    
    @objc private func toggleEdit() {
        isEditingMode.toggle()
        tableView.setEditing(isEditingMode, animated: true)
        editButton.setTitle(isEditingMode ? "完成" : "编辑", for: .normal)
        view.viewWithTag(999)?.isHidden = !isEditingMode
        selectedIds.removeAll()
    }
    
    @objc private func batchDelete() {
        let alert = UIAlertController(title: "确认删除", message: "删除选中的 \(selectedIds.count) 项？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "仅删除记录", style: .default) { _ in
            for id in self.selectedIds { DownloadManager.shared.remove(id: id, deleteFile: false) }
            self.selectedIds.removeAll()
            self.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "同时删除文件", style: .destructive) { _ in
            for id in self.selectedIds { DownloadManager.shared.remove(id: id, deleteFile: true) }
            self.selectedIds.removeAll()
            self.tableView.reloadData()
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }
    
    @objc private func showFilterMenu() {
        let alert = UIAlertController(title: "按类型筛选", message: nil, preferredStyle: .actionSheet)
        let types: [(String, DownloadTask.FileType?)] = [
            ("全部", nil), ("文档", .document), ("图片", .image),
            ("视频", .video), ("音频", .audio), ("压缩包", .archive), ("其他", .other)
        ]
        for (name, type) in types {
            alert.addAction(UIAlertAction(title: name, style: .default) { _ in
                self.currentFilter = type
                self.filterButton.setTitle("\(name) ▾", for: .normal)
                self.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = filterButton
            popover.sourceRect = filterButton.bounds
        }
        present(alert, animated: true)
    }
}

extension DownloadPanelViewController: UITableViewDelegate, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let count = filteredTasks.count
        if count == 0 {
            tableView.setEmptyMessage("暂无下载内容")
        } else {
            tableView.restoreEmptyMessage()
        }
        return count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DownloadCell", for: indexPath) as! DownloadCell
        let task = filteredTasks[indexPath.row]
        cell.configure(with: task)
        cell.onAction = { [weak self] action in
            self?.handleCellAction(task: task, action: action)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if isEditingMode {
            let task = filteredTasks[indexPath.row]
            selectedIds.insert(task.id)
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        let task = filteredTasks[indexPath.row]
        if task.status == .completed, let path = task.localPath {
            let url = URL(fileURLWithPath: path)
            let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            present(activityVC, animated: true)
        }
    }
    
    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if isEditingMode {
            let task = filteredTasks[indexPath.row]
            selectedIds.remove(task.id)
        }
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        if isEditingMode { return nil }
        let task = filteredTasks[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { _, _, completion in
            DownloadManager.shared.remove(id: task.id, deleteFile: true)
            tableView.reloadData()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }
    
    private func handleCellAction(task: DownloadTask, action: DownloadCell.Action) {
        switch action {
        case .pause: DownloadManager.shared.pause(id: task.id)
        case .resume: DownloadManager.shared.resume(id: task.id)
        case .cancel: DownloadManager.shared.cancel(id: task.id)
        case .retry:
            DownloadManager.shared.remove(id: task.id)
            DownloadManager.shared.startDownload(url: task.url, fileName: task.fileName)
        case .share:
            if let path = task.localPath {
                let url = URL(fileURLWithPath: path)
                let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                present(vc, animated: true)
            }
        }
        tableView.reloadData()
    }
}

extension DownloadPanelViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
        tableView.reloadData()
    }
}

// MARK: - 下载单元格
class DownloadCell: UITableViewCell {
    enum Action { case pause, resume, cancel, retry, share }
    var onAction: ((Action) -> Void)?
    
    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let progressView = UIProgressView()
    private let actionButton = UIButton(type: .system)
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    required init?(coder: NSCoder) { fatalError() }
    
    private func setupUI() {
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .systemBlue
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)
        
        nameLabel.font = .systemFont(ofSize: 15, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)
        
        detailLabel.font = .systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabel
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(detailLabel)
        
        progressView.progressTintColor = .systemBlue
        progressView.trackTintColor = .systemGray5
        progressView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(progressView)
        
        actionButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        contentView.addSubview(actionButton)
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 32),
            iconView.heightAnchor.constraint(equalToConstant: 32),
            
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            nameLabel.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -8),
            
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            
            progressView.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 4),
            progressView.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            progressView.heightAnchor.constraint(equalToConstant: 4),
            
            actionButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            actionButton.widthAnchor.constraint(equalToConstant: 50),
        ])
    }
    
    private var currentAction: DownloadCell.Action = .pause
    
    @objc private func actionTapped() {
        onAction?(currentAction)
    }
    
    func configure(with task: DownloadTask) {
        iconView.image = UIImage(systemName: task.fileType.iconName)
        iconView.tintColor = task.fileType.color
        nameLabel.text = task.fileName
        
        switch task.status {
        case .downloading:
            detailLabel.text = "\(task.downloadedText) / \(task.sizeText)  \(Int(task.progress * 100))%"
            progressView.isHidden = false
            progressView.progress = Float(task.progress)
            actionButton.setTitle("暂停", for: .normal)
            actionButton.tintColor = .systemOrange
            currentAction = .pause
        case .paused:
            detailLabel.text = "已暂停  \(task.downloadedText) / \(task.sizeText)"
            progressView.isHidden = false
            progressView.progress = Float(task.progress)
            actionButton.setTitle("继续", for: .normal)
            actionButton.tintColor = .systemBlue
            currentAction = .resume
        case .completed:
            detailLabel.text = "\(task.sizeText)  \(task.timeText)"
            progressView.isHidden = true
            actionButton.setTitle("分享", for: .normal)
            actionButton.tintColor = .systemGreen
            currentAction = .share
        case .failed:
            detailLabel.text = "下载失败  \(task.timeText)"
            progressView.isHidden = true
            actionButton.setTitle("重试", for: .normal)
            actionButton.tintColor = .systemRed
            currentAction = .retry
        case .cancelled:
            detailLabel.text = "已取消  \(task.timeText)"
            progressView.isHidden = true
            actionButton.setTitle("重试", for: .normal)
            actionButton.tintColor = .systemGray
            currentAction = .retry
        }
    }
}

// MARK: - UITableView空状态扩展
extension UITableView {
    func setEmptyMessage(_ message: String) {
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
        label.text = message
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 16)
        backgroundView = label
        separatorStyle = .none
    }
    func restoreEmptyMessage() {
        backgroundView = nil
        separatorStyle = .singleLine
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
                    let alert = UIAlertController(title: "下载路径", message: "文件App → 我的iPhone → 轻浏览 → Downloads", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "知道了", style: .default))
                    self.present(alert, animated: true)
                }
            }
        } else {
            let alert = UIAlertController(title: "下载路径", message: "文件App → 我的iPhone → 轻浏览 → Downloads", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            present(alert, animated: true)
        }
    }


}
