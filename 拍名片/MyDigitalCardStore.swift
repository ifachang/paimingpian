import Foundation

final class MyDigitalCardStore {
    static let shared = MyDigitalCardStore()

    private let defaultsKey = "my_digital_business_card"

    private init() {}

    func load() -> ScannedCard {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let card = try? JSONDecoder().decode(ScannedCard.self, from: data)
        else {
            return ScannedCard()
        }

        return card
    }

    func save(_ card: ScannedCard) {
        guard let data = try? JSONEncoder().encode(card) else {
            return
        }

        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
