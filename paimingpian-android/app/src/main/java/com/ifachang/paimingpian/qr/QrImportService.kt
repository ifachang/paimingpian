package com.ifachang.paimingpian.qr

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.common.InputImage
import com.ifachang.paimingpian.model.LabeledValue
import com.ifachang.paimingpian.model.ScannedCard
import kotlinx.coroutines.tasks.await

class QrImportService {
    private val scanner = BarcodeScanning.getClient()

    suspend fun importFromBitmap(bitmap: Bitmap): Result<ScannedCard> {
        return readCard(InputImage.fromBitmap(bitmap, 0))
    }

    suspend fun importFromUri(
        context: Context,
        uri: Uri
    ): Result<ScannedCard> {
        return readCard(InputImage.fromFilePath(context, uri))
    }

    private suspend fun readCard(image: InputImage): Result<ScannedCard> = runCatching {
        val barcodes = scanner.process(image).await()
        val payload = barcodes.firstNotNullOfOrNull { it.rawValue?.takeIf(String::isNotBlank) }
            ?: throw IllegalStateException("沒有掃描到可讀取的 QR Code。")

        VCardParser.parse(payload)
    }
}

private object VCardParser {
    fun parse(payload: String): ScannedCard {
        val lines = payload
            .replace("\r\n", "\n")
            .split('\n')
            .map { it.trim() }
            .filter { it.isNotBlank() }

        if (lines.none { it.equals("BEGIN:VCARD", ignoreCase = true) }) {
            throw IllegalStateException("這個 QR Code 不是可讀取的電子名片格式。")
        }

        var givenName = ""
        var familyName = ""
        var displayName = ""
        var company = ""
        var jobTitle = ""
        var address = ""
        val phones = mutableListOf<LabeledValue>()
        val emails = mutableListOf<LabeledValue>()

        lines.forEach { line ->
            when {
                line.startsWith("N:", ignoreCase = true) -> {
                    val body = line.substringAfter("N:")
                    val parts = body.split(';')
                    familyName = parts.getOrNull(0).orEmpty().unescapeValue()
                    givenName = parts.getOrNull(1).orEmpty().unescapeValue()
                }

                line.startsWith("FN:", ignoreCase = true) -> {
                    displayName = line.substringAfter("FN:").unescapeValue()
                }

                line.startsWith("ORG:", ignoreCase = true) -> {
                    company = line.substringAfter("ORG:").unescapeValue()
                }

                line.startsWith("TITLE:", ignoreCase = true) -> {
                    jobTitle = line.substringAfter("TITLE:").unescapeValue()
                }

                line.startsWith("TEL", ignoreCase = true) -> {
                    val value = line.substringAfter(':').unescapeValue()
                    if (value.isNotBlank()) {
                        phones += LabeledValue(kindFromLabel(line, isEmail = false), value)
                    }
                }

                line.startsWith("EMAIL", ignoreCase = true) -> {
                    val value = line.substringAfter(':').unescapeValue()
                    if (value.isNotBlank()) {
                        emails += LabeledValue(kindFromLabel(line, isEmail = true), value)
                    }
                }

                line.startsWith("ADR", ignoreCase = true) -> {
                    val value = line.substringAfter(':')
                    val parts = value.split(';').map { it.unescapeValue() }
                    address = parts.filter { it.isNotBlank() }.joinToString(" ")
                }
            }
        }

        val fallbackName = displayName.takeIf { it.isNotBlank() }.orEmpty()
        return ScannedCard(
            givenName = if (givenName.isBlank() && familyName.isBlank()) fallbackName else givenName,
            familyName = familyName,
            company = company,
            jobTitle = jobTitle,
            phoneNumbers = phones,
            emails = emails,
            address = address
        ).normalized()
    }

    private fun kindFromLabel(line: String, isEmail: Boolean): LabeledValue.Kind {
        val lower = line.lowercase()
        return when {
            lower.contains("mobile") -> LabeledValue.Kind.MOBILE
            lower.contains("work") -> LabeledValue.Kind.WORK
            lower.contains("fax") -> LabeledValue.Kind.FAX
            lower.contains("home") -> LabeledValue.Kind.HOME
            else -> if (isEmail) LabeledValue.Kind.OTHER else LabeledValue.Kind.OTHER
        }
    }

    private fun String.unescapeValue(): String {
        return replace("\\n", "\n")
            .replace("\\;", ";")
            .replace("\\,", ",")
            .replace("\\\\", "\\")
    }
}
