package com.wtv.app.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.sp
import androidx.tv.material3.Typography

/**
 * Sizes for a 1080p TV seen from the sofa (the screen is 960 x 540 dp).
 * Text direction follows the text itself, so an English synopsis in the
 * Hebrew layout keeps its full stop at the end.
 */
val WtvTypography = Typography(
    // Title in the header.
    displayMedium = TextStyle(fontSize = 36.sp, lineHeight = 42.sp, fontWeight = FontWeight.Bold, textDirection = TextDirection.Content),
    // Person name, big page titles.
    headlineMedium = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, textDirection = TextDirection.Content),
    // Row titles ("Viewers also liked").
    titleMedium = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.SemiBold, textDirection = TextDirection.Content),
    // Meta line, highlight line.
    titleSmall = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium, textDirection = TextDirection.Content),
    // Synopsis.
    bodyLarge = TextStyle(fontSize = 15.sp, lineHeight = 22.sp, fontWeight = FontWeight.Normal, textDirection = TextDirection.Content),
    bodyMedium = TextStyle(fontSize = 13.sp, lineHeight = 18.sp, fontWeight = FontWeight.Normal, textDirection = TextDirection.Content),
    // Badges and card labels.
    labelLarge = TextStyle(fontSize = 14.sp, lineHeight = 18.sp, fontWeight = FontWeight.SemiBold, textDirection = TextDirection.Content),
    labelMedium = TextStyle(fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Bold, textDirection = TextDirection.Content),
)
