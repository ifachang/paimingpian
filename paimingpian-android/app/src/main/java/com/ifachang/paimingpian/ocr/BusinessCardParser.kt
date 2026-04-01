package com.ifachang.paimingpian.ocr

import com.ifachang.paimingpian.model.LabeledValue
import com.ifachang.paimingpian.model.ScannedCard

object BusinessCardParser {
    fun parse(lines: List<OcrTextLine>): ScannedCard {
        var card = ScannedCard()
        val rawLines = lines.map { it.text.trim() }.filter { it.isNotBlank() }

        card = card.copy(
            emails = extractEmails(rawLines),
            phoneNumbers = extractPhones(rawLines),
            address = extractAddress(rawLines).orEmpty()
        )

        val nonMetadataLines = rawLines.filterNot { line ->
            card.emails.any { line.contains(it.value, ignoreCase = true) } ||
                card.phoneNumbers.any { line.contains(it.value) } ||
                line == card.address ||
                line.startsWith("www.", ignoreCase = true) ||
                line.contains("http", ignoreCase = true) ||
                looksLikeEmail(line) ||
                isLikelyAddress(line) ||
                isLikelyPhone(line)
        }

        val nameLine = bestNameCandidate(nonMetadataLines)
        if (nameLine != null) {
            card = assignName(nameLine, card)
        }

        val companyLine = bestCompanyCandidate(nonMetadataLines, card.fullName)
        if (companyLine != null) {
            card = card.copy(company = companyLine)
        }

        val titleLine = bestTitleCandidate(nonMetadataLines, listOf(card.fullName, card.company))
        if (titleLine != null) {
            card = card.copy(jobTitle = titleLine)
        }

        return card
    }

    private fun extractPhones(lines: List<String>): List<LabeledValue> {
        val regex = Regex(
            "(?:(?:\\+886|886|0)?(?:\\s|-)?9\\d{2}(?:\\s|-)?\\d{3}(?:\\s|-)?\\d{3}|(?:\\+886|886|0)?(?:2|3|4|5|6|7|8)(?:\\s|-)?\\d{3,4}(?:\\s|-)?\\d{3,4})"
        )

        val seen = linkedSetOf<String>()
        val results = mutableListOf<LabeledValue>()

        lines.forEach { line ->
            val normalized = line.replace("O", "0").replace("o", "0")
            regex.findAll(normalized).forEach { match ->
                val cleaned = cleanupPhone(match.value)
                val digitCount = cleaned.count(Char::isDigit)
                if (digitCount >= 9 && seen.add(cleaned)) {
                    results += LabeledValue(inferPhoneKind(line), cleaned)
                }
            }
        }

        return results
    }

    private fun extractEmails(lines: List<String>): List<LabeledValue> {
        val regex = Regex("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", RegexOption.IGNORE_CASE)
        val seen = linkedSetOf<String>()
        val results = mutableListOf<LabeledValue>()

        lines.forEach { line ->
            regex.findAll(line).forEach { match ->
                val value = match.value.lowercase()
                if (seen.add(value)) {
                    results += LabeledValue(inferEmailKind(line), value)
                }
            }
        }

        return results
    }

    private fun extractAddress(lines: List<String>): String? {
        val candidates = lines.filter(::isLikelyAddress)
        return if (candidates.isEmpty()) null else candidates.joinToString(" ")
    }

    private fun bestNameCandidate(lines: List<String>): String? {
        return lines.maxByOrNull(::scoreName)
    }

    private fun bestCompanyCandidate(lines: List<String>, fullName: String): String? {
        val normalizedName = fullName.replace(" ", "")
        return lines
            .filterNot { it.replace(" ", "") == normalizedName }
            .maxByOrNull(::scoreCompany)
    }

    private fun bestTitleCandidate(lines: List<String>, exclusions: List<String>): String? {
        val excluded = exclusions.map { it.replace(" ", "") }.toSet()
        return lines
            .filterNot { excluded.contains(it.replace(" ", "")) }
            .maxByOrNull(::scoreTitle)
    }

