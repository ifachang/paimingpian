import Contacts

enum ContactStoreServiceError: LocalizedError {
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "沒有聯絡人權限，請到系統設定允許存取聯絡人。"
        }
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
