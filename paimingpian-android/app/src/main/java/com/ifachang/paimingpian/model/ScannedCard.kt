package com.ifachang.paimingpian.model

data class LabeledValue(
    val kind: Kind,
    val value: String
) {
    enum class Kind(val displayName: String) {
        MOBILE("手機"),
        WORK("公司"),
        FAX("傳真"),
        HOME("住家"),
        OTHER("其他")
    }

    val isEmpty: Boolean
        get() = value.isBlank()
}

data class ScannedCard(
    val givenName: String = "",
    val familyName: String = "",
    val company: String = "",
    val jobTitle: String = "",
    val phoneNumbers: List<LabeledValue> = emptyList(),
    val emails: List<LabeledValue> = emptyList(),
    val address: String = ""
) {
    val fullName: String
        get() {
            val compactName = listOf(familyName, givenName).filter { it.isNotBlank() }.joinToString("")
            return compactName.ifBlank {
                listOf(givenName, familyName).filter { it.isNotBlank() }.joinToString(" ")
            }
        }

    val displayName: String
        get() = fullName.ifBlank { "未命名聯絡人" }

    val hasContent: Boolean
        get() = listOf(givenName, familyName, company, jobTitle, address).any { it.isNotBlank() } ||
            phoneNumbers.any { !it.isEmpty } ||
            emails.any { !it.isEmpty }

    fun normalized(): ScannedCard {
        return copy(
            phoneNumbers = phoneNumbers.filterNot { it.isEmpty },
            emails = emails.filterNot { it.isEmpty }
        )
    }
}

object DemoCards {
    val sample = ScannedCard(
        givenName = "Ivan",
        familyName = "Chang",
        company = "WoWo AI Commerce",
        jobTitle = "Founder",
        phoneNumbers = listOf(
            LabeledValue(LabeledValue.Kind.MOBILE, "+886 987 605 116")
        ),
        emails = listOf(
            LabeledValue(LabeledValue.Kind.WORK, "ifa1002@icloud.com")
        ),
        address = "台北市信義區松高路"
    )
}
