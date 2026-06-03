import Foundation

final class CompressionWorkStateStore {
    private let queueKey = "com.zypher.vidpress.queue.v1"
    private let historyKey = "com.zypher.vidpress.history.v1"
    private let presetsKey = "com.zypher.vidpress.custom-presets.v1"
    private let historyLimit = 200
    private let presetsLimit = 50
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func loadQueue() -> [VideoJob] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
              let jobs = try? decoder.decode([VideoJob].self, from: data) else {
            return []
        }

        return jobs.map { $0.restoredForLaunch() }
    }

    func saveQueue(_ jobs: [VideoJob]) {
        guard let data = try? encoder.encode(jobs) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }

    func loadHistory() -> [CompressionHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let history = try? decoder.decode([CompressionHistoryItem].self, from: data) else {
            return []
        }

        return history
    }

    func saveHistory(_ history: [CompressionHistoryItem]) {
        let trimmed = Array(history.prefix(historyLimit))
        guard let data = try? encoder.encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    func loadCustomPresets() -> [CustomCompressionPreset] {
        guard let data = UserDefaults.standard.data(forKey: presetsKey),
              let presets = try? decoder.decode([CustomCompressionPreset].self, from: data) else {
            return []
        }

        return presets
    }

    func saveCustomPresets(_ presets: [CustomCompressionPreset]) {
        let trimmed = Array(presets.prefix(presetsLimit))
        guard let data = try? encoder.encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: presetsKey)
    }
}
