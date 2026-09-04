import UIKit
import WebKit

// MARK: - 下载任务模型
struct DownloadTask: Codable, Equatable {
    let id: String
    var url: String
    var fileName: String
    var fileSize: Int64
    var downloadedSize: Int64
    var status: DownloadStatus
    var startTime: Date
    var finishTime: Date?
    var localPath: String?
    var mimeType: String
    
    enum DownloadStatus: String, Codable {
        case downloading
        case paused
        case completed
        case failed
        case cancelled
    }
    
    var progress: Double {
        guard fileSize > 0 else { return 0 }
        return Double(downloadedSize) / Double(fileSize)
    }
    
    var fileType: FileType {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md": return .document
        case "jpg", "jpeg", "png", "gif", "webp", "bmp", "svg", "heic": return .image
        case "mp4", "mov", "avi", "mkv", "flv", "wmv", "webm": return .video
        case "mp3", "wav", "flac", "aac", "ogg", "m4a": return .audio
        case "zip", "rar", "7z", "tar", "gz": return .archive
        default: return .other
        }
    }
    
    enum FileType: String, Codable {
        case document, image, video, audio, archive, other
        var iconName: String {
            switch self {
            case .document: return "doc.text"
            case .image: return "photo"
            case .video: return "film"
            case .audio: return "music.note"
            case .archive: return "archivebox"
            case .other: return "doc"
            }
        }
        var color: UIColor {
            switch self {
            case .document: return .systemBlue
            case .image: return .systemGreen
            case .video: return .systemPurple
            case .audio: return .systemPink
            case .archive: return .systemOrange
            case .other: return .systemGray
            }
        }
    }
}

// MARK: - 下载管理器
class DownloadManager: NSObject, URLSessionDownloadDelegate {
    static let shared = DownloadManager()
    
    private var session: URLSession!
    private var tasks: [String: DownloadTask] = [:]
    private var urlSessionTasks: [String: URLSessionDownloadTask] = [:]
    private var wkDownloads: [String: WKDownload] = [:]
    private var wkProgressObservers: [String: NSKeyValueObservation] = [:]
    private let taskQueue = DispatchQueue(label: "download.manager.queue")
    private let maxConcurrent = 3
    
    var onProgress: ((DownloadTask) -> Void)?
    var onStatusChanged: ((DownloadTask) -> Void)?
    var onCompleted: ((DownloadTask) -> Void)?
    
