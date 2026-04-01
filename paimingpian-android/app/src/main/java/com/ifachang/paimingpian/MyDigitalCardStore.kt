package com.ifachang.paimingpian

import android.content.Context
import com.ifachang.paimingpian.model.LabeledValue
import com.ifachang.paimingpian.model.ScannedCard
import org.json.JSONArray
import org.json.JSONObject

class MyDigitalCardStore(context: Context) {
    private val preferences = context.getSharedPreferences("paimingpian_my_card", Context.MODE_PRIVATE)

    fun load(): ScannedCard {
        val raw = preferences.getString("card", null) ?: return ScannedCard()
        return runCatching {
            val json = JSONObject(raw)
            ScannedCard(
                givenName = json.optString("givenName"),
                familyName = json.optString("familyName"),
                company = json.optString("company"),
                jobTitle = json.optString("jobTitle"),
                phoneNumbers = parseValues(json.optJSONArray("phoneNumbers")),
                emails = parseValues(json.optJSONArray("emails")),
                address = json.optString("address")
            )
        }.getOrDefault(ScannedCard())
    }

    fun save(card: ScannedCard) {
        val json = JSONObject()
            .put("givenName", card.givenName)
            .put("familyName", card.familyName)
            .put("company", card.company)
            .put("jobTitle", card.jobTitle)
            .put("address", card.address)
            .put("phoneNumbers", encodeValues(card.phoneNumbers))
            .put("emails", encodeValues(card.emails))

        preferences.edit().putString("card", json.toString()).apply()
    }

    private fun encodeValues(values: List<LabeledValue>): JSONArray {
        return JSONArray().apply {
            values.forEach {
                put(
                    JSONObject()
                        .put("kind", it.kind.name)
                        .put("value", it.value)
                )
            }
        }
    }

    private fun parseValues(array: JSONArray?): List<LabeledValue> {
        if (array == null) return emptyList()
        return buildList {
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val kind = runCatching { LabeledValue.Kind.valueOf(item.optString("kind")) }
                    .getOrDefault(LabeledValue.Kind.OTHER)
                add(LabeledValue(kind, item.optString("value")))
            }
        }
    }
}
