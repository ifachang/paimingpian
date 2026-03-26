import Foundation

final class InstallationIDStore {
    static let shared = InstallationIDStore()

    private let defaultsKey = "aiProxyInstallationID"

    private init() {}

    func load() -> String {
        UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func save(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return }
        UserDefaults.standard.set(trimmedValue, forKey: defaultsKey)
    }
}
