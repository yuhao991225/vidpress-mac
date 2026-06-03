import Foundation

enum Formatters {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    static func bytes(_ value: Int64?) -> String {
        guard let value else { return "-" }
        return byteFormatter.string(fromByteCount: value)
    }

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "-" }

        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", min(max(fraction, 0), 1) * 100)
    }

    static func bitRate(_ bitsPerSecond: Int64) -> String {
        guard bitsPerSecond > 0 else { return "-" }
        let kbps = Double(bitsPerSecond) / 1_000
        if kbps >= 1_000 {
            return "\(decimal(kbps / 1_000, maxFractionDigits: 1)) Mbps"
        }
        return "\(decimal(kbps, maxFractionDigits: 0)) kbps"
    }

    static func decimal(_ value: Double, maxFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(maxFractionDigits)f", value)
    }

    static func shortDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
