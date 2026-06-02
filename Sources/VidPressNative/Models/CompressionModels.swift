import Foundation

enum SupportedFormats {
    static let inputExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "webm", "avi", "wmv", "flv",
        "mpeg", "mpg", "3gp", "ts", "mts", "m2ts"
    ]

    static let outputExtensions: Set<String> = Set(OutputContainer.allCases.map(\.fileExtension))

    static func isSupportedInput(_ url: URL) -> Bool {
        inputExtensions.contains(url.pathExtension.lowercased())
    }
}

enum CompressionStatus: String, Codable, CaseIterable {
    case ready
    case probing
    case queued
    case compressing
    case finished
    case failed
    case canceled

    var title: String {
        switch self {
        case .ready: "就绪"
        case .probing: "读取中"
        case .queued: "排队"
        case .compressing: "压缩中"
        case .finished: "完成"
        case .failed: "失败"
        case .canceled: "已取消"
        }
    }
}

enum VideoCodec: String, CaseIterable, Codable, Identifiable {
    case h264
    case h265
    case vp9
    case av1
    case mpeg4
    case copy

    var id: Self { self }

    var title: String {
        switch self {
        case .h264: "H.264"
        case .h265: "H.265"
        case .vp9: "VP9"
        case .av1: "AV1"
        case .mpeg4: "MPEG-4"
        case .copy: "复制视频"
        }
    }

    var ffmpegName: String {
        switch self {
        case .h264: "libx264"
        case .h265: "libx265"
        case .vp9: "libvpx-vp9"
        case .av1: "libaom-av1"
        case .mpeg4: "mpeg4"
        case .copy: "copy"
        }
    }

    var usesX26xPreset: Bool {
        self == .h264 || self == .h265
    }
}

enum AudioCodec: String, CaseIterable, Codable, Identifiable {
    case aac
    case opus
    case mp3
    case copy

    var id: Self { self }

    var title: String {
        switch self {
        case .aac: "AAC"
        case .opus: "Opus"
        case .mp3: "MP3"
        case .copy: "复制音频"
        }
    }

    var ffmpegName: String {
        switch self {
        case .aac: "aac"
        case .opus: "libopus"
        case .mp3: "libmp3lame"
        case .copy: "copy"
        }
    }
}

enum OutputContainer: String, CaseIterable, Codable, Identifiable {
    case mp4
    case mov
    case mkv
    case webm
    case avi

    var id: Self { self }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { rawValue }

    var defaultVideoCodec: VideoCodec {
        switch self {
        case .webm: .vp9
        default: .h264
        }
    }

    var defaultAudioCodec: AudioCodec {
        switch self {
        case .webm: .opus
        case .avi: .mp3
        default: .aac
        }
    }

    var supportedVideoCodecs: [VideoCodec] {
        switch self {
        case .mp4:
            [.h264, .h265, .av1, .mpeg4, .copy]
        case .mov:
            [.h264, .h265, .mpeg4, .copy]
        case .mkv:
            [.h264, .h265, .vp9, .av1, .mpeg4, .copy]
        case .webm:
            [.vp9, .av1, .copy]
        case .avi:
            [.h264, .mpeg4, .copy]
        }
    }

    var supportedAudioCodecs: [AudioCodec] {
        switch self {
        case .mp4, .mov:
            [.aac, .mp3, .copy]
        case .mkv:
            [.aac, .opus, .mp3, .copy]
        case .webm:
            [.opus, .copy]
        case .avi:
            [.mp3, .copy]
        }
    }
}

enum SimplePreset: String, CaseIterable, Codable, Identifiable {
    case visuallyLossless
    case highQuality
    case balanced
    case smallFile
    case social

    var id: Self { self }

    var title: String {
        switch self {
        case .visuallyLossless: "无损压缩"
        case .highQuality: "高质量"
        case .balanced: "均衡"
        case .smallFile: "小体积"
        case .social: "社交平台"
        }
    }

    var slug: String {
        switch self {
        case .visuallyLossless: "lossless"
        case .highQuality: "hq"
        case .balanced: "balanced"
        case .smallFile: "small"
        case .social: "social"
        }
    }
}

enum EncoderSpeed: String, CaseIterable, Codable, Identifiable {
    case ultrafast
    case superfast
    case veryfast
    case faster
    case fast
    case medium
    case slow
    case slower
    case veryslow

    var id: Self { self }

    var title: String {
        switch self {
        case .ultrafast: "极快"
        case .superfast: "超快"
        case .veryfast: "很快"
        case .faster: "较快"
        case .fast: "快速"
        case .medium: "标准"
        case .slow: "慢"
        case .slower: "更慢"
        case .veryslow: "最慢"
        }
    }
}

struct CompressionSettings: Codable, Equatable {
    var useProfessionalMode = false
    var simplePreset: SimplePreset = .balanced
    var outputContainer: OutputContainer = .mp4
    var outputDirectory: URL = Self.defaultOutputDirectory()

    var videoCodec: VideoCodec = .h264
    var audioCodec: AudioCodec = .aac
    var encoderSpeed: EncoderSpeed = .medium
    var crf: Int = 24
    var useVideoBitrate = false
    var videoBitrateKbps = 2400
    var width = 0
    var height = 0
    var fps = 0
    var audioBitrateKbps = 128
    var removeAudio = false

    static func defaultOutputDirectory() -> URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
        let homeMovies = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        return (movies ?? homeMovies).appendingPathComponent("VidPress")
    }

    func normalizedForContainer() -> CompressionSettings {
        var normalized = self

        if !normalized.outputContainer.supportedVideoCodecs.contains(normalized.videoCodec) {
            normalized.videoCodec = normalized.outputContainer.defaultVideoCodec
        }

        if !normalized.outputContainer.supportedAudioCodecs.contains(normalized.audioCodec) {
            normalized.audioCodec = normalized.outputContainer.defaultAudioCodec
        }

        normalized.crf = min(max(normalized.crf, 0), 51)
        normalized.videoBitrateKbps = max(normalized.videoBitrateKbps, 1)
        normalized.audioBitrateKbps = max(normalized.audioBitrateKbps, 1)
        normalized.width = max(normalized.width, 0)
        normalized.height = max(normalized.height, 0)
        normalized.fps = max(normalized.fps, 0)

        if normalized.videoCodec == .copy {
            normalized.useVideoBitrate = false
            normalized.width = 0
            normalized.height = 0
            normalized.fps = 0
        }

        return normalized
    }
}

struct VideoJob: Identifiable, Equatable {
    let id: UUID
    let sourceURL: URL
    var duration: Double?
    var sourceBytes: Int64?
    var outputURL: URL?
    var outputBytes: Int64?
    var progress: Double
    var status: CompressionStatus
    var detail: String

    init(sourceURL: URL, sourceBytes: Int64? = nil) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.duration = nil
        self.sourceBytes = sourceBytes
        self.outputURL = nil
        self.outputBytes = nil
        self.progress = 0
        self.status = .queued
        self.detail = "等待处理"
    }

    var sourceName: String {
        sourceURL.lastPathComponent
    }

    var sourceFolder: String {
        sourceURL.deletingLastPathComponent().path
    }

    var compressionRatioText: String? {
        guard let sourceBytes, let outputBytes, sourceBytes > 0 else { return nil }
        let saved = max(0, sourceBytes - outputBytes)
        let percent = Double(saved) / Double(sourceBytes) * 100
        return String(format: "节省 %.1f%%", percent)
    }
}

struct VideoMetadata {
    let duration: Double?
    let size: Int64?
}

struct VidPressError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
