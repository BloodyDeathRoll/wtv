package com.wtv.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import com.wtv.app.R
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.ui.theme.WtvColors

/** Age rating or format badge: "TV-14", "16+", "4K". */
@Composable
fun Badge(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelMedium,
        color = WtvColors.TextPrimary,
        modifier = modifier
            .background(WtvColors.Badge, RoundedCornerShape(4.dp))
            .padding(horizontal = 7.dp, vertical = 3.dp),
    )
}

/** WTW's "92% match", as WTW shows it; `small` on cards. */
@Composable
fun MatchBadge(percent: Int, modifier: Modifier = Modifier, small: Boolean = false) {
    Row(
        modifier
            .background(Color(0xCC000000), RoundedCornerShape(if (small) 4.dp else 6.dp))
            .padding(horizontal = if (small) 6.dp else 10.dp, vertical = if (small) 2.dp else 5.dp),
        horizontalArrangement = Arrangement.spacedBy(if (small) 4.dp else 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(if (small) 6.dp else 8.dp).background(WtvColors.Accent, CircleShape))
        Text(
            stringResource(R.string.wtw_match, percent),
            style = if (small) MaterialTheme.typography.labelSmall else MaterialTheme.typography.titleSmall,
            color = WtvColors.TextPrimary,
        )
    }
}

/** Light tag in front of the meta line: "TRENDING", "NEW". */
@Composable
fun Tag(text: String, modifier: Modifier = Modifier) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        color = WtvColors.OnTag,
        modifier = modifier
            .background(WtvColors.Tag, RoundedCornerShape(4.dp))
            .padding(horizontal = 7.dp, vertical = 3.dp),
    )
}
