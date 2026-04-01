package com.ifachang.paimingpian.qr

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.ifachang.paimingpian.model.ScannedCard

object VCardService {
    fun makeVCardString(card: ScannedCard): String? {
        val normalized = card.normalized()
        if (!normalized.hasContent) return null

        val phoneLines = normalized.phoneNumbers
            .filterNot { it.isEmpty }
            .joinToString("\n") { "TEL;TYPE=${it.kind.name.lowercase()}:${escape(it.value)}" }

        val emailLines = normalized.emails
            .filterNot { it.isEmpty }
            .joinToString("\n") { "EMAIL;TYPE=${it.kind.name.lowercase()}:${escape(it.value)}" }

        val addressLine = normalized.address
            .takeIf { it.isNotBlank() }
            ?.let { "ADR;TYPE=WORK:;;${escape(it)};;;;" }
            .orEmpty()

        return buildString {
            appendLine("BEGIN:VCARD")
            appendLine("VERSION:3.0")
            appendLine("N:${escape(normalized.familyName)};${escape(normalized.givenName)};;;")
            appendLine("FN:${escape(normalized.displayName)}")
            if (normalized.company.isNotBlank()) appendLine("ORG:${escape(normalized.company)}")
            if (normalized.jobTitle.isNotBlank()) appendLine("TITLE:${escape(normalized.jobTitle)}")
            if (phoneLines.isNotBlank()) appendLine(phoneLines)
            if (emailLines.isNotBlank()) appendLine(emailLines)
            if (addressLine.isNotBlank()) appendLine(addressLine)
            appendLine("END:VCARD")
        }.trim()
    }

    fun makeQrBitmap(text: String, size: Int = 960): Bitmap {
        val matrix = QRCodeWriter().encode(
            text,
            BarcodeFormat.QR_CODE,
            size,
            size,
            mapOf(
                EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.M,
                EncodeHintType.MARGIN to 1
            )
        )

        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        for (x in 0 until size) {
            for (y in 0 until size) {
                bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
            }
        }
        return bitmap
    }

    private fun escape(value: String): String {
        return value
            .replace("\\", "\\\\")
            .replace(";", "\\;")
            .replace(",", "\\,")
            .replace("\n", "\\n")
    }
}
