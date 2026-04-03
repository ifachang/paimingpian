import Foundation

enum OpenAIServiceError: LocalizedError {
    case missingProxyURL
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingProxyURL:
            return "AI 服務尚未完成設定。"
        case .invalidResponse:
            return "AI 回傳格式無法解析。"
        case .serverError(let message):
            return message
        }
    }
}

final class OpenAIService {
    func parseBusinessCard(lines: [OCRTextLine], fallback: ScannedCard) async throws -> ScannedCard {
        let proxyURL = resolvedProxyURL()
        guard !proxyURL.isEmpty else {
            throw OpenAIServiceError.missingProxyURL
        }

        let payload = OpenAIResponseRequest(
            model: AppSecrets.openAIModel,
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: systemPrompt)]),
                .init(role: "user", content: [.init(type: "input_text", text: buildUserPrompt(lines: lines, fallback: fallback))])
            ],
            text: .init(
                format: .init(
                    type: "json_schema",
                    name: "business_card_fields",
                    strict: true,
                    schema: OpenAIParsedCard.jsonSchema
                )
            )
        )

        let decoded = try await sendResponsesRequest(payload, proxyURL: proxyURL)
        guard let jsonText = decoded.outputText ?? decoded.outputMessageText else {
            throw OpenAIServiceError.invalidResponse
        }

        return try decodeJSONPayload(OpenAIParsedCard.self, from: jsonText).toScannedCard(fallback: fallback)
    }

    func generateOutreachSuggestions(card: ScannedCard, context: String) async throws -> [OutreachSuggestion] {
        let proxyURL = resolvedProxyURL()
        guard !proxyURL.isEmpty else {
            throw OpenAIServiceError.missingProxyURL
        }

        let payload = OpenAIResponseRequest(
            model: AppSecrets.openAIModel,
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: outreachSystemPrompt)]),
                .init(role: "user", content: [.init(type: "input_text", text: buildOutreachPrompt(card: card, context: context))])
            ],
            text: .init(
                format: .init(
                    type: "json_schema",
                    name: "outreach_suggestions",
                    strict: true,
                    schema: OutreachSuggestionsEnvelope.jsonSchema
                )
            )
        )

        let decoded = try await sendResponsesRequest(payload, proxyURL: proxyURL)
        guard let jsonText = decoded.outputText ?? decoded.outputMessageText else {
            throw OpenAIServiceError.invalidResponse
        }

        return try decodeJSONPayload(OutreachSuggestionsEnvelope.self, from: jsonText).suggestions
    }

    func analyzeRelationshipValue(card: ScannedCard, goal: String, context: String) async throws -> RelationshipValueAnalysis {
        let proxyURL = resolvedProxyURL()
        guard !proxyURL.isEmpty else {
            throw OpenAIServiceError.missingProxyURL
        }

        let payload = OpenAIResponseRequest(
            model: AppSecrets.openAIModel,
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: relationshipAnalysisSystemPrompt)]),
                .init(role: "user", content: [.init(type: "input_text", text: buildRelationshipAnalysisPrompt(card: card, goal: goal, context: context))])
            ],
            text: .init(
                format: .init(
                    type: "json_schema",
                    name: "relationship_value_analysis",
                    strict: true,
                    schema: RelationshipValueAnalysis.jsonSchema
                )
            )
        )

        let decoded = try await sendResponsesRequest(payload, proxyURL: proxyURL)
        guard let jsonText = decoded.outputText ?? decoded.outputMessageText else {
            throw OpenAIServiceError.invalidResponse
        }

        return try decodeJSONPayload(RelationshipValueAnalysis.self, from: jsonText)
    }

    func rerankContactsForPeopleSearch(query: String, candidates: [SearchableContact]) async throws -> [PeopleSearchRecommendation] {
        let proxyURL = resolvedProxyURL()
        guard !proxyURL.isEmpty else {
            throw OpenAIServiceError.missingProxyURL
        }

        let payload = OpenAIResponseRequest(
            model: AppSecrets.openAIModel,
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: peopleSearchSystemPrompt)]),
                .init(role: "user", content: [.init(type: "input_text", text: buildPeopleSearchPrompt(query: query, candidates: candidates))])
            ],
            text: .init(
                format: .init(
                    type: "json_schema",
                    name: "people_search_recommendations",
                    strict: true,
                    schema: PeopleSearchRecommendationsEnvelope.jsonSchema
                )
            )
        )

        let decoded = try await sendResponsesRequest(payload, proxyURL: proxyURL)
        guard let jsonText = decoded.outputText ?? decoded.outputMessageText else {
            throw OpenAIServiceError.invalidResponse
        }

        return try decodeJSONPayload(PeopleSearchRecommendationsEnvelope.self, from: jsonText).recommendations
    }

    private func sendResponsesRequest(_ payload: OpenAIResponseRequest, proxyURL: String) async throws -> OpenAIResponseEnvelope {
        guard let url = URL(string: proxyURL) else {
            throw OpenAIServiceError.missingProxyURL
        }

        var request = URLRequest(url: url)
        let installationID = InstallationIDStore.shared.load()
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(payload.text.format.name, forHTTPHeaderField: "X-AI-Feature")
        request.setValue("ios", forHTTPHeaderField: "X-Client-Platform")
        if !installationID.isEmpty {
            request.setValue(installationID, forHTTPHeaderField: "X-Installation-ID")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }

        if let assignedInstallationID = httpResponse.value(forHTTPHeaderField: "X-Installation-ID") {
            InstallationIDStore.shared.save(assignedInstallationID)
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data)
            throw OpenAIServiceError.serverError(apiError?.error.message ?? "AI 呼叫失敗。")
        }

        return try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
    }

    private func resolvedProxyURL() -> String {
        AppSecrets.aiProxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var systemPrompt: String {
        """
        You extract structured contact data from OCR text lines of a business card.
        Use OCR line text, layout positions, and the fallback heuristic result.
        Return JSON only.
        Preserve multiple phone numbers and multiple email addresses when present.
        For phones and emails, use labels such as mobile, work, fax, home, or other.
        Leave unknown fields as empty strings or empty arrays.
        """
    }

    private var outreachSystemPrompt: String {
        """
        You write concise first-contact outreach messages based on a business card.
        Return exactly three suggestions in Traditional Chinese:
        1. email
        2. short_message
        3. partnership
        Keep each suggestion practical and ready to send.
        """
    }

    private var relationshipAnalysisSystemPrompt: String {
        """
        You analyze the relationship value and follow-up strategy for a newly scanned business card.
        Return JSON only in Traditional Chinese.
        Be helpful, practical, and avoid sounding manipulative.
        Base the analysis only on the provided card details and user goal/context.
        If information is limited, explicitly say the confidence is limited.
        """
    }

    private var peopleSearchSystemPrompt: String {
        """
        你是一個人脈助手。
        請根據使用者需求，從候選聯絡人中選出最相關的 3 位。
        回傳內容必須是繁體中文 JSON。
        每位推薦都要包含簡短理由，理由要具體、可信，不要誇大。
        若資訊不足，也要誠實說明是根據公司、職稱或 email 網域推測。
        """
    }

    private func buildUserPrompt(lines: [OCRTextLine], fallback: ScannedCard) -> String {
        let lineDescriptions = lines.enumerated().map { index, line in
            let box = line.boundingBox
            return """
            \(index + 1). text: \(line.text)
               x: \(String(format: "%.3f", box.minX)), y: \(String(format: "%.3f", box.minY)), width: \(String(format: "%.3f", box.width)), height: \(String(format: "%.3f", box.height))
            """
        }.joined(separator: "\n")

        let fallbackPhones = fallback.phoneNumbers
            .map { #"{"label":"\#($0.kind.rawValue)","value":"\#(escapeForJSON($0.value))"}"# }
            .joined(separator: ",")

        let fallbackEmails = fallback.emails
            .map { #"{"label":"\#($0.kind.rawValue)","value":"\#(escapeForJSON($0.value))"}"# }
            .joined(separator: ",")

        return """
        OCR lines:
        \(lineDescriptions)

        Fallback heuristic result:
        {
          "given_name": "\(escapeForJSON(fallback.givenName))",
          "family_name": "\(escapeForJSON(fallback.familyName))",
          "company": "\(escapeForJSON(fallback.company))",
          "job_title": "\(escapeForJSON(fallback.jobTitle))",
          "phone_numbers": [\(fallbackPhones)],
          "emails": [\(fallbackEmails)],
          "address": "\(escapeForJSON(fallback.address))"
        }
        """
    }

    private func buildOutreachPrompt(card: ScannedCard, context: String) -> String {
        let phones = card.phoneNumbers
            .map { "\($0.kind.rawValue): \($0.value)" }
            .joined(separator: ", ")
        let emails = card.emails
            .map { "\($0.kind.rawValue): \($0.value)" }
            .joined(separator: ", ")

        return """
        Contact info:
        - name: \(card.displayName)
        - company: \(card.company)
        - job_title: \(card.jobTitle)
        - phones: \(phones)
        - emails: \(emails)
        - address: \(card.address)

        User context:
        \(context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none provided" : context)
        """
    }

    private func buildRelationshipAnalysisPrompt(card: ScannedCard, goal: String, context: String) -> String {
        let phones = card.phoneNumbers
            .map { "\($0.kind.rawValue): \($0.value)" }
            .joined(separator: ", ")
        let emails = card.emails
            .map { "\($0.kind.rawValue): \($0.value)" }
            .joined(separator: ", ")

        return """
        Contact info:
        - name: \(card.displayName)
        - company: \(card.company)
        - job_title: \(card.jobTitle)
        - phones: \(phones)
        - emails: \(emails)
        - address: \(card.address)

        User goal:
        \(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "general networking" : goal)

        Extra context:
        \(context.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "none provided" : context)

        Return:
        - a short summary of who this person likely is
        - relationship priority: high, medium, or low
        - why this contact may be valuable
        - possible collaboration opportunities
        - practical next action
        - one caution or missing-information note
        """
    }

    private func buildPeopleSearchPrompt(query: String, candidates: [SearchableContact]) -> String {
        let candidateLines = candidates.enumerated().map { index, contact in
            """
            \(index + 1). id: \(contact.id)
               name: \(contact.name)
               company: \(contact.company)
               job_title: \(contact.jobTitle)
               email: \(contact.email)
            """
        }.joined(separator: "\n")

        return """
        使用者需求：
        \(query)

        以下是候選聯絡人：
        \(candidateLines)

        請選出最相關的 3 位，並為每位提供一句繁體中文推薦理由。
        """
    }

    private func escapeForJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func decodeJSONPayload<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let data = text.data(using: .utf8) else {
            throw OpenAIServiceError.invalidResponse
        }

        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct OpenAIResponseRequest: Encodable {
    let model: String
    let input: [InputMessage]
    let text: TextConfig

    struct InputMessage: Encodable {
        let role: String
        let content: [InputContent]
    }

    struct InputContent: Encodable {
        let type: String
        let text: String
    }

    struct TextConfig: Encodable {
        let format: Format
    }

    struct Format: Encodable {
        let type: String
        let name: String
        let strict: Bool
        let schema: JSONValue
    }
}

private struct OpenAIResponseEnvelope: Decodable {
    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var outputMessageText: String? {
        output?
            .compactMap { item -> String? in
                guard item.type == "message" else { return nil }
                return item.content?.first(where: { $0.type == "output_text" })?.text
            }
            .first
    }

    struct OutputItem: Decodable {
        let type: String
        let content: [OutputContent]?
    }

    struct OutputContent: Decodable {
        let type: String
        let text: String?
    }
}

private struct OpenAIAPIErrorEnvelope: Decodable {
    let error: OpenAIAPIError

    struct OpenAIAPIError: Decodable {
        let message: String
    }
}

private struct OpenAIParsedCard: Decodable {
    let givenName: String
    let familyName: String
    let company: String
    let jobTitle: String
    let phoneNumbers: [OpenAIParsedValue]
    let emails: [OpenAIParsedValue]
    let address: String

    enum CodingKeys: String, CodingKey {
        case givenName = "given_name"
        case familyName = "family_name"
        case company
        case jobTitle = "job_title"
        case phoneNumbers = "phone_numbers"
        case emails
        case address
    }

    static var jsonSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "given_name": .object(["type": .string("string")]),
                "family_name": .object(["type": .string("string")]),
                "company": .object(["type": .string("string")]),
                "job_title": .object(["type": .string("string")]),
                "phone_numbers": .object([
                    "type": .string("array"),
                    "items": OpenAIParsedValue.schema
                ]),
                "emails": .object([
                    "type": .string("array"),
                    "items": OpenAIParsedValue.schema
                ]),
                "address": .object(["type": .string("string")])
            ]),
            "required": .array([
                .string("given_name"),
                .string("family_name"),
                .string("company"),
                .string("job_title"),
                .string("phone_numbers"),
                .string("emails"),
                .string("address")
            ])
        ])
    }

    func toScannedCard(fallback: ScannedCard) -> ScannedCard {
        var card = ScannedCard(
            givenName: resolved(givenName, fallback: fallback.givenName),
            familyName: resolved(familyName, fallback: fallback.familyName),
            company: resolved(company, fallback: fallback.company),
            jobTitle: resolved(jobTitle, fallback: fallback.jobTitle),
            phoneNumbers: resolved(phoneNumbers, fallback: fallback.phoneNumbers),
            emails: resolved(emails, fallback: fallback.emails),
            address: resolved(address, fallback: fallback.address)
        )
        card.normalized()
        return card
    }

    private func resolved(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func resolved(_ values: [OpenAIParsedValue], fallback: [LabeledValue]) -> [LabeledValue] {
        let mapped = values.compactMap { $0.toLabeledValue() }
        return mapped.isEmpty ? fallback : mapped
    }
}

