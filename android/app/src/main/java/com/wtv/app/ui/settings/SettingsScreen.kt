package com.wtv.app.ui.settings

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.AppLanguage
import com.wtv.app.R
import com.wtv.app.ui.theme.WtvColors

/**
 * Settings. For now the app language; the account, provider login and hidden
 * channels come with P6-1.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SettingsScreen(firstFocus: FocusRequester) {
    val context = LocalContext.current
    val current = remember { AppLanguage.current(context) }
    Column(Modifier.fillMaxSize().padding(start = 88.dp, top = 48.dp)) {
        Text(stringResource(R.string.rail_settings), style = MaterialTheme.typography.displayMedium, color = WtvColors.TextPrimary)
        Spacer(Modifier.height(32.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(stringResource(R.string.setting_language), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextSecondary)
            Spacer(Modifier.width(24.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                AppLanguage.entries.forEach { language ->
                    FilterChip(
                        selected = language == current,
                        onClick = {
                            if (language != current) {
                                AppLanguage.save(context, language)
                                // Recreated with the new language and layout direction.
                                (context as? Activity)?.recreate()
                            }
                        },
                        modifier = if (language == current) Modifier.focusRequester(firstFocus) else Modifier,
                    ) {
                        // Each language is named in itself, so it can be found whatever the current one.
                        Text(
                            stringResource(
                                when (language) {
                                    AppLanguage.English -> R.string.language_english
                                    AppLanguage.Hebrew -> R.string.language_hebrew
                                },
                            ),
                        )
                    }
                }
            }
        }
    }
}
