package com.soniq.soniqcontroller.ui.theme

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val HighContrastColorScheme = darkColorScheme(
    primary = Color.Yellow,
    onPrimary = Color.Black,
    background = Color.Black,
    onBackground = Color.Yellow,
    surface = Color.Black,
    onSurface = Color.Yellow
)



@Composable
fun SoniqTheme(
    highContrast: Boolean,
    content: @Composable () -> Unit
) {
    val colors = if (highContrast) {
        HighContrastColorScheme
    } else {
        lightColorScheme()
    }

    MaterialTheme(
        colorScheme = colors,
        content = content
    )
}