struct OutreachSuggestion: Decodable, Identifiable, Equatable {
    let type: String
    let title: String
    let message: String

    var id: String { type }
}

private struct OutreachSuggestionsEnvelope: Decodable {
    let suggestions: [OutreachSuggestion]

    static var jsonSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "suggestions": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "type": .object(["type": .string("string")]),
                            "title": .object(["type": .string("string")]),
                            "message": .object(["type": .string("string")])
                        ]),
                        "required": .array([
                            .string("type"),
                            .string("title"),
                            .string("message")
                        ])
                    ])
                ])
            ]),
            "required": .array([.string("suggestions")])
        ])
    }
}

struct RelationshipValueAnalysis: Codable, Equatable {
    let headline: String
    let priority: String
    let summary: String
    let valueReasons: [String]
    let opportunities: [String]
    let nextAction: String
    let caution: String

    enum CodingKeys: String, CodingKey {
        case headline
        case priority
        case summary
        case valueReasons = "value_reasons"
        case opportunities
        case nextAction = "next_action"
        case caution
    }

    static var jsonSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "headline": .object(["type": .string("string")]),
                "priority": .object(["type": .string("string")]),
                "summary": .object(["type": .string("string")]),
                "value_reasons": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "opportunities": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ]),
                "next_action": .object(["type": .string("string")]),
                "caution": .object(["type": .string("string")])
            ]),
            "required": .array([
                .string("headline"),
                .string("priority"),
                .string("summary"),
                .string("value_reasons"),
                .string("opportunities"),
                .string("next_action"),
                .string("caution")
            ])
        ])
    }
}

