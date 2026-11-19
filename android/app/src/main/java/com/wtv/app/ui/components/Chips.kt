package com.wtv.app.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.tv.material3.Border
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.FilterChipDefaults
import com.wtv.app.ui.theme.WtvColors

/**
 * A choice chip (sort, filter, season, group, setting): dark and borderless,
 * its text white at 50%, or full white on a darker chip when selected.
 * Focused, it turns light like the tabs.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun ChoiceChip(selected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val dim = WtvColors.TextPrimary.copy(alpha = 0.5f)
    FilterChip(
        selected = selected,
        onClick = onClick,
        modifier = modifier,
        colors = FilterChipDefaults.colors(
            containerColor = WtvColors.Chip,
            contentColor = dim,
            focusedContainerColor = WtvColors.TextPrimary,
            focusedContentColor = WtvColors.Background,
            pressedContainerColor = WtvColors.TextPrimary,
            pressedContentColor = WtvColors.Background,
            selectedContainerColor = WtvColors.ChipSelected,
            selectedContentColor = WtvColors.TextPrimary,
            focusedSelectedContainerColor = WtvColors.TextPrimary,
            focusedSelectedContentColor = WtvColors.Background,
            pressedSelectedContainerColor = WtvColors.TextPrimary,
            pressedSelectedContentColor = WtvColors.Background,
        ),
        border = FilterChipDefaults.border(
            border = Border.None,
            focusedBorder = Border.None,
            pressedBorder = Border.None,
            selectedBorder = Border.None,
            focusedSelectedBorder = Border.None,
            pressedSelectedBorder = Border.None,
        ),
        content = content,
    )
}
