import Foundation

enum BusinessCardParser {
    static func parse(lines: [OCRTextLine]) -> ScannedCard {
        var card = ScannedCard()
        let rawLines = lines.map(\.text)
        let fullText = rawLines.joined(separator: "\n")

        card.emails = extractEmails(from: rawLines)
        card.phoneNumbers = extractPhones(from: rawLines)
        card.address = extractAddress(from: lines) ?? ""

        let nonMetadataLines = lines.filter { line in
            let lowercased = line.text.lowercased()
            return !card.emails.contains(where: { line.text.contains($0.value) }) &&
                !card.phoneNumbers.contains(where: { line.text.contains($0.value) }) &&
                line.text != card.address &&
                !lowercased.hasPrefix("www.") &&
                !lowercased.contains("http") &&
                !isLikelyPhone(line.text) &&
                !isLikelyAddress(line.text) &&
                !looksLikeEmail(line.text)
        }

        if let nameLine = bestNameCandidate(from: nonMetadataLines) {
            assignName(from: nameLine.text, to: &card)
        }

        if let companyLine = bestCompanyCandidate(from: nonMetadataLines, excluding: card.fullName) {
            card.company = companyLine.text
        }

        if let titleLine = bestTitleCandidate(from: nonMetadataLines, excluding: [card.fullName, card.company]) {
            card.jobTitle = titleLine.text
        }

        return card
    }

    private static func extractPhones(from lines: [String]) -> [LabeledValue] {
        let pattern = #"(?:(?:\+886|886|0)?(?:\s|-)?9\d{2}(?:\s|-)?\d{3}(?:\s|-)?\d{3}|(?:\+886|886|0)?(?:2|3|4|5|6|7|8)(?:\s|-)?\d{3,4}(?:\s|-)?\d{3,4})"#
        var results: [LabeledValue] = []
        var seen = Set<String>()

        for line in lines {
            let normalized = line
                .replacingOccurrences(of: "O", with: "0")
                .replacingOccurrences(of: "o", with: "0")

            for match in allMatches(in: normalized, pattern: pattern) {
                let cleaned = cleanupPhone(match)
                let digitCount = cleaned.filter(\.isNumber).count
                guard digitCount >= 9, !seen.contains(cleaned) else {
                    continue
                }

                seen.insert(cleaned)
                results.append(LabeledValue(kind: inferPhoneKind(from: line), value: cleaned))
            }
        }

        return results
    }

    private static func extractEmails(from lines: [String]) -> [LabeledValue] {
        let pattern = #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}"#
        var results: [LabeledValue] = []
        var seen = Set<String>()

        for line in lines {
            for match in allMatches(in: line, pattern: pattern) {
                let normalized = match.lowercased()
                guard !seen.contains(normalized) else {
                    continue
                }

                seen.insert(normalized)
                results.append(LabeledValue(kind: inferEmailKind(from: line), value: normalized))
            }
        }

        return results
    }

    private static func extractAddress(from lines: [OCRTextLine]) -> String? {
        let addressLines = lines
            .filter { isLikelyAddress($0.text) }
            .sorted { $0.midY > $1.midY }
            .map(\.text)

        guard !addressLines.isEmpty else {
            return nil
        }

        return addressLines.joined(separator: " ")
    }

    private static func bestNameCandidate(from lines: [OCRTextLine]) -> OCRTextLine? {
        lines.max { scoreName($0) < scoreName($1) }
    }

    private static func bestCompanyCandidate(from lines: [OCRTextLine], excluding fullName: String) -> OCRTextLine? {
        let normalizedName = fullName.replacingOccurrences(of: " ", with: "")
        let candidates = lines.filter {
            !$0.text.replacingOccurrences(of: " ", with: "").elementsEqual(normalizedName)
        }

        return candidates.max { scoreCompany($0) < scoreCompany($1) }
    }

    private static func bestTitleCandidate(from lines: [OCRTextLine], excluding exclusions: [String]) -> OCRTextLine? {
        let excluded = Set(exclusions.map { $0.replacingOccurrences(of: " ", with: "") })
        let candidates = lines.filter { line in
            let normalized = line.text.replacingOccurrences(of: " ", with: "")
            return !excluded.contains(normalized)
        }

        return candidates.max { scoreTitle($0) < scoreTitle($1) }
    }

