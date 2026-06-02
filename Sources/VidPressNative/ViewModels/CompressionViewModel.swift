import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CompressionViewModel: ObservableObject {
    @Published var jobs: [VideoJob] = []
    @Published var settings = CompressionSettings() {
        didSet {
            persistAndNormalizeSettings()
        }
    }
    @Published var isDropTarget = false
    @Published var isRunning = false
    @Published var binaryStatusSummary = ""
    @Published var binaryReady = false
    @Published var footerMessage = "准备就绪"

    private let engine = CompressionEngine()
    private let settingsStore = CompressionSettingsStore()
    private var queueTask: Task<Void, Never>?
    private var isApplyingSettingsNormalization = false

    init() {
        settings = settingsStore.load()
        refreshBinaryStatus()
    }

    var outputDirectoryTitle: String {
        settings.outputDirectory.path
    }

    func refreshBinaryStatus() {
        let status = engine.binaryStatus()
        binaryStatusSummary = status.summary
        binaryReady = status.isReady
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = SupportedFormats.inputExtensions
            .sorted()
            .compactMap { UTType(filenameExtension: $0) }

        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.outputDirectory

        if panel.runModal() == .OK, let url = panel.url {
            settings.outputDirectory = url
        }
    }

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?

                if let data = item as? Data,
                   let string = String(data: data, encoding: .utf8) {
                    url = URL(string: string)
                } else {
                    url = item as? URL
                }

                guard let url else { return }

                Task { @MainActor in
                    self.addFiles([url])
                }
            }
        }

        return accepted
    }

    func addFiles(_ urls: [URL]) {
        let supported = urls
            .map { $0.standardizedFileURL }
            .filter(SupportedFormats.isSupportedInput)

        guard !supported.isEmpty else {
            footerMessage = "未添加：格式暂不支持"
            return
        }

        let existingPaths = Set(jobs.map { $0.sourceURL.path })
        let newURLs = supported.filter { !existingPaths.contains($0.path) }

        guard !newURLs.isEmpty else {
            footerMessage = "队列中已存在这些视频"
            return
        }

        let newJobs = newURLs.map { VideoJob(sourceURL: $0, sourceBytes: Self.fileSize($0)) }
        jobs.append(contentsOf: newJobs)
        footerMessage = "已添加 \(newJobs.count) 个视频"

        let ids = newJobs.map(\.id)
        Task {
            await probeJobs(ids)
        }
    }

    func startQueue() {
        guard !isRunning else { return }
        settings = settings.normalizedForContainer()

        refreshBinaryStatus()
        guard binaryReady else {
            footerMessage = binaryStatusSummary
            return
        }

        let runnableStatuses: Set<CompressionStatus> = [.queued, .ready, .failed, .canceled]
        guard jobs.contains(where: { runnableStatuses.contains($0.status) }) else {
            footerMessage = "没有待压缩的视频"
            return
        }

        queueTask = Task {
            await runQueue()
        }
    }

    func cancelQueue() {
        queueTask?.cancel()
        queueTask = nil
        engine.cancelActiveProcess()
        footerMessage = "正在取消"
    }

    func clearFinished() {
        jobs.removeAll { $0.status == .finished || $0.status == .failed || $0.status == .canceled }
        footerMessage = jobs.isEmpty ? "准备就绪" : "已清理完成项"
    }

    func clearAll() {
        cancelQueue()
        jobs.removeAll()
        footerMessage = "队列已清空"
    }

    func removeJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[index].status != .compressing else {
            footerMessage = "当前任务正在压缩"
            return
        }
        jobs.remove(at: index)
    }

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func probeJobs(_ ids: [UUID]) async {
        for id in ids {
            guard let index = jobs.firstIndex(where: { $0.id == id }) else { continue }
            let sourceURL = jobs[index].sourceURL
            jobs[index].status = .probing
            jobs[index].detail = "读取元数据"

            do {
                let metadata = try await engine.probe(sourceURL)
                guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { continue }
                jobs[currentIndex].duration = metadata.duration
                jobs[currentIndex].sourceBytes = metadata.size ?? jobs[currentIndex].sourceBytes
                jobs[currentIndex].status = .ready
                jobs[currentIndex].detail = metadata.duration.map(Formatters.duration) ?? "就绪"
            } catch {
                guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { continue }
                jobs[currentIndex].status = .ready
                jobs[currentIndex].detail = "元数据读取失败"
            }
        }
    }

    private func runQueue() async {
        isRunning = true
        footerMessage = "开始压缩"

        defer {
            isRunning = false
            queueTask = nil
            refreshBinaryStatus()
        }

        let ids = jobs.map(\.id)

        for id in ids {
            if Task.isCancelled {
                markRemainingAsCanceled()
                footerMessage = "已取消"
                return
            }

            guard let index = jobs.firstIndex(where: { $0.id == id }) else { continue }
            guard jobs[index].status != .finished else { continue }

            await compressJob(id)
        }

        footerMessage = "队列完成"
    }

    private func compressJob(_ id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let sourceURL = jobs[index].sourceURL
        let outputURL = uniqueOutputURL(for: jobs[index])
        let compressionSettings = settings.normalizedForContainer()
        let duration = jobs[index].duration

        jobs[index].status = .compressing
        jobs[index].progress = 0
        jobs[index].outputURL = outputURL
        jobs[index].detail = "启动 FFmpeg"

        do {
            let finishedURL = try await engine.compress(
                input: sourceURL,
                output: outputURL,
                settings: compressionSettings,
                duration: duration
            ) { [weak self] fraction, detail in
                guard let self, let currentIndex = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                self.jobs[currentIndex].progress = fraction
                self.jobs[currentIndex].detail = detail
            }

            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].outputURL = finishedURL
            jobs[currentIndex].outputBytes = Self.fileSize(finishedURL)
            jobs[currentIndex].progress = 1
            jobs[currentIndex].status = .finished
            jobs[currentIndex].detail = jobs[currentIndex].compressionRatioText ?? "已导出"
        } catch is CancellationError {
            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].status = .canceled
            jobs[currentIndex].detail = "已取消"
        } catch {
            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].status = .failed
            jobs[currentIndex].detail = error.localizedDescription
        }
    }

    private func markRemainingAsCanceled() {
        for index in jobs.indices where jobs[index].status == .queued || jobs[index].status == .compressing {
            jobs[index].status = .canceled
            jobs[index].detail = "已取消"
        }
    }

    private func uniqueOutputURL(for job: VideoJob) -> URL {
        let fileManager = FileManager.default
        let sourceName = job.sourceURL.deletingPathExtension().lastPathComponent
        let currentSettings = settings.normalizedForContainer()
        let mode = currentSettings.useProfessionalMode ? "pro" : currentSettings.simplePreset.slug
        let ext = currentSettings.outputContainer.fileExtension
        let baseName = "\(sourceName)-\(mode)"
        var candidate = settings.outputDirectory.appendingPathComponent("\(baseName).\(ext)")
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            candidate = settings.outputDirectory.appendingPathComponent("\(baseName)-\(counter).\(ext)")
            counter += 1
        }

        return candidate
    }

    private func persistAndNormalizeSettings() {
        guard !isApplyingSettingsNormalization else { return }

        let normalized = settings.normalizedForContainer()
        if normalized != settings {
            isApplyingSettingsNormalization = true
            settings = normalized
            isApplyingSettingsNormalization = false
            footerMessage = "已调整为当前格式兼容的参数"
        }

        settingsStore.save(normalized)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }

        return Int64(fileSize)
    }
}
