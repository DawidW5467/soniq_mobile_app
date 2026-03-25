package com.soniq.soniqcontroller.ui.theme

import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import com.soniq.soniqcontroller.ui.settings.FontScale

private val HighContrastColorScheme = darkColorScheme(
    primary = Color.Yellow,
    onPrimary = Color.Black,

    secondary = Color.Yellow,
    onSecondary = Color.Black,

    secondaryContainer = Color.Yellow,
    onSecondaryContainer = Color.Black,

    background = Color.Black,
    onBackground = Color.Yellow,

    surface = Color.Black,
    onSurface = Color.Yellow,

    surfaceVariant = Color(0xFF1A1A1A),
    onSurfaceVariant = Color.Yellow,

    outline = Color.Yellow
)

fun scaledTypography(scale: Float): Typography {
    val base = Typography()
    return Typography(
        displayLarge = base.displayLarge.copy(fontSize = base.displayLarge.fontSize * scale),
        headlineMedium = base.headlineMedium.copy(fontSize = base.headlineMedium.fontSize * scale),
        bodyLarge = base.bodyLarge.copy(fontSize = base.bodyLarge.fontSize * scale),
        bodyMedium = base.bodyMedium.copy(fontSize = base.bodyMedium.fontSize * scale),
        bodySmall = base.bodySmall.copy(fontSize = base.bodySmall.fontSize * scale),
        labelLarge = base.labelLarge.copy(fontSize = base.labelLarge.fontSize * scale),
        labelSmall = base.labelSmall.copy(fontSize = base.labelSmall.fontSize * scale),
    )
}

@Composable
fun SoniqTheme(
    highContrast: Boolean,
    fontScale: FontScale,
    content: @Composable () -> Unit
) {
    val colors = if (highContrast) HighContrastColorScheme else lightColorScheme()

    MaterialTheme(
        colorScheme = colors,
        typography = scaledTypography(fontScale.scale),
        content = content
    )
}