    private override init() {
        super.init()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    // MARK: - 持久化
    private let persistenceKey = "persistedDownloadTasks"
    
    private func loadPersistedTasks() {
        guard let data = UserDefaults.standard.data(forKey: persistenceKey),
              let decoded = try? JSONDecoder().decode([DownloadTask].self, from: data) else { return }
        for task in decoded where task.status == .downloading {
            var t = task
            t.status = .paused
            tasks[t.id] = t
        }
        for task in decoded where task.status != .downloading {
            tasks[task.id] = task
        }
    }
    
    private func persist() {
        let list = Array(tasks.values)
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: persistenceKey)
        }
    }
    
    // MARK: - 公共API
    func allTasks() -> [DownloadTask] {
        return taskQueue.sync { Array(tasks.values) }
    }
    
    func activeCount() -> Int {
        return taskQueue.sync { tasks.values.filter { $0.status == .downloading }.count }
    }
    
    func startDownload(url: String, fileName: String? = nil, mimeType: String = "") {
        taskQueue.async { [weak self] in
            guard let self = self else { return }
            let id = UUID().uuidString
            let name = fileName ?? (url as NSString).lastPathComponent
            var task = DownloadTask(
                id: id, url: url, fileName: name, fileSize: 0,
                downloadedSize: 0, status: .downloading,
                startTime: Date(), finishTime: nil, localPath: nil, mimeType: mimeType
            )
            self.tasks[id] = task
            self.persist()
            
            guard let urlObj = URL(string: url) else {
                task.status = .failed
                self.tasks[id] = task
                self.persist()
                DispatchQueue.main.async { self.onStatusChanged?(task) }
                return
            }
            
            let downloadTask = self.session.downloadTask(with: urlObj)
            downloadTask.taskDescription = id
            self.urlSessionTasks[id] = downloadTask
            downloadTask.resume()
            
            DispatchQueue.main.async {
                self.onStatusChanged?(task)
                self.onProgress?(task)
            }
        }
    }
    
    func pause(id: String) {
        taskQueue.async { [weak self] in
            guard let self = self, var task = self.tasks[id],
                  let sessionTask = self.urlSessionTasks[id] else { return }
            task.status = .paused
            self.tasks[id] = task
            sessionTask.suspend()
            self.persist()
            DispatchQueue.main.async { self.onStatusChanged?(task) }
        }
    }
    
    func resume(id: String) {
        taskQueue.async { [weak self] in
            guard let self = self, var task = self.tasks[id],
                  let sessionTask = self.urlSessionTasks[id] else { return }
            task.status = .downloading
            self.tasks[id] = task
            sessionTask.resume()
            self.persist()
            DispatchQueue.main.async { self.onStatusChanged?(task) }
        }
    }
    
    func cancel(id: String) {
        taskQueue.async { [weak self] in
            guard let self = self, var task = self.tasks[id] else { return }
            task.status = .cancelled
            self.tasks[id] = task
            self.urlSessionTasks[id]?.cancel()
            self.urlSessionTasks.removeValue(forKey: id)
            self.persist()
            DispatchQueue.main.async { self.onStatusChanged?(task) }
        }
    }
    
    func remove(id: String, deleteFile: Bool = false) {
        taskQueue.async { [weak self] in
            guard let self = self else { return }
            if deleteFile, let task = self.tasks[id], let path = task.localPath {
                try? FileManager.default.removeItem(atPath: path)
            }
            self.tasks.removeValue(forKey: id)
            self.urlSessionTasks[id]?.cancel()
            self.urlSessionTasks.removeValue(forKey: id)
            self.persist()
        }
    }
    
    func clearCompleted(deleteFiles: Bool = false) {
        taskQueue.async { [weak self] in
            guard let self = self else { return }
            for (id, task) in self.tasks where task.status == .completed {
                if deleteFiles, let path = task.localPath {
                    try? FileManager.default.removeItem(atPath: path)
                }
                self.tasks.removeValue(forKey: id)
            }
            self.persist()
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        taskQueue.sync {
            guard var task = tasks[id] else { return }
            
            // 检查HTTP状态码
            if let httpResponse = downloadTask.response as? HTTPURLResponse {
                guard (200...299).contains(httpResponse.statusCode) else {
                    task.status = .failed
                    tasks[id] = task
                    persist()
                    DispatchQueue.main.async { self.onStatusChanged?(task) }
                    return
                }
                if httpResponse.expectedContentLength > 0 {
                    task.fileSize = httpResponse.expectedContentLength
                }
            }
            
            let fileManager = FileManager.default
            let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let downloadsDir = docsDir.appendingPathComponent("Downloads", isDirectory: true)
            do {
                try fileManager.createDirectory(at: downloadsDir, withIntermediateDirectories: true)
            } catch {
                task.status = .failed
                tasks[id] = task
                persist()
                DispatchQueue.main.async { self.onStatusChanged?(task) }
                return
            }
            
            var fileName = task.fileName
            if fileName.isEmpty { fileName = "download_\(Int(Date().timeIntervalSince1970))" }
            // 清理文件名中的非法字符
            fileName = fileName.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined(separator: "_")
            var destURL = downloadsDir.appendingPathComponent(fileName)
            // 避免重名
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
            
            // 先尝试移动，失败则尝试复制
            var fileSaved = false
            do {
                try fileManager.moveItem(at: location, to: destURL)
                fileSaved = true
            } catch {
                do {
                    try fileManager.copyItem(at: location, to: destURL)
                    fileSaved = true
                } catch {
                    fileSaved = false
                }
            }
            
            if fileSaved {
                task.localPath = destURL.path
                task.fileName = destURL.lastPathComponent
                task.status = .completed
                task.finishTime = Date()
                // 更新实际文件大小
                if let attrs = try? fileManager.attributesOfItem(atPath: destURL.path),
                   let size = attrs[.size] as? Int64 {
                    task.fileSize = size
                }
                tasks[id] = task
                persist()
                DispatchQueue.main.async {
                    self.onProgress?(task)
                    self.onStatusChanged?(task)
                    self.onCompleted?(task)
                }
            } else {
                task.status = .failed
                tasks[id] = task
                persist()
                print("[Download] 文件保存失败: \(fileName), 临时文件: \(location.path)")
                DispatchQueue.main.async { self.onStatusChanged?(task) }
            }
        }
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        taskQueue.sync {
            guard var task = tasks[id] else { return }
            task.downloadedSize = totalBytesWritten
            if totalBytesExpectedToWrite > 0 {
                task.fileSize = totalBytesExpectedToWrite
            }
            tasks[id] = task
            DispatchQueue.main.async { self.onProgress?(task) }
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription, error != nil else { return }
        taskQueue.sync {
            guard var dtask = tasks[id], dtask.status == .downloading else { return }
            dtask.status = .failed
            tasks[id] = dtask
            persist()
            DispatchQueue.main.async { self.onStatusChanged?(dtask) }
        }
    }
    // MARK: - WKDownload 支持
    func startWKDownload(download: WKDownload, url: String, fileName: String, fileSize: Int64, mimeType: String) {
        let id = UUID().uuidString
        taskQueue.sync {
            var task = DownloadTask(
                id: id,
                url: url,
                fileName: fileName,
                fileSize: fileSize > 0 ? fileSize : 0,
                downloadedSize: 0,
                status: .downloading,
                startTime: Date(),
                finishTime: nil,
                localPath: nil,
                mimeType: mimeType
            )
            tasks[id] = task
            wkDownloads[id] = download
            persist()
            DispatchQueue.main.async {
                self.onStatusChanged?(task)
            }
        }
        // KVO观察下载进度
        let observation = download.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self = self else { return }
            self.taskQueue.sync {
                guard var task = self.tasks[id] else { return }
                task.downloadedSize = Int64(Double(task.fileSize) * progress.fractionCompleted)
                self.tasks[id] = task
                DispatchQueue.main.async {
                    self.onProgress?(task)
                }
            }
        }
        taskQueue.sync {
            wkProgressObservers[id] = observation
        }
    }
    
    func completeWKDownload(download: WKDownload) {
        taskQueue.sync {
            // 找到对应的任务
            guard let id = wkDownloads.first(where: { $0.value === download })?.key else { return }
            guard var task = tasks[id] else { return }
            // 移除KVO观察
            wkProgressObservers[id]?.invalidate()
            wkProgressObservers.removeValue(forKey: id)
            wkDownloads.removeValue(forKey: id)
            // 更新任务状态
            task.status = .completed
            task.finishTime = Date()
            task.downloadedSize = task.fileSize
            // 获取保存路径
            if let destURL = download.fileURL {
                task.localPath = destURL.path
                // 更新实际文件大小
                if let attrs = try? FileManager.default.attributesOfItem(atPath: destURL.path),
                   let size = attrs[.size] as? Int64 {
                    task.fileSize = size
                    task.downloadedSize = size
                }
            }
            tasks[id] = task
            persist()
            DispatchQueue.main.async {
                self.onProgress?(task)
                self.onStatusChanged?(task)
                self.onCompleted?(task)
            }
        }
    }
    
    func failWKDownload(download: WKDownload, error: Error) {
        taskQueue.sync {
            guard let id = wkDownloads.first(where: { $0.value === download })?.key else { return }
            guard var task = tasks[id] else { return }
            // 移除KVO观察
            wkProgressObservers[id]?.invalidate()
            wkProgressObservers.removeValue(forKey: id)
            wkDownloads.removeValue(forKey: id)
            // 更新任务状态
            task.status = .failed
            tasks[id] = task
            persist()
            DispatchQueue.main.async {
                self.onStatusChanged?(task)
            }

        }
    }
}

// MARK: - 格式化工具
extension DownloadTask {
    var sizeText: String {
        let bytes = fileSize > 0 ? fileSize : downloadedSize
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
    var downloadedText: String {
        return ByteCountFormatter.string(fromByteCount: downloadedSize, countStyle: .file)
    }
    var timeText: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "MM-dd HH:mm"
        return fmt.string(from: finishTime ?? startTime)
    }
}
