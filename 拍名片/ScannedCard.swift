import Foundation

struct LabeledValue: Equatable, Identifiable {
    enum Kind: String, CaseIterable, Codable {
        case mobile
        case work
        case fax
        case home
        case other

        var displayName: String {
            switch self {
            case .mobile:
                return "手機"
            case .work:
                return "公司"
            case .fax:
                return "傳真"
            case .home:
                return "住家"
            case .other:
                return "其他"
            }
        }
    }

    let id: UUID
    var kind: Kind
    var value: String

    init(id: UUID = UUID(), kind: Kind, value: String) {
        self.id = id
        self.kind = kind
        self.value = value
    }

    var isEmpty: Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct ScannedCard: Equatable {
    var givenName = ""
    var familyName = ""
    var company = ""
    var jobTitle = ""
    var phoneNumbers: [LabeledValue] = []
    var emails: [LabeledValue] = []
    var address = ""

    var fullName: String {
        let name = [familyName, givenName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined()

        if !name.isEmpty {
            return name
        }

        return [givenName, familyName]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: " ")
    }

    var displayName: String {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "未命名聯絡人" : name
    }

    var hasContent: Bool {
        ![
            givenName,
            familyName,
            company,
            jobTitle,
            address
        ].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ||
        phoneNumbers.contains(where: { !$0.isEmpty }) ||
        emails.contains(where: { !$0.isEmpty })
    }

    var primaryPhone: String {
        phoneNumbers.first(where: { !$0.isEmpty })?.value ?? ""
    }

    var primaryEmail: String {
        emails.first(where: { !$0.isEmpty })?.value ?? ""
    }

    mutating func normalized() {
        phoneNumbers = phoneNumbers.filter { !$0.isEmpty }
        emails = emails.filter { !$0.isEmpty }
    }
}
