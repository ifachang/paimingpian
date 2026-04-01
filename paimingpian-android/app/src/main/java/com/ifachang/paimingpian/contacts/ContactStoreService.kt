package com.ifachang.paimingpian.contacts

import android.content.ContentProviderOperation
import android.content.Context
import android.provider.ContactsContract
import com.ifachang.paimingpian.model.LabeledValue
import com.ifachang.paimingpian.model.ScannedCard

class ContactStoreService(
    private val context: Context
) {
    fun save(card: ScannedCard): Result<Unit> = runCatching {
        val resolver = context.contentResolver
        val operations = arrayListOf<ContentProviderOperation>()

        operations += ContentProviderOperation.newInsert(ContactsContract.RawContacts.CONTENT_URI)
            .withValue(ContactsContract.RawContacts.ACCOUNT_TYPE, null)
            .withValue(ContactsContract.RawContacts.ACCOUNT_NAME, null)
            .build()

        val fullName = card.fullName.ifBlank { card.displayName }

        operations += ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
            .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
            .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredName.CONTENT_ITEM_TYPE)
            .withValue(ContactsContract.CommonDataKinds.StructuredName.GIVEN_NAME, card.givenName)
            .withValue(ContactsContract.CommonDataKinds.StructuredName.FAMILY_NAME, card.familyName)
            .withValue(ContactsContract.CommonDataKinds.StructuredName.DISPLAY_NAME, fullName)
            .build()

        if (card.company.isNotBlank() || card.jobTitle.isNotBlank()) {
            operations += ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Organization.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.Organization.COMPANY, card.company)
                .withValue(ContactsContract.CommonDataKinds.Organization.TITLE, card.jobTitle)
                .build()
        }

        card.phoneNumbers.filterNot { it.isEmpty }.forEach { phone ->
            operations += ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Phone.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.Phone.NUMBER, phone.value)
                .withValue(ContactsContract.CommonDataKinds.Phone.TYPE, mapPhoneType(phone.kind))
                .build()
        }

        card.emails.filterNot { it.isEmpty }.forEach { email ->
            operations += ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.Email.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.Email.ADDRESS, email.value)
                .withValue(ContactsContract.CommonDataKinds.Email.TYPE, mapEmailType(email.kind))
                .build()
        }

        if (card.address.isNotBlank()) {
            operations += ContentProviderOperation.newInsert(ContactsContract.Data.CONTENT_URI)
                .withValueBackReference(ContactsContract.Data.RAW_CONTACT_ID, 0)
                .withValue(ContactsContract.Data.MIMETYPE, ContactsContract.CommonDataKinds.StructuredPostal.CONTENT_ITEM_TYPE)
                .withValue(ContactsContract.CommonDataKinds.StructuredPostal.FORMATTED_ADDRESS, card.address)
                .withValue(ContactsContract.CommonDataKinds.StructuredPostal.TYPE, ContactsContract.CommonDataKinds.StructuredPostal.TYPE_WORK)
                .build()
        }

        resolver.applyBatch(ContactsContract.AUTHORITY, operations)
    }

    private fun mapPhoneType(kind: LabeledValue.Kind): Int {
        return when (kind) {
            LabeledValue.Kind.MOBILE -> ContactsContract.CommonDataKinds.Phone.TYPE_MOBILE
            LabeledValue.Kind.WORK -> ContactsContract.CommonDataKinds.Phone.TYPE_WORK
            LabeledValue.Kind.FAX -> ContactsContract.CommonDataKinds.Phone.TYPE_FAX_WORK
            LabeledValue.Kind.HOME -> ContactsContract.CommonDataKinds.Phone.TYPE_HOME
            LabeledValue.Kind.OTHER -> ContactsContract.CommonDataKinds.Phone.TYPE_OTHER
        }
    }

    private fun mapEmailType(kind: LabeledValue.Kind): Int {
        return when (kind) {
            LabeledValue.Kind.HOME -> ContactsContract.CommonDataKinds.Email.TYPE_HOME
            LabeledValue.Kind.WORK, LabeledValue.Kind.MOBILE, LabeledValue.Kind.FAX -> ContactsContract.CommonDataKinds.Email.TYPE_WORK
            LabeledValue.Kind.OTHER -> ContactsContract.CommonDataKinds.Email.TYPE_OTHER
        }
    }
}
