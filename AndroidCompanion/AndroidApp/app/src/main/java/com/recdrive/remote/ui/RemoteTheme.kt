package com.recdrive.remote.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DarkColorScheme = darkColorScheme(
    primary = Color(0xFF0A84FF),
    onPrimary = Color.White,
    secondary = Color(0xFF30D158),
    onSecondary = Color.White,
    background = Color(0xFF0A0C0E),
    onBackground = Color(0xFFE5E7EB),
    surface = Color(0xFF16191F),
    onSurface = Color(0xFFF3F4F6),
    surfaceVariant = Color(0xFF222730),
    onSurfaceVariant = Color(0xFF9CA3AF),
    error = Color(0xFFFF453A)
)

@Composable
fun RemoteTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        content = content
    )
}
