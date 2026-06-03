import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: CompressionViewModel

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(viewModel: viewModel)
            Divider()

            HStack(spacing: 0) {
                QueuePanel(viewModel: viewModel)
                    .frame(minWidth: 620)

                Divider()

                SettingsPanel(viewModel: viewModel)
                    .frame(width: 360)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $viewModel.isDropTarget) { providers in
            viewModel.handleDrop(providers)
        }
    }
}

private struct HeaderBar: View {
    @ObservedObject var viewModel: CompressionViewModel

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("VidPress")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.binaryReady ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(viewModel.binaryStatusSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                viewModel.chooseFiles()
            } label: {
                Label("添加", systemImage: "plus")
            }

            Button {
                viewModel.startQueue()
            } label: {
                Label("开始", systemImage: "play.fill")
            }
            .disabled(viewModel.isRunning || viewModel.jobs.isEmpty)
            .keyboardShortcut(.return, modifiers: [.command])

            Button {
                viewModel.cancelQueue()
            } label: {
                Label("取消", systemImage: "stop.fill")
            }
            .disabled(!viewModel.isRunning)

            Button {
                viewModel.clearFinished()
            } label: {
                Label("清理", systemImage: "checkmark.circle")
            }
            .disabled(viewModel.jobs.isEmpty || viewModel.isRunning)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct QueuePanel: View {
    @ObservedObject var viewModel: CompressionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("队列")
                    .font(.headline)
                Text("\(viewModel.jobs.count) 个视频")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(viewModel.footerMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ZStack {
                if viewModel.jobs.isEmpty {
                    EmptyQueueView(isTargeted: viewModel.isDropTarget)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(viewModel.jobs) { job in
                                JobRow(
                                    job: job,
                                    retry: { viewModel.retryJob(job.id) },
                                    remove: { viewModel.removeJob(job.id) },
                                    reveal: { viewModel.reveal(job.outputURL) },
                                    exportLog: { viewModel.exportLog(job.id) }
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if viewModel.isDropTarget {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .background(Color.accentColor.opacity(0.08))
                        .allowsHitTesting(false)
                }
            }
        }
        .padding(18)
    }
}

private struct EmptyQueueView: View {
    let isTargeted: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film.stack")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary)
            Text(isTargeted ? "释放以添加视频" : "拖入视频或点击添加")
                .font(.headline)
                .foregroundStyle(isTargeted ? Color.accentColor : Color.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 6]))
        )
    }
}

private struct JobRow: View {
    let job: VideoJob
    let retry: () -> Void
    let remove: () -> Void
    let reveal: () -> Void
    let exportLog: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: job.status.systemImage)
                    .font(.title3)
                    .foregroundStyle(job.status.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 5) {
                    Text(job.sourceName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(job.sourceFolder)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 10) {
                        Text(job.status.title)
                            .foregroundStyle(job.status.color)
                        Text(Formatters.bytes(job.sourceBytes))
                        if let duration = job.duration {
                            Text(Formatters.duration(duration))
                        }
                        if let outputBytes = job.outputBytes {
                            Text(Formatters.bytes(outputBytes))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let summary = job.metadata?.summary {
                        Text(summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 6) {
                        Button(action: reveal) {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.borderless)
                        .help("在访达中显示")
                        .disabled(job.outputURL == nil)

                        Button(action: exportLog) {
                            Image(systemName: "doc.text")
                        }
                        .buttonStyle(.borderless)
                        .help("导出 FFmpeg 日志")
                        .disabled(job.ffmpegLog?.isEmpty ?? true)

                        Button(action: retry) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("重试")
                        .disabled(!job.canRetry)

                        Button(action: remove) {
                            Image(systemName: "xmark.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("移除")
                        .disabled(job.status == .compressing)
                    }

                    Text(job.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 180, alignment: .trailing)
                }
            }

            ProgressView(value: job.progress)
                .opacity(job.status == .compressing || job.status == .finished ? 1 : 0.22)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.12))
        )
    }
}

private struct SettingsPanel: View {
    @ObservedObject var viewModel: CompressionViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GroupBox("导出") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("格式", selection: $viewModel.settings.outputContainer) {
                            ForEach(OutputContainer.allCases) { container in
                                Text(container.title).tag(container)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            viewModel.chooseOutputDirectory()
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text(viewModel.outputDirectoryTitle)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("模式") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("目标体积", isOn: $viewModel.settings.useTargetSizeMode)

                        if viewModel.settings.useTargetSizeMode {
                            NumericField(title: "目标体积", suffix: "MB", value: $viewModel.settings.targetSizeMB)
                        } else {
                            Toggle("专业参数", isOn: $viewModel.settings.useProfessionalMode)

                            if viewModel.settings.useProfessionalMode {
                                ProfessionalSettingsView(settings: $viewModel.settings)
                            } else {
                                Picker("压缩策略", selection: $viewModel.settings.simplePreset) {
                                    ForEach(SimplePreset.allCases) { preset in
                                        Text(preset.title).tag(preset)
                                    }
                                }
                                .pickerStyle(.radioGroup)
                            }
                        }
                    }
                    .padding(.top, 4)
                }

                GroupBox("预设") {
                    CustomPresetsPanel(viewModel: viewModel)
                        .padding(.top, 4)
                }

