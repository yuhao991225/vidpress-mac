import Foundation

struct BinaryLookupStatus {
    let ffmpegURL: URL?
    let ffprobeURL: URL?

    var isReady: Bool {
        ffmpegURL != nil && ffprobeURL != nil
    }

    var summary: String {
        switch (ffmpegURL, ffprobeURL) {
        case (.some(let ffmpeg), .some(let ffprobe)):
            if ffmpeg.path.contains(".app/Contents/Resources") && ffprobe.path.contains(".app/Contents/Resources") {
                return "内置 FFmpeg 已就绪"
            }
            return "FFmpeg 已就绪"
        case (.none, .some):
            return "缺少 FFmpeg"
        case (.some, .none):
            return "缺少 FFprobe"
        case (.none, .none):
            return "未找到 FFmpeg"
        }
    }
}

final class FFmpegLocator {
    func status() -> BinaryLookupStatus {
        BinaryLookupStatus(
            ffmpegURL: locateExecutable(named: "ffmpeg", envKeys: ["VIDPRESS_FFMPEG_PATH", "FFMPEG_PATH"]),
            ffprobeURL: locateExecutable(named: "ffprobe", envKeys: ["VIDPRESS_FFPROBE_PATH", "FFPROBE_PATH"])
        )
    }

    func requireFFmpeg() throws -> URL {
        if let url = status().ffmpegURL {
            return url
        }
        throw VidPressError("未找到 FFmpeg。请先运行 npm run bootstrap:cn，或设置 VIDPRESS_FFMPEG_PATH。")
    }

    func requireFFprobe() throws -> URL {
        if let url = status().ffprobeURL {
            return url
        }
        throw VidPressError("未找到 FFprobe。请先运行 npm run bootstrap:cn，或设置 VIDPRESS_FFPROBE_PATH。")
    }

    private func locateExecutable(named name: String, envKeys: [String]) -> URL? {
        let environment = ProcessInfo.processInfo.environment

        for key in envKeys {
            if let path = environment[key], !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                if isExecutable(url) {
                    return url
                }
            }
        }

        for url in bundledCandidates(named: name) + repositoryCandidates(named: name) + systemCandidates(named: name) {
            if isExecutable(url) {
                return url
            }
        }

        return nil
    }

    private func bundledCandidates(named name: String) -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(name))
        }

        if let executableURL = Bundle.main.executableURL {
            let contents = executableURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            candidates.append(contents.appendingPathComponent("Resources/\(name)"))
        }

        return candidates
    }

    private func repositoryCandidates(named name: String) -> [URL] {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        switch name {
        case "ffmpeg":
            return [
                currentDirectory.appendingPathComponent("node_modules/ffmpeg-static/ffmpeg")
            ]
        case "ffprobe":
            return [
                currentDirectory.appendingPathComponent("node_modules/ffprobe-static/bin/darwin/arm64/ffprobe"),
                currentDirectory.appendingPathComponent("node_modules/ffprobe-static/bin/darwin/x64/ffprobe")
            ]
        default:
            return []
        }
    }

    private func systemCandidates(named name: String) -> [URL] {
        [
            URL(fileURLWithPath: "/opt/homebrew/bin/\(name)"),
            URL(fileURLWithPath: "/usr/local/bin/\(name)"),
            URL(fileURLWithPath: "/usr/bin/\(name)")
        ]
    }

    private func isExecutable(_ url: URL) -> Bool {
        FileManager.default.isExecutableFile(atPath: url.path)
    }
}
