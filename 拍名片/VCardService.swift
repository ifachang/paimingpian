import Contacts
import CoreImage.CIFilterBuiltins
import UIKit

enum VCardService {
    static func makeVCardString(from card: ScannedCard) throws -> String {
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

        if !normalizedCard.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let address = CNMutablePostalAddress()
            address.street = normalizedCard.address
            contact.postalAddresses = [
                CNLabeledValue(label: CNLabelWork, value: address.copy() as! CNPostalAddress)
            ]
        }

        let data = try CNContactVCardSerialization.data(with: [contact])
        guard let string = String(data: data, encoding: .utf8) else {
            throw VCardServiceError.encodingFailed
        }

        return string
    }

    static func makeQRCode(from text: String, sideLength: CGFloat = 960) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else {
            return nil
        }

        let scaleX = sideLength / outputImage.extent.width
        let scaleY = sideLength / outputImage.extent.height
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        let context = CIContext()

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    static func parseScannedCard(fromVCard text: String) throws -> ScannedCard {
        guard let data = text.data(using: .utf8) else {
            throw VCardServiceError.invalidVCard
        }

        let contacts = try CNContactVCardSerialization.contacts(with: data)
        guard let contact = contacts.first else {
            throw VCardServiceError.invalidVCard
        }

        var card = ScannedCard()
        card.givenName = contact.givenName
        card.familyName = contact.familyName
        card.company = contact.organizationName
        card.jobTitle = contact.jobTitle
        card.phoneNumbers = contact.phoneNumbers.map {
            LabeledValue(kind: labeledValueKind(from: $0.label, isEmail: false), value: $0.value.stringValue)
        }
        card.emails = contact.emailAddresses.map {
            LabeledValue(kind: labeledValueKind(from: $0.label, isEmail: true), value: String($0.value))
        }
        card.address = contact.postalAddresses
            .map { $0.value }
            .map { [$0.street, $0.city, $0.state, $0.postalCode, $0.country].filter { !$0.isEmpty }.joined(separator: " ") }
            .first ?? ""
        card.normalized()
        return card
    }

    private static func contactLabel(for kind: LabeledValue.Kind, isEmail: Bool) -> String {
        switch kind {
        case .mobile:
            return isEmail ? CNLabelWork : CNLabelPhoneNumberMobile
        case .work:
            return CNLabelWork
        case .fax:
            return CNLabelPhoneNumberOtherFax
        case .home:
            return CNLabelHome
        case .other:
            return CNLabelOther
        }
    }

    private static func labeledValueKind(from label: String?, isEmail: Bool) -> LabeledValue.Kind {
        switch label {
        case CNLabelPhoneNumberMobile:
            return .mobile
        case CNLabelWork:
            return .work
        case CNLabelPhoneNumberOtherFax:
            return .fax
        case CNLabelHome:
            return .home
        default:
            return isEmail ? .other : .other
        }
    }
}

enum VCardServiceError: LocalizedError {
    case encodingFailed
    case invalidVCard

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "無法生成電子名片資料。"
        case .invalidVCard:
            return "這個 QR Code 不是可讀取的電子名片格式。"
        }
    }
}
