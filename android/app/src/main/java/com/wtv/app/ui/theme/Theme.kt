package com.wtv.app.ui.theme

import androidx.compose.runtime.Composable
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.darkColorScheme

private val Scheme = darkColorScheme(
    primary = WtvColors.TextPrimary,
    onPrimary = WtvColors.Background,
    background = WtvColors.Background,
    onBackground = WtvColors.TextPrimary,
    surface = WtvColors.Background,
    onSurface = WtvColors.TextPrimary,
    surfaceVariant = WtvColors.Surface,
    onSurfaceVariant = WtvColors.TextSecondary,
    border = WtvColors.Focus,
)

@Composable
fun WtvTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = Scheme, typography = WtvTypography, content = content)
}
