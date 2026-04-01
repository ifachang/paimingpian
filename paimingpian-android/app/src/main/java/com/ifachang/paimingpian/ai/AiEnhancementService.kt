package com.ifachang.paimingpian.ai

import com.ifachang.paimingpian.AppConfig
import com.ifachang.paimingpian.InstallationIdStore
import com.ifachang.paimingpian.model.LabeledValue
import com.ifachang.paimingpian.model.ScannedCard
import com.ifachang.paimingpian.ocr.OcrTextLine
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

class AiEnhancementService(
    private val installationIdStore: InstallationIdStore
) {
    suspend fun parseBusinessCard(
        lines: List<OcrTextLine>,
        fallback: ScannedCard
    ): Result<ScannedCard> = withContext(Dispatchers.IO) {
        runCatching {
            val payload = buildPayload(lines, fallback)
            val connection = (URL(AppConfig.aiProxyBaseUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                doOutput = true
                doInput = true
                setRequestProperty("Content-Type", "application/json")
                setRequestProperty("X-AI-Feature", "business_card_fields")
                setRequestProperty("X-Client-Platform", "android")
                val installationId = installationIdStore.load()
                if (installationId.isNotEmpty()) {
                    setRequestProperty("X-Installation-ID", installationId)
                }
            }

            OutputStreamWriter(connection.outputStream).use { writer ->
                writer.write(payload.toString())
                writer.flush()
            }

            connection.headerFields["X-Installation-ID"]?.firstOrNull()?.let {
                installationIdStore.save(it)
            }

            val body = if (connection.responseCode in 200..299) {
                BufferedReader(InputStreamReader(connection.inputStream)).use { it.readText() }
            } else {
                val errorText = BufferedReader(InputStreamReader(connection.errorStream ?: connection.inputStream)).use { it.readText() }
                val message = runCatching {
                    JSONObject(errorText).getJSONObject("error").getString("message")
                }.getOrDefault("AI 呼叫失敗。")
                throw IllegalStateException(message)
            }

            val responseJson = JSONObject(body)
            val outputText = responseJson.optString("output_text")
                .takeIf { it.isNotBlank() }
                ?: extractOutputMessageText(responseJson)
                ?: throw IllegalStateException("AI 回傳格式無法解析。")

            parseEnhancedCard(JSONObject(outputText), fallback)
        }
    }

    private fun buildPayload(lines: List<OcrTextLine>, fallback: ScannedCard): JSONObject {
        val messages = JSONArray()
            .put(
                JSONObject()
                    .put("role", "system")
                    .put("content", JSONArray().put(JSONObject().put("type", "input_text").put("text", systemPrompt)))
            )
            .put(
                JSONObject()
                    .put("role", "user")
                    .put("content", JSONArray().put(JSONObject().put("type", "input_text").put("text", buildUserPrompt(lines, fallback))))
            )

        return JSONObject()
            .put("model", AppConfig.openAIModel)
            .put("input", messages)
            .put(
                "text",
                JSONObject().put(
                    "format",
                    JSONObject()
                        .put("type", "json_schema")
                        .put("name", "business_card_fields")
                        .put("strict", true)
                        .put("schema", businessCardSchema())
                )
            )
    }

    private fun buildUserPrompt(lines: List<OcrTextLine>, fallback: ScannedCard): String {
        val lineDescriptions = lines.mapIndexed { index, line ->
            "${index + 1}. text: ${line.text}"
        }.joinToString("\n")

        val fallbackPhones = JSONArray().apply {
            fallback.phoneNumbers.forEach { put(JSONObject().put("label", it.kind.name.lowercase()).put("value", it.value)) }
        }
        val fallbackEmails = JSONArray().apply {
            fallback.emails.forEach { put(JSONObject().put("label", it.kind.name.lowercase()).put("value", it.value)) }
        }

        return """
        OCR lines:
        $lineDescriptions

        Fallback heuristic result:
        {
          "given_name": "${escapeForJson(fallback.givenName)}",
          "family_name": "${escapeForJson(fallback.familyName)}",
          "company": "${escapeForJson(fallback.company)}",
          "job_title": "${escapeForJson(fallback.jobTitle)}",
          "phone_numbers": $fallbackPhones,
          "emails": $fallbackEmails,
          "address": "${escapeForJson(fallback.address)}"
        }
        """.trimIndent()
    }

    private fun parseEnhancedCard(json: JSONObject, fallback: ScannedCard): ScannedCard {
        fun resolvedString(key: String, fallbackValue: String): String {
            return json.optString(key).trim().ifBlank { fallbackValue }
        }

        fun resolvedValues(key: String, fallbackValues: List<LabeledValue>): List<LabeledValue> {
            val items = mutableListOf<LabeledValue>()
            val array = json.optJSONArray(key) ?: JSONArray()
            for (i in 0 until array.length()) {
                val item = array.optJSONObject(i) ?: continue
                val label = item.optString("label").trim()
                val value = item.optString("value").trim()
                if (value.isBlank()) continue
                items += LabeledValue(mapKind(label), value)
            }
            return if (items.isEmpty()) fallbackValues else items
        }

        return ScannedCard(
            givenName = resolvedString("given_name", fallback.givenName),
            familyName = resolvedString("family_name", fallback.familyName),
            company = resolvedString("company", fallback.company),
            jobTitle = resolvedString("job_title", fallback.jobTitle),
            phoneNumbers = resolvedValues("phone_numbers", fallback.phoneNumbers),
            emails = resolvedValues("emails", fallback.emails),
            address = resolvedString("address", fallback.address)
        )
    }

    private fun mapKind(raw: String): LabeledValue.Kind {
        return when (raw.lowercase()) {
            "mobile" -> LabeledValue.Kind.MOBILE
            "work" -> LabeledValue.Kind.WORK
            "fax" -> LabeledValue.Kind.FAX
            "home" -> LabeledValue.Kind.HOME
            else -> LabeledValue.Kind.OTHER
        }
    }

    private fun extractOutputMessageText(responseJson: JSONObject): String? {
        val output = responseJson.optJSONArray("output") ?: return null
        for (i in 0 until output.length()) {
            val item = output.optJSONObject(i) ?: continue
            if (item.optString("type") != "message") continue
            val content = item.optJSONArray("content") ?: continue
            for (j in 0 until content.length()) {
                val entry = content.optJSONObject(j) ?: continue
                if (entry.optString("type") == "output_text") {
                    val text = entry.optString("text")
                    if (text.isNotBlank()) return text
                }
            }
        }
        return null
    }

    private fun escapeForJson(value: String): String {
        return value.replace("\\", "\\\\").replace("\"", "\\\"")
    }

    private fun businessCardSchema(): JSONObject {
        fun stringProp() = JSONObject().put("type", "string")
        fun parsedValueSchema() = JSONObject()
            .put("type", "object")
            .put("additionalProperties", false)
            .put("properties", JSONObject()
                .put("label", stringProp())
                .put("value", stringProp()))
            .put("required", JSONArray().put("label").put("value"))

        return JSONObject()
            .put("type", "object")
            .put("additionalProperties", false)
            .put(
                "properties",
                JSONObject()
                    .put("given_name", stringProp())
                    .put("family_name", stringProp())
                    .put("company", stringProp())
                    .put("job_title", stringProp())
                    .put("phone_numbers", JSONObject().put("type", "array").put("items", parsedValueSchema()))
                    .put("emails", JSONObject().put("type", "array").put("items", parsedValueSchema()))
                    .put("address", stringProp())
            )
            .put(
                "required",
                JSONArray()
                    .put("given_name")
                    .put("family_name")
                    .put("company")
                    .put("job_title")
                    .put("phone_numbers")
                    .put("emails")
                    .put("address")
            )
    }

    private val systemPrompt = """
        You extract structured contact data from OCR text lines of a business card.
        Use OCR line text and the fallback heuristic result.
        Return JSON only.
        Preserve multiple phone numbers and multiple email addresses when present.
        For phones and emails, use labels such as mobile, work, fax, home, or other.
        Leave unknown fields as empty strings or empty arrays.
    """.trimIndent()
}
