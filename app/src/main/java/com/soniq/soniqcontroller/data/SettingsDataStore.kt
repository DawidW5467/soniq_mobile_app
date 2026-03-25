package com.soniq.soniqcontroller.data

import android.content.Context
import androidx.datastore.preferences.core.*
import androidx.datastore.preferences.preferencesDataStore
import com.soniq.soniqcontroller.ui.settings.FontScale
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

private val Context.dataStore by preferencesDataStore(name = "settings")

class SettingsDataStore(private val context: Context) {

    private object Keys {
        val HIGH_CONTRAST = booleanPreferencesKey("high_contrast")
        val REPLACE_ICONS = booleanPreferencesKey("replace_icons")
        val FONT_SCALE = stringPreferencesKey("font_scale")
    }

    val highContrast: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.HIGH_CONTRAST] ?: false }

    val replaceIcons: Flow<Boolean> =
        context.dataStore.data.map { it[Keys.REPLACE_ICONS] ?: false }

    val fontScale: Flow<FontScale> =
        context.dataStore.data.map {
            FontScale.valueOf(it[Keys.FONT_SCALE] ?: FontScale.NORMAL.name)
        }

    suspend fun setHighContrast(value: Boolean) {
        context.dataStore.edit { it[Keys.HIGH_CONTRAST] = value }
    }

    suspend fun setReplaceIcons(value: Boolean) {
        context.dataStore.edit { it[Keys.REPLACE_ICONS] = value }
    }

    suspend fun setFontScale(value: FontScale) {
        context.dataStore.edit { it[Keys.FONT_SCALE] = value.name }
    }
}