struct PeopleSearchRecommendation: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let company: String
    let reason: String
}

private struct PeopleSearchRecommendationsEnvelope: Decodable {
    let recommendations: [PeopleSearchRecommendation]

    static var jsonSchema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "recommendations": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "id": .object(["type": .string("string")]),
                            "name": .object(["type": .string("string")]),
                            "company": .object(["type": .string("string")]),
                            "reason": .object(["type": .string("string")]),
                        ]),
                        "required": .array([
                            .string("id"),
                            .string("name"),
                            .string("company"),
                            .string("reason"),
                        ]),
                    ]),
                ]),
            ]),
            "required": .array([.string("recommendations")]),
        ])
    }
}

private struct OpenAIParsedValue: Decodable {
    let label: String
    let value: String

    static var schema: JSONValue {
        .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "label": .object(["type": .string("string")]),
                "value": .object(["type": .string("string")])
            ]),
            "required": .array([
                .string("label"),
                .string("value")
            ])
        ])
    }

    func toLabeledValue() -> LabeledValue? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        return LabeledValue(kind: mapKind(label), value: trimmedValue)
    }

    private func mapKind(_ rawValue: String) -> LabeledValue.Kind {
        switch rawValue.lowercased() {
        case "mobile":
            return .mobile
        case "work":
            return .work
        case "fax":
            return .fax
        case "home":
            return .home
        default:
            return .other
        }
    }
}

enum JSONValue: Encodable {
    case string(String)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])

    func encode(to encoder: Encoder) throws {
        switch self {
        case .string(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .bool(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .object(let dictionary):
            var container = encoder.container(keyedBy: DynamicCodingKey.self)
            for (key, value) in dictionary {
                try container.encode(value, forKey: DynamicCodingKey(stringValue: key)!)
            }
        case .array(let array):
            var container = encoder.unkeyedContainer()
            for value in array {
                try container.encode(value)
            }
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