                GroupBox("队列") {
                    VStack(spacing: 10) {
                        Button {
                            viewModel.startQueue()
                        } label: {
                            Label("开始压缩", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(viewModel.isRunning || viewModel.jobs.isEmpty)

                        Button {
                            viewModel.retryFailedJobs()
                        } label: {
                            Label("重试失败", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(viewModel.isRunning || !viewModel.hasRetryableJobs)

                        Button(role: .destructive) {
                            viewModel.clearAll()
                        } label: {
                            Label("清空队列", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(viewModel.jobs.isEmpty)
                    }
                    .padding(.top, 4)
                }

                GroupBox("历史") {
                    HistoryPanel(viewModel: viewModel)
                        .padding(.top, 4)
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
    }
}

private struct CustomPresetsPanel: View {
    @ObservedObject var viewModel: CompressionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("预设名称", text: $viewModel.presetName)
                    .textFieldStyle(.roundedBorder)

                Button {
                    viewModel.saveCurrentPreset()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("保存当前参数")
                .disabled(viewModel.presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if viewModel.customPresets.isEmpty {
                Text("暂无自定义预设")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.customPresets.prefix(5)) { preset in
                    CustomPresetRow(
                        preset: preset,
                        apply: { viewModel.applyPreset(preset.id) },
                        delete: { viewModel.deletePreset(preset.id) }
                    )
                }
            }
        }
    }
}

private struct CustomPresetRow: View {
    let preset: CustomCompressionPreset
    let apply: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(presetSummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button(action: apply) {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help("应用预设")

            Button(action: delete) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("删除预设")
        }
    }

    private var presetSummary: String {
        let settings = preset.settings
        if settings.useTargetSizeMode {
            return "\(settings.outputContainer.title) · 目标 \(settings.targetSizeMB) MB"
        }

        if settings.useProfessionalMode {
            return "\(settings.outputContainer.title) · 专业参数"
        }

        return "\(settings.outputContainer.title) · \(settings.simplePreset.title)"
    }
}

private struct HistoryPanel: View {
    @ObservedObject var viewModel: CompressionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if viewModel.history.isEmpty {
                Text("暂无导出记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(viewModel.history.prefix(6))) { item in
                    HistoryRow(
                        item: item,
                        reveal: { viewModel.reveal(item.outputURL) },
                        remove: { viewModel.removeHistoryItem(item.id) }
                    )
                }

                Button(role: .destructive) {
                    viewModel.clearHistory()
                } label: {
                    Label("清空历史", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let item: CompressionHistoryItem
    let reveal: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.sourceName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(historyDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 6)

            Button(action: reveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("在访达中显示")

            Button(action: remove) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("移除记录")
        }
    }

    private var historyDetail: String {
        var parts = [
            Formatters.shortDateTime(item.finishedAt),
            Formatters.bytes(item.outputBytes)
        ]

        if let ratio = item.compressionRatioText {
            parts.append(ratio)
        }

        return parts.joined(separator: " · ")
    }
}

private struct ProfessionalSettingsView: View {
    @Binding var settings: CompressionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("视频编码", selection: $settings.videoCodec) {
                ForEach(settings.outputContainer.supportedVideoCodecs) { codec in
                    Text(codec.title).tag(codec)
                }
            }

            Picker("编码速度", selection: $settings.encoderSpeed) {
                ForEach(EncoderSpeed.allCases) { speed in
                    Text(speed.title).tag(speed)
                }
            }
            .disabled(settings.videoCodec == .copy)

            Stepper(value: $settings.crf, in: 0...51) {
                LabeledContent("CRF", value: "\(settings.crf)")
            }
            .disabled(settings.videoCodec == .copy || settings.useVideoBitrate)

            Toggle("指定视频码率", isOn: $settings.useVideoBitrate)
                .disabled(settings.videoCodec == .copy)

            if settings.useVideoBitrate {
                NumericField(title: "视频码率", suffix: "kbps", value: $settings.videoBitrateKbps)
            }

            Divider()

            HStack(spacing: 8) {
                NumericField(title: "宽", suffix: "px", value: $settings.width)
                NumericField(title: "高", suffix: "px", value: $settings.height)
            }
            .disabled(settings.videoCodec == .copy)

            NumericField(title: "帧率", suffix: "fps", value: $settings.fps)
                .disabled(settings.videoCodec == .copy)

            Divider()

            Toggle("移除音频", isOn: $settings.removeAudio)

            Picker("音频编码", selection: $settings.audioCodec) {
                ForEach(settings.outputContainer.supportedAudioCodecs) { codec in
                    Text(codec.title).tag(codec)
                }
            }
            .disabled(settings.removeAudio)

            NumericField(title: "音频码率", suffix: "kbps", value: $settings.audioBitrateKbps)
                .disabled(settings.removeAudio || settings.audioCodec == .copy)
        }
    }
}

private struct NumericField: View {
    let title: String
    let suffix: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 72)
            Text(suffix)
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .leading)
        }
    }
}

private extension CompressionStatus {
    var color: Color {
        switch self {
        case .ready, .queued, .probing: .secondary
        case .compressing: .accentColor
        case .finished: .green
        case .failed: .red
        case .canceled: .orange
        }
    }

    var systemImage: String {
        switch self {
        case .ready: "checkmark.circle"
        case .probing: "waveform"
        case .queued: "clock"
        case .compressing: "arrow.triangle.2.circlepath"
        case .finished: "checkmark.seal.fill"
        case .failed: "xmark.octagon.fill"
        case .canceled: "pause.circle"
        }
    }
}
