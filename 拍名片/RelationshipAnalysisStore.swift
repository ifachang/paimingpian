import Foundation

struct SavedRelationshipAnalysis: Codable, Equatable, Identifiable {
    let id: UUID
    let createdAt: Date
    let goal: String
    let card: ScannedCard
    let analysis: RelationshipValueAnalysis

    init(
        id: UUID = UUID(),
        createdAt: Date = .now,
        goal: String,
        card: ScannedCard,
        analysis: RelationshipValueAnalysis
    ) {
        self.id = id
        self.createdAt = createdAt
        self.goal = goal
        self.card = card
        self.analysis = analysis
    }
}

final class RelationshipAnalysisStore {
    static let shared = RelationshipAnalysisStore()

    private let defaultsKey = "saved_relationship_analyses"
    private let maxCount = 20

    private init() {}

    func load() -> [SavedRelationshipAnalysis] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([SavedRelationshipAnalysis].self, from: data)
        else {
            return []
        }

        return items.sorted { $0.createdAt > $1.createdAt }
    }

    func save(goal: String, card: ScannedCard, analysis: RelationshipValueAnalysis) -> [SavedRelationshipAnalysis] {
        var items = load()
        let normalizedCard = normalized(card)

        items.removeAll {
            $0.card.displayName == normalizedCard.displayName &&
            $0.card.company == normalizedCard.company &&
            $0.goal == goal
        }

        items.insert(
            SavedRelationshipAnalysis(goal: goal, card: normalizedCard, analysis: analysis),
            at: 0
        )

        let trimmed = Array(items.prefix(maxCount))
        persist(trimmed)
        return trimmed
    }

    private func normalized(_ card: ScannedCard) -> ScannedCard {
        var value = card
        value.normalized()
        return value
    }

    private func persist(_ items: [SavedRelationshipAnalysis]) {
        guard let data = try? JSONEncoder().encode(items) else {
            return
        }

        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
