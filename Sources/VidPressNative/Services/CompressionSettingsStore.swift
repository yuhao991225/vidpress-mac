import Foundation

final class CompressionSettingsStore {
    private let key = "com.zypher.vidpress.compression-settings.v1"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func load() -> CompressionSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? decoder.decode(CompressionSettings.self, from: data) else {
            return CompressionSettings().normalizedForContainer()
        }

        return settings.normalizedForContainer()
    }

    func save(_ settings: CompressionSettings) {
        guard let data = try? encoder.encode(settings.normalizedForContainer()) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
