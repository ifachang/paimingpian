package com.ifachang.paimingpian

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

data class HomeHeroConfig(
    val imageUrl: String,
    val linkUrl: String
)

class HomeHeroService {
    suspend fun load(): HomeHeroConfig? = withContext(Dispatchers.IO) {
        runCatching {
            val connection = (URL(AppConfig.homeHeroConfigUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 8000
                readTimeout = 8000
                setRequestProperty("Accept", "application/json")
            }

            if (connection.responseCode !in 200..299) {
                return@withContext null
            }

            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)
            HomeHeroConfig(
                imageUrl = json.optString("imageURL").trim(),
                linkUrl = json.optString("linkURL").trim()
            )
        }.getOrNull()
    }
}
