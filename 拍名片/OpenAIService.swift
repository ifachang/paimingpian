import Foundation

enum OpenAIServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "尚未填入 OpenAI API Key。"
        case .invalidResponse:
            return "OpenAI 回傳格式無法解析。"
        case .serverError(let message):
            return message
        }
    }
}

final class OpenAIService {
    func parseBusinessCard(lines: [OCRTextLine], fallback: ScannedCard, apiKey: String) async throws -> ScannedCard {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        let parsedCard = try await sendRequest(lines: lines, fallback: fallback, apiKey: trimmedKey)
        return parsedCard.toScannedCard(fallback: fallback)
    }

    func generateOutreachSuggestions(card: ScannedCard, context: String, apiKey: String) async throws -> [OutreachSuggestion] {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw OpenAIServiceError.missingAPIKey
        }

        let parsed = try await sendOutreachRequest(card: card, context: context, apiKey: trimmedKey)
        return parsed.suggestions
    }

    private func sendRequest(lines: [OCRTextLine], fallback: ScannedCard, apiKey: String) async throws -> OpenAIParsedCard {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIResponseRequest(
            model: "gpt-5-mini-2025-08-07",
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

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data)
            throw OpenAIServiceError.serverError(apiError?.error.message ?? "OpenAI API 呼叫失敗。")
        }

        let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        let jsonText = decoded.outputText ?? decoded.outputMessageText

        guard let jsonText,
              let jsonData = jsonText.data(using: .utf8)
        else {
            throw OpenAIServiceError.invalidResponse
        }

        return try JSONDecoder().decode(OpenAIParsedCard.self, from: jsonData)
    }

    private func sendOutreachRequest(card: ScannedCard, context: String, apiKey: String) async throws -> OutreachSuggestionsEnvelope {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let payload = OpenAIResponseRequest(
            model: "gpt-5-mini-2025-08-07",
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

        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIServiceError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            let apiError = try? JSONDecoder().decode(OpenAIAPIErrorEnvelope.self, from: data)
            throw OpenAIServiceError.serverError(apiError?.error.message ?? "OpenAI API 呼叫失敗。")
        }

        let decoded = try JSONDecoder().decode(OpenAIResponseEnvelope.self, from: data)
        let jsonText = decoded.outputText ?? decoded.outputMessageText

        guard let jsonText,
              let jsonData = jsonText.data(using: .utf8)
        else {
            throw OpenAIServiceError.invalidResponse
        }

        return try JSONDecoder().decode(OutreachSuggestionsEnvelope.self, from: jsonData)
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

    private func escapeForJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
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

    private func resolved(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private func resolved(_ values: [OpenAIParsedValue], fallback: [LabeledValue]) -> [LabeledValue] {
        let mapped = values.compactMap(\.toLabeledValue)
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
            "required": .array([
                .string("suggestions")
            ])
        ])
    }
}

private struct OpenAIParsedValue: Decodable {
    let label: String
    let value: String

    var toLabeledValue: LabeledValue? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return LabeledValue(kind: mapKind(label), value: trimmed)
    }

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

    private func mapKind(_ label: String) -> LabeledValue.Kind {
        switch label.lowercased() {
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

private enum JSONValue: Encodable {
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
        case .object(let value):
            var container = encoder.container(keyedBy: JSONCodingKey.self)
            for (key, nestedValue) in value {
                try container.encode(nestedValue, forKey: JSONCodingKey(stringValue: key)!)
            }
        case .array(let value):
            var container = encoder.unkeyedContainer()
            for nestedValue in value {
                try container.encode(nestedValue)
            }
        }
    }
}

private struct JSONCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}
