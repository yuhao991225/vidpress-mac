import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class CompressionViewModel: ObservableObject {
    @Published var jobs: [VideoJob] = []
    @Published var history: [CompressionHistoryItem] = []
    @Published var customPresets: [CustomCompressionPreset] = []
    @Published var presetName = ""
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
    private let workStateStore = CompressionWorkStateStore()
    private let notificationService = NotificationService()
    private var queueTask: Task<Void, Never>?
    private var isApplyingSettingsNormalization = false

    init() {
        settings = settingsStore.load()
        jobs = workStateStore.loadQueue()
        history = workStateStore.loadHistory()
        customPresets = workStateStore.loadCustomPresets()
        refreshBinaryStatus()
        notificationService.requestAuthorization()

        if !jobs.isEmpty {
            footerMessage = "已恢复 \(jobs.count) 个队列任务"
        }
    }

    var outputDirectoryTitle: String {
        settings.outputDirectory.path
    }

    var hasRetryableJobs: Bool {
        jobs.contains(where: \.canRetry)
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
        saveQueueSnapshot()
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

        let runnableStatuses: Set<CompressionStatus> = [.queued, .ready]
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
        saveQueueSnapshot()
        footerMessage = jobs.isEmpty ? "准备就绪" : "已清理完成项"
    }

    func clearAll() {
        cancelQueue()
        jobs.removeAll()
        saveQueueSnapshot()
        footerMessage = "队列已清空"
    }

    func retryJob(_ id: UUID) {
        guard !isRunning else { return }
        resetJobForRetry(id)
        footerMessage = "已加入重试"
        startQueue()
    }

    func retryFailedJobs() {
        guard !isRunning else { return }
        let retryableIDs = jobs.filter(\.canRetry).map(\.id)
        guard !retryableIDs.isEmpty else {
            footerMessage = "没有可重试的任务"
            return
        }

        retryableIDs.forEach(resetJobForRetry)
        footerMessage = "重试 \(retryableIDs.count) 个任务"
        startQueue()
    }

    func removeJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        guard jobs[index].status != .compressing else {
            footerMessage = "当前任务正在压缩"
            return
        }
        jobs.remove(at: index)
        saveQueueSnapshot()
    }

    func reveal(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func clearHistory() {
        history.removeAll()
        workStateStore.saveHistory(history)
        footerMessage = "历史记录已清空"
    }

    func removeHistoryItem(_ id: UUID) {
        history.removeAll { $0.id == id }
        workStateStore.saveHistory(history)
    }

    func exportLog(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }),
              let log = job.ffmpegLog,
              !log.isEmpty else {
            footerMessage = "没有可导出的日志"
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(job.sourceURL.deletingPathExtension().lastPathComponent)-ffmpeg.log"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try log.write(to: url, atomically: true, encoding: .utf8)
                footerMessage = "日志已导出"
            } catch {
                footerMessage = "日志导出失败：\(error.localizedDescription)"
            }
        }
    }

    func saveCurrentPreset() {
        let name = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            footerMessage = "请输入预设名称"
            return
        }

        var presetSettings = settings.normalizedForContainer()
        presetSettings.outputDirectory = CompressionSettings.defaultOutputDirectory()
        customPresets.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        customPresets.insert(CustomCompressionPreset(name: name, settings: presetSettings), at: 0)
        presetName = ""
        workStateStore.saveCustomPresets(customPresets)
        footerMessage = "已保存预设：\(name)"
    }

    func applyPreset(_ id: UUID) {
        guard let preset = customPresets.first(where: { $0.id == id }) else { return }
        var appliedSettings = preset.settings.normalizedForContainer()
        appliedSettings.outputDirectory = settings.outputDirectory
        settings = appliedSettings
        footerMessage = "已应用预设：\(preset.name)"
    }

    func deletePreset(_ id: UUID) {
        guard let preset = customPresets.first(where: { $0.id == id }) else { return }
        customPresets.removeAll { $0.id == id }
        workStateStore.saveCustomPresets(customPresets)
        footerMessage = "已删除预设：\(preset.name)"
    }

    private func probeJobs(_ ids: [UUID]) async {
        for id in ids {
            guard let index = jobs.firstIndex(where: { $0.id == id }) else { continue }
            let sourceURL = jobs[index].sourceURL
            jobs[index].status = .probing
            jobs[index].detail = "读取元数据"
            saveQueueSnapshot()

            do {
                let metadata = try await engine.probe(sourceURL)
                guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { continue }
                jobs[currentIndex].metadata = metadata
                jobs[currentIndex].duration = metadata.duration
                jobs[currentIndex].sourceBytes = metadata.size ?? jobs[currentIndex].sourceBytes
                jobs[currentIndex].status = .ready
                jobs[currentIndex].detail = metadata.summary
                saveQueueSnapshot()
            } catch {
                guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { continue }
                jobs[currentIndex].status = .ready
                jobs[currentIndex].detail = "元数据读取失败"
                saveQueueSnapshot()
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
            saveQueueSnapshot()
        }

        let ids = jobs.map(\.id)
        var processedIDs: [UUID] = []

        for id in ids {
            if Task.isCancelled {
                markRemainingAsCanceled()
                footerMessage = "已取消"
                return
            }

            guard let index = jobs.firstIndex(where: { $0.id == id }) else { continue }
            guard jobs[index].status == .queued || jobs[index].status == .ready else { continue }

            await compressJob(id)
            processedIDs.append(id)
        }

        footerMessage = "队列完成"
        notifyQueueFinished(processedIDs)
    }

    private func compressJob(_ id: UUID) async {
        guard jobs.contains(where: { $0.id == id }) else { return }
        await ensureMetadata(for: id)

        guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
        let sourceURL = jobs[currentIndex].sourceURL
        let outputURL = uniqueOutputURL(for: jobs[currentIndex])
        let duration = jobs[currentIndex].duration

        do {
            let compressionSettings = try settingsForJob(jobs[currentIndex])

            jobs[currentIndex].status = .compressing
            jobs[currentIndex].progress = 0
            jobs[currentIndex].outputURL = outputURL
            jobs[currentIndex].ffmpegLog = nil
            jobs[currentIndex].detail = settings.useTargetSizeMode
                ? "目标 \(settings.targetSizeMB) MB · 视频 \(compressionSettings.videoBitrateKbps) kbps"
                : "启动 FFmpeg"
            saveQueueSnapshot()

            let finishedURL = try await engine.compress(
                input: sourceURL,
                output: outputURL,
                settings: compressionSettings,
                duration: duration
            ) { [weak self] fraction, detail in
                guard let self, let currentIndex = self.jobs.firstIndex(where: { $0.id == id }) else { return }
                self.jobs[currentIndex].progress = fraction
                self.jobs[currentIndex].detail = detail
            } logUpdate: { [weak self] text in
                self?.appendLog(text, to: id)
            }

            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].outputURL = finishedURL
            jobs[currentIndex].outputBytes = Self.fileSize(finishedURL)
            jobs[currentIndex].progress = 1
            jobs[currentIndex].status = .finished
            jobs[currentIndex].detail = finishedDetail(for: jobs[currentIndex])
            recordHistory(for: jobs[currentIndex])
            saveQueueSnapshot()
        } catch is CancellationError {
            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].status = .canceled
            jobs[currentIndex].detail = "已取消"
            saveQueueSnapshot()
        } catch {
            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].status = .failed
            jobs[currentIndex].detail = error.localizedDescription
            saveQueueSnapshot()
        }
    }

    private func markRemainingAsCanceled() {
        for index in jobs.indices where jobs[index].status == .queued || jobs[index].status == .compressing {
            jobs[index].status = .canceled
            jobs[index].detail = "已取消"
        }
        saveQueueSnapshot()
    }

    private func resetJobForRetry(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].canRetry else { return }
        jobs[index].status = .ready
        jobs[index].progress = 0
        jobs[index].outputURL = nil
        jobs[index].outputBytes = nil
        jobs[index].ffmpegLog = nil
        jobs[index].detail = jobs[index].metadata?.summary ?? "等待重试"
        saveQueueSnapshot()
    }

    private func uniqueOutputURL(for job: VideoJob) -> URL {
        let fileManager = FileManager.default
        let sourceName = job.sourceURL.deletingPathExtension().lastPathComponent
        let currentSettings = settings.normalizedForContainer()
        let mode = if currentSettings.useTargetSizeMode {
            "target-\(currentSettings.targetSizeMB)mb"
        } else if currentSettings.useProfessionalMode {
            "pro"
        } else {
            currentSettings.simplePreset.slug
        }
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

    private func ensureMetadata(for id: UUID) async {
        guard let index = jobs.firstIndex(where: { $0.id == id }),
              jobs[index].metadata == nil || jobs[index].duration == nil else {
            return
        }

        let sourceURL = jobs[index].sourceURL
        jobs[index].status = .probing
        jobs[index].detail = "读取元数据"

        do {
            let metadata = try await engine.probe(sourceURL)
            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].metadata = metadata
            jobs[currentIndex].duration = metadata.duration
            jobs[currentIndex].sourceBytes = metadata.size ?? jobs[currentIndex].sourceBytes
            jobs[currentIndex].detail = metadata.summary
            saveQueueSnapshot()
        } catch {
            guard let currentIndex = jobs.firstIndex(where: { $0.id == id }) else { return }
            jobs[currentIndex].detail = "元数据读取失败"
            saveQueueSnapshot()
        }
    }

    private func settingsForJob(_ job: VideoJob) throws -> CompressionSettings {
        var currentSettings = settings.normalizedForContainer()
        guard currentSettings.useTargetSizeMode else {
            return currentSettings
        }

        guard let duration = job.duration, duration > 0 else {
            throw VidPressError("无法读取视频时长，不能按目标体积压缩。")
        }

        let targetBits = Double(currentSettings.targetSizeMB) * 1_024 * 1_024 * 8
        let totalKbps = Int((targetBits * 0.92 / duration / 1_000).rounded(.down))
        let audioKbps = currentSettings.removeAudio ? 0 : max(64, min(currentSettings.audioBitrateKbps, 192))
        let videoKbps = totalKbps - audioKbps

        guard videoKbps >= 120 else {
            throw VidPressError("目标体积太小，无法为这段视频保留足够视频码率。")
        }

        currentSettings.useProfessionalMode = true
        currentSettings.videoCodec = currentSettings.outputContainer.defaultVideoCodec
        currentSettings.audioCodec = currentSettings.outputContainer.defaultAudioCodec
        currentSettings.useVideoBitrate = true
        currentSettings.videoBitrateKbps = videoKbps
        currentSettings.audioBitrateKbps = audioKbps
        currentSettings.encoderSpeed = .medium

        return currentSettings.normalizedForContainer()
    }

    private func finishedDetail(for job: VideoJob) -> String {
        var parts: [String] = []

        if let ratio = job.compressionRatioText {
            parts.append(ratio)
        }

        if settings.useTargetSizeMode, let outputBytes = job.outputBytes {
            let targetBytes = Int64(settings.targetSizeMB) * 1_024 * 1_024
            let deltaMB = Double(outputBytes - targetBytes) / 1_024 / 1_024
            parts.append(String(format: "目标差 %.1f MB", deltaMB))
        }

        return parts.isEmpty ? "已导出" : parts.joined(separator: " · ")
    }

    private func recordHistory(for job: VideoJob) {
        guard let outputURL = job.outputURL else { return }

        history.removeAll {
            $0.sourceURL.path == job.sourceURL.path && $0.outputURL.path == outputURL.path
        }
        history.insert(CompressionHistoryItem(job: job), at: 0)
        workStateStore.saveHistory(history)
    }

    private func saveQueueSnapshot() {
        workStateStore.saveQueue(jobs)
    }

    private func appendLog(_ text: String, to id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let combined = (jobs[index].ffmpegLog ?? "") + text
        jobs[index].ffmpegLog = combined.count > 65_536 ? String(combined.suffix(65_536)) : combined
    }

    private func notifyQueueFinished(_ processedIDs: [UUID]) {
        let processedJobs = jobs.filter { processedIDs.contains($0.id) }
        let failedCount = processedJobs.filter { $0.status == .failed }.count
        notificationService.notifyQueueFinished(total: processedJobs.count, failed: failedCount)
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }

        return Int64(fileSize)
    }
}
