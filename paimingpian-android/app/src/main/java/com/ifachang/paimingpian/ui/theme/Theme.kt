package com.ifachang.paimingpian.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = Slate,
    secondary = GoldDeep,
    background = Sand,
    surface = Paper,
    onPrimary = Paper,
    onSecondary = Paper,
    onBackground = Ink,
    onSurface = Ink
)

private val DarkColors = darkColorScheme(
    primary = Paper,
    secondary = Gold,
    background = Slate,
    surface = Slate,
    onPrimary = Slate,
    onSecondary = Slate,
    onBackground = Paper,
    onSurface = Paper
)

@Composable
fun PaiMingPianTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        content = content
    )
}
