import Foundation

enum FFmpegArgumentBuilder {
    static func build(input: URL, output: URL, settings: CompressionSettings) -> [String] {
        let settings = settings.normalizedForContainer()
        var arguments = [
            "-hide_banner",
            "-y",
            "-nostdin",
            "-i", input.path
        ]

        if settings.useProfessionalMode {
            appendProfessionalArguments(&arguments, settings: settings)
        } else {
            appendSimplePresetArguments(&arguments, settings: settings)
        }

        if settings.outputContainer == .mp4 || settings.outputContainer == .mov {
            arguments += ["-movflags", "+faststart"]
        }

        arguments += [
            "-progress", "pipe:1",
            "-stats_period", "0.25",
            "-nostats",
            output.path
        ]

        return arguments
    }

    private static func appendSimplePresetArguments(_ arguments: inout [String], settings: CompressionSettings) {
        let videoCodec = settings.outputContainer.defaultVideoCodec
        let audioCodec = settings.outputContainer.defaultAudioCodec
        let profile = simpleProfile(for: settings.simplePreset)

        arguments += ["-c:v", videoCodec.ffmpegName]
        appendQualityArguments(&arguments, codec: videoCodec, crf: profile.crf, speed: profile.speed)

        if let filter = profile.videoFilter {
            arguments += ["-vf", filter]
        }

        arguments += ["-c:a", audioCodec.ffmpegName]
        arguments += ["-b:a", "\(profile.audioBitrateKbps)k"]
    }

    private static func appendProfessionalArguments(_ arguments: inout [String], settings: CompressionSettings) {
        let videoCodec = settings.videoCodec
        arguments += ["-c:v", videoCodec.ffmpegName]

        if videoCodec != .copy {
            if settings.useVideoBitrate && settings.videoBitrateKbps > 0 {
                arguments += ["-b:v", "\(settings.videoBitrateKbps)k"]
            } else {
                appendQualityArguments(&arguments, codec: videoCodec, crf: settings.crf, speed: settings.encoderSpeed)
            }

            let filters = professionalFilters(settings: settings)
            if !filters.isEmpty {
                arguments += ["-vf", filters.joined(separator: ",")]
            }
        }

        if settings.removeAudio {
            arguments += ["-an"]
        } else {
            arguments += ["-c:a", settings.audioCodec.ffmpegName]
            if settings.audioCodec != .copy {
                arguments += ["-b:a", "\(settings.audioBitrateKbps)k"]
            }
        }
    }

    private static func appendQualityArguments(
        _ arguments: inout [String],
        codec: VideoCodec,
        crf: Int,
        speed: EncoderSpeed
    ) {
        switch codec {
        case .h264, .h265:
            arguments += ["-preset", speed.rawValue, "-crf", "\(crf)"]
        case .vp9:
            arguments += ["-deadline", "good", "-cpu-used", "4", "-row-mt", "1", "-crf", "\(crf)", "-b:v", "0"]
        case .av1:
            arguments += ["-cpu-used", "6", "-crf", "\(crf)"]
        case .mpeg4:
            arguments += ["-q:v", "\(max(1, min(31, crf / 2)))"]
        case .copy:
            break
        }
    }

    private static func simpleProfile(for preset: SimplePreset) -> (crf: Int, speed: EncoderSpeed, audioBitrateKbps: Int, videoFilter: String?) {
        switch preset {
        case .visuallyLossless:
            return (16, .slow, 192, nil)
        case .highQuality:
            return (20, .medium, 160, nil)
        case .balanced:
            return (24, .medium, 128, nil)
        case .smallFile:
            return (30, .slow, 96, "scale='if(gt(iw,1280),1280,iw)':-2")
        case .social:
            return (23, .medium, 128, "scale='if(gt(iw,1920),1920,iw)':-2,fps=30")
        }
    }

    private static func professionalFilters(settings: CompressionSettings) -> [String] {
        var filters: [String] = []

        if settings.width > 0 && settings.height > 0 {
            filters.append("scale=\(settings.width):\(settings.height):force_original_aspect_ratio=decrease")
        } else if settings.width > 0 {
            filters.append("scale=\(settings.width):-2")
        } else if settings.height > 0 {
            filters.append("scale=-2:\(settings.height)")
        }

        if settings.fps > 0 {
            filters.append("fps=\(settings.fps)")
        }

        return filters
    }
}
