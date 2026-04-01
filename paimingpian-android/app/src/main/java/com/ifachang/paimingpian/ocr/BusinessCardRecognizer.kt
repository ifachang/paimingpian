package com.ifachang.paimingpian.ocr

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import kotlinx.coroutines.tasks.await

class BusinessCardRecognizer {
    private val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())

    suspend fun recognizeFromBitmap(bitmap: Bitmap): ScannedCardRecognitionResult {
        return try {
            val image = InputImage.fromBitmap(bitmap, 0)
            runRecognition(image)
        } catch (error: Exception) {
            ScannedCardRecognitionResult.Failure(error.message ?: "辨識失敗，請再試一次。")
        }
    }

    suspend fun recognizeFromUri(
        context: Context,
        uri: Uri
    ): ScannedCardRecognitionResult {
        return try {
            val image = InputImage.fromFilePath(context, uri)
            runRecognition(image)
        } catch (error: Exception) {
            ScannedCardRecognitionResult.Failure(error.message ?: "讀取照片失敗，請換一張圖片再試一次。")
        }
    }

    private suspend fun runRecognition(image: InputImage): ScannedCardRecognitionResult {
        val result = recognizer.process(image).await()
        val lines = result.textBlocks
            .flatMap { block -> block.lines }
            .mapIndexedNotNull { index, line ->
                val text = line.text.trim()
                if (text.isBlank()) null else OcrTextLine(text = text, order = index)
            }

        if (lines.isEmpty()) {
            return ScannedCardRecognitionResult.Failure("沒有辨識到文字，請換一張更清楚的名片照片。")
        }

        val card = BusinessCardParser.parse(lines)
        return ScannedCardRecognitionResult.Success(card = card, lines = lines)
    }
}

sealed interface ScannedCardRecognitionResult {
    data class Success(
        val card: com.ifachang.paimingpian.model.ScannedCard,
        val lines: List<OcrTextLine>
    ) : ScannedCardRecognitionResult

    data class Failure(val message: String) : ScannedCardRecognitionResult
}
