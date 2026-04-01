package com.ifachang.paimingpian

import android.content.Context

class InstallationIdStore(context: Context) {
    private val preferences = context.getSharedPreferences("paimingpian_ai_proxy", Context.MODE_PRIVATE)

    fun load(): String {
        return preferences.getString("installation_id", "").orEmpty().trim()
    }

    fun save(value: String) {
        val trimmed = value.trim()
        if (trimmed.isEmpty()) return
        preferences.edit().putString("installation_id", trimmed).apply()
    }
}