    private static func scoreName(_ line: OCRTextLine) -> Double {
        let text = line.text
        let compact = text.replacingOccurrences(of: " ", with: "")

        guard !compact.isEmpty, !compact.contains("@"), !compact.contains(where: \.isNumber) else {
            return -100
        }

        var score = 0.0

        if compact.count <= 6 { score += 3 }
        if compact.count <= 12 { score += 1 }
        if line.midY > 0.45 { score += 1.5 }
        if line.boundingBox.height > 0.04 { score += 2 }
        if containsCompanyKeyword(text) { score -= 4 }
        if containsTitleKeyword(text) { score -= 1.5 }
        if isLikelyAddress(text) { score -= 5 }

        return score
    }

    private static func scoreCompany(_ line: OCRTextLine) -> Double {
        let text = line.text
        var score = 0.0

        if containsCompanyKeyword(text) { score += 5 }
        if containsTitleKeyword(text) { score -= 2 }
        if text.contains(where: \.isNumber) { score -= 2 }
        if text.count >= 4 { score += 1 }
        if line.midY > 0.3 { score += 1 }
        if line.boundingBox.height > 0.025 { score += 1 }
        if isLikelyAddress(text) { score -= 4 }
        if looksLikeEmail(text) { score -= 5 }

        return score
    }

    private static func scoreTitle(_ line: OCRTextLine) -> Double {
        let text = line.text
        var score = 0.0

        if containsTitleKeyword(text) { score += 5 }
        if containsCompanyKeyword(text) { score -= 3 }
        if text.contains(where: \.isNumber) { score -= 3 }
        if text.count <= 20 { score += 1 }
        if line.midY > 0.2 && line.midY < 0.8 { score += 1 }
        if isLikelyAddress(text) { score -= 4 }
        if looksLikeEmail(text) { score -= 5 }

        return score
    }

    private static func assignName(from text: String, to card: inout ScannedCard) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let compact = trimmed.replacingOccurrences(of: " ", with: "")

        if compact.count <= 4 && !compact.contains(where: \.isNumber) {
            card.familyName = String(compact.prefix(1))
            card.givenName = String(compact.dropFirst())
            return
        }

        let parts = trimmed.split(separator: " ").map(String.init)
        if parts.count >= 2 {
            card.givenName = parts.dropLast().joined(separator: " ")
            card.familyName = parts.last ?? ""
        } else {
            card.givenName = trimmed
        }
    }

    private static func isLikelyPhone(_ line: String) -> Bool {
        !extractPhones(from: [line]).isEmpty
    }

    private static func isLikelyAddress(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let keywords = ["市", "縣", "區", "路", "街", "段", "巷", "弄", "號", "樓", "室", "台灣", "taiwan", "road", "rd", "street", "st", "district", "city"]

        guard line.count >= 6 else {
            return false
        }

        return keywords.contains { lowercased.contains($0) }
    }

    private static func containsCompanyKeyword(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let keywords = ["公司", "有限公司", "股份", "集團", "studio", "design", "tech", "inc", "corp", "co.", "company", "llc", "ltd"]
        return keywords.contains { lowercased.contains($0) }
    }

    private static func containsTitleKeyword(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let keywords = ["經理", "總監", "業務", "工程師", "設計師", "director", "manager", "engineer", "founder", "ceo", "cto", "pm"]
        return keywords.contains { lowercased.contains($0) }
    }

    private static func looksLikeEmail(_ line: String) -> Bool {
        !extractEmails(from: [line]).isEmpty
    }

    private static func inferPhoneKind(from line: String) -> LabeledValue.Kind {
        let lowercased = line.lowercased()
        if lowercased.contains("fax") || lowercased.contains("傳真") {
            return .fax
        }
        if lowercased.contains("mobile") || lowercased.contains("手機") || lowercased.contains("cell") {
            return .mobile
        }
        if lowercased.contains("tel") || lowercased.contains("office") || lowercased.contains("公司") {
            return .work
        }
        return .other
    }

    private static func inferEmailKind(from line: String) -> LabeledValue.Kind {
        let lowercased = line.lowercased()
        if lowercased.contains("home") {
            return .home
        }
        if lowercased.contains("work") || lowercased.contains("office") || lowercased.contains("公司") {
            return .work
        }
        return .other
    }

    private static func cleanupPhone(_ phone: String) -> String {
        phone
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let matchRange = Range(match.range, in: text)
        else {
            return nil
        }

        return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func allMatches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { match in
            guard let matchRange = Range(match.range, in: text) else {
                return nil
            }
            return String(text[matchRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
