import Contacts

enum ContactStoreServiceError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "目前無法新增聯絡人，請到系統設定允許聯絡人權限。"
        }
    }
}

struct SearchableContact: Identifiable, Equatable {
    let id: String
    let name: String
    let company: String
    let email: String
    let jobTitle: String

    var displayCompany: String {
        company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未提供公司" : company
    }
}

final class ContactStoreService {
    private let store = CNContactStore()

    func save(card: ScannedCard) async throws {
        let granted = try await requestAccess()
        guard granted else {
            throw ContactStoreServiceError.accessDenied
        }

        var normalizedCard = card
        normalizedCard.normalized()

        let contact = CNMutableContact()
        contact.givenName = normalizedCard.givenName
        contact.familyName = normalizedCard.familyName
        contact.organizationName = normalizedCard.company
        contact.jobTitle = normalizedCard.jobTitle

        contact.phoneNumbers = normalizedCard.phoneNumbers.map {
            CNLabeledValue(
                label: contactLabel(for: $0.kind, isEmail: false),
                value: CNPhoneNumber(stringValue: $0.value)
            )
        }

        contact.emailAddresses = normalizedCard.emails.map {
            CNLabeledValue(
                label: contactLabel(for: $0.kind, isEmail: true),
                value: NSString(string: $0.value)
            )
        }

        if !normalizedCard.address.isEmpty {
            let address = CNMutablePostalAddress()
            address.street = normalizedCard.address
            contact.postalAddresses = [CNLabeledValue(
                label: CNLabelWork,
                value: address.copy() as! CNPostalAddress
            )]
        }

        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
    }

    func fetchSearchableContacts() async throws -> [SearchableContact] {
        let granted = try await requestAccess()
        guard granted else {
            throw ContactStoreServiceError.accessDenied
        }

        let keys: [CNKeyDescriptor] = [
            CNContactIdentifierKey as CNKeyDescriptor,
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactJobTitleKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
        ]

        let request = CNContactFetchRequest(keysToFetch: keys)
        request.unifyResults = true

        var contacts: [SearchableContact] = []

        try store.enumerateContacts(with: request) { contact, _ in
            let fullName = [contact.familyName, contact.givenName]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined()
            let fallbackName = [contact.givenName, contact.familyName]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: " ")
            let resolvedName = (fullName.isEmpty ? fallbackName : fullName)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let primaryEmail = contact.emailAddresses.first?.value as String? ?? ""

            let item = SearchableContact(
                id: contact.identifier,
                name: resolvedName.isEmpty ? "未命名聯絡人" : resolvedName,
                company: contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines),
                email: primaryEmail.trimmingCharacters(in: .whitespacesAndNewlines),
                jobTitle: contact.jobTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            contacts.append(item)
        }

        return contacts
    }

    private func requestAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestAccess(for: .contacts) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    private func contactLabel(for kind: LabeledValue.Kind, isEmail: Bool) -> String {
        switch kind {
        case .mobile:
            return isEmail ? CNLabelWork : CNLabelPhoneNumberMobile
        case .work:
            return CNLabelWork
        case .fax:
            return CNLabelPhoneNumberOtherFax
        case .home:
            return isEmail ? CNLabelHome : CNLabelHome
        case .other:
            return CNLabelOther
        }
    }
}
