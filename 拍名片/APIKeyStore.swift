import Foundation

final class APIKeyStore {
    static let shared = APIKeyStore()

    private let defaultsKey = "openAIAPIKey"

    private init() {}

    func load() -> String {
        UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    func save(_ value: String) {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedValue.isEmpty {
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return
        }

        UserDefaults.standard.set(trimmedValue, forKey: defaultsKey)
    }
}