    private fun scoreName(text: String): Double {
        val compact = text.replace(" ", "")
        if (compact.isBlank() || compact.contains("@") || compact.any(Char::isDigit)) return -100.0

        var score = 0.0
        if (compact.length <= 6) score += 3
        if (compact.length <= 12) score += 1
        if (containsCompanyKeyword(text)) score -= 4
        if (containsTitleKeyword(text)) score -= 1.5
        if (isLikelyAddress(text)) score -= 5
        return score
    }

    private fun scoreCompany(text: String): Double {
        var score = 0.0
        if (containsCompanyKeyword(text)) score += 5
        if (containsTitleKeyword(text)) score -= 2
        if (text.any(Char::isDigit)) score -= 2
        if (text.length >= 4) score += 1
        if (isLikelyAddress(text)) score -= 4
        if (looksLikeEmail(text)) score -= 5
        return score
    }

    private fun scoreTitle(text: String): Double {
        var score = 0.0
        if (containsTitleKeyword(text)) score += 5
        if (containsCompanyKeyword(text)) score -= 3
        if (text.any(Char::isDigit)) score -= 3
        if (text.length <= 20) score += 1
        if (isLikelyAddress(text)) score -= 4
        if (looksLikeEmail(text)) score -= 5
        return score
    }

    private fun assignName(text: String, card: ScannedCard): ScannedCard {
        val trimmed = text.trim()
        val compact = trimmed.replace(" ", "")

        return when {
            compact.length <= 4 && compact.none(Char::isDigit) -> {
                card.copy(
                    familyName = compact.take(1),
                    givenName = compact.drop(1)
                )
            }
            trimmed.contains(" ") -> {
                val parts = trimmed.split(" ").filter { it.isNotBlank() }
                card.copy(
                    givenName = parts.dropLast(1).joinToString(" "),
                    familyName = parts.lastOrNull().orEmpty()
                )
            }
            else -> card.copy(givenName = trimmed)
        }
    }

    private fun isLikelyPhone(line: String): Boolean = extractPhones(listOf(line)).isNotEmpty()

    private fun isLikelyAddress(line: String): Boolean {
        if (line.length < 6) return false
        val lower = line.lowercase()
        val keywords = listOf("市", "縣", "區", "路", "街", "段", "巷", "弄", "號", "樓", "室", "台灣", "taiwan", "road", "rd", "street", "st", "district", "city")
        return keywords.any { lower.contains(it) }
    }

    private fun containsCompanyKeyword(line: String): Boolean {
        val lower = line.lowercase()
        val keywords = listOf("公司", "有限公司", "股份", "集團", "studio", "design", "tech", "inc", "corp", "co.", "company", "llc", "ltd")
        return keywords.any { lower.contains(it) }
    }

    private fun containsTitleKeyword(line: String): Boolean {
        val lower = line.lowercase()
        val keywords = listOf("經理", "總監", "業務", "工程師", "設計師", "director", "manager", "engineer", "founder", "ceo", "cto", "pm")
        return keywords.any { lower.contains(it) }
    }

    private fun looksLikeEmail(line: String): Boolean = extractEmails(listOf(line)).isNotEmpty()

    private fun inferPhoneKind(line: String): LabeledValue.Kind {
        val lower = line.lowercase()
        return when {
            lower.contains("fax") || lower.contains("傳真") -> LabeledValue.Kind.FAX
            lower.contains("mobile") || lower.contains("手機") || lower.contains("cell") -> LabeledValue.Kind.MOBILE
            lower.contains("tel") || lower.contains("office") || lower.contains("公司") -> LabeledValue.Kind.WORK
            else -> LabeledValue.Kind.OTHER
        }
    }

    private fun inferEmailKind(line: String): LabeledValue.Kind {
        val lower = line.lowercase()
        return when {
            lower.contains("home") -> LabeledValue.Kind.HOME
            lower.contains("work") || lower.contains("office") || lower.contains("公司") -> LabeledValue.Kind.WORK
            else -> LabeledValue.Kind.OTHER
        }
    }

    private fun cleanupPhone(phone: String): String {
        return phone
            .replace("(", "")
            .replace(")", "")
            .replace("  ", " ")
            .trim()
    }
}
