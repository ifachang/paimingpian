import Foundation

struct HomeHeroItem: Decodable, Identifiable {
    let imageURL: URL
    let linkURL: URL?

    var id: String { imageURL.absoluteString + "|" + (linkURL?.absoluteString ?? "") }
}

struct HomeHeroConfig: Decodable {
    enum Mode: String, Decodable {
        case single
        case carousel
    }

    let mode: Mode?
    let imageURL: URL?
    let linkURL: URL?
    let images: [HomeHeroItem]?

    var items: [HomeHeroItem] {
        let explicitItems = (images ?? []).filter { !$0.imageURL.absoluteString.isEmpty }
        if !explicitItems.isEmpty {
            return explicitItems
        }

        if let imageURL {
            return [HomeHeroItem(imageURL: imageURL, linkURL: linkURL)]
        }

        return []
    }

    var usesCarousel: Bool {
        (mode ?? .single) == .carousel && items.count > 1
    }
}

final class HomeHeroService {
    static let shared = HomeHeroService()

    private init() {}

    func fetchConfig() async -> HomeHeroConfig? {
        guard let url = URL(string: AppSecrets.homeHeroConfigURL) else {
            return nil
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ..< 300).contains(httpResponse.statusCode)
            else {
                return nil
            }

            let decoder = JSONDecoder()
            return try decoder.decode(HomeHeroConfig.self, from: data)
        } catch {
            return nil
        }
    }
}
