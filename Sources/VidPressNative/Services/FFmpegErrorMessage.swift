import Foundation

enum FFmpegErrorMessage {
    static func explain(_ rawMessage: String, exitCode: Int32? = nil, toolName: String = "FFmpeg") -> String {
        let raw = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = raw.lowercased()
        let fallback = exitCode.map { "\(toolName) 退出码 \($0)" } ?? "\(toolName) 执行失败"

        let readable: String

        if lowercased.contains("permission denied") || lowercased.contains("operation not permitted") {
            readable = "没有权限读取源视频或写入导出目录。"
        } else if lowercased.contains("no such file or directory") {
            readable = "源视频或导出目录不存在，请确认文件没有被移动或删除。"
        } else if lowercased.contains("unknown encoder") || lowercased.contains("encoder not found") {
            readable = "当前 FFmpeg 不支持所选编码器，请换一种视频或音频编码。"
        } else if lowercased.contains("could not write header") ||
                    lowercased.contains("invalid argument") ||
                    lowercased.contains("codec not currently supported in container") ||
                    lowercased.contains("tag") && lowercased.contains("incompatible") {
            readable = "导出格式和编码参数不兼容，请换一个导出格式或编码器。"
        } else if lowercased.contains("moov atom not found") ||
                    lowercased.contains("invalid data found when processing input") {
            readable = "源视频可能损坏，或格式信息不完整，无法正常读取。"
        } else if lowercased.contains("immediate exit requested") {
            readable = "任务已取消。"
        } else if lowercased.contains("cannot allocate memory") ||
                    lowercased.contains("not enough memory") {
            readable = "内存不足，建议降低分辨率、码率或关闭其他大型应用后重试。"
        } else {
            readable = fallback
        }

        guard !raw.isEmpty else {
            return readable
        }

        let tail = raw
            .split(separator: "\n")
            .suffix(4)
            .joined(separator: "\n")

        return "\(readable)\n\(tail)"
    }
}
