package com.wtv.app.ui.settings

import android.app.Activity
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.tv.material3.Button
import androidx.tv.material3.ExperimentalTvMaterial3Api
import androidx.tv.material3.FilterChip
import androidx.tv.material3.MaterialTheme
import androidx.tv.material3.Text
import com.wtv.app.AppLanguage
import com.wtv.app.R
import com.wtv.app.player.ProviderLogin
import com.wtv.app.ui.theme.WtvColors

/**
 * Settings: the app language and the provider login. The account and hidden
 * channels come with P6-1. `providerFirst` opens the page on the login (Play
 * sends the user here when there is none).
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SettingsScreen(firstFocus: FocusRequester, providerFirst: Boolean = false) {
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
                        modifier = if (language == current && !providerFirst) Modifier.focusRequester(firstFocus) else Modifier,
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
        Spacer(Modifier.height(40.dp))
        ProviderSection(focus = if (providerFirst) firstFocus else null)
    }
}

/** Server, user name and password of the provider, saved encrypted on this device. */
@Composable
private fun ProviderSection(focus: FocusRequester?) {
    val context = LocalContext.current
    val saved = remember { ProviderLogin.load(context) }
    var server by remember { mutableStateOf(saved?.server.orEmpty()) }
    var user by remember { mutableStateOf(saved?.user.orEmpty()) }
    var password by remember { mutableStateOf(saved?.password.orEmpty()) }
    var done by remember { mutableStateOf(false) }

    Text(stringResource(R.string.setting_provider), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
    Spacer(Modifier.height(12.dp))
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SettingField(stringResource(R.string.provider_server), server, { server = it; done = false }, focus = focus)
        SettingField(stringResource(R.string.provider_user), user, { user = it; done = false })
        SettingField(stringResource(R.string.provider_password), password, { password = it; done = false }, secret = true)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = {
                ProviderLogin.save(context, ProviderLogin(server, user, password))
                done = true
            }) { Text(stringResource(R.string.save)) }
            if (done) {
                Spacer(Modifier.width(16.dp))
                Text(stringResource(R.string.saved), style = MaterialTheme.typography.bodyMedium, color = WtvColors.Accent)
            }
        }
    }
}

/** A labelled one-line text field; the TV keyboard opens on it. */
@Composable
private fun SettingField(label: String, value: String, onChange: (String) -> Unit, focus: FocusRequester? = null, secret: Boolean = false) {
    var focused by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextSecondary, modifier = Modifier.width(140.dp))
        BasicTextField(
            value = value,
            onValueChange = onChange,
            singleLine = true,
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = WtvColors.TextPrimary),
            cursorBrush = SolidColor(WtvColors.TextPrimary),
            visualTransformation = if (secret) PasswordVisualTransformation() else VisualTransformation.None,
            keyboardOptions = KeyboardOptions(
                keyboardType = if (secret) KeyboardType.Password else KeyboardType.Uri,
                imeAction = ImeAction.Next,
                autoCorrectEnabled = false,
            ),
            // The keyboard's Next key goes to the next field (or Save).
            keyboardActions = KeyboardActions(onNext = { focusManager.moveFocus(FocusDirection.Down) }),
            modifier = Modifier
                .width(420.dp)
                .then(if (focus != null) Modifier.focusRequester(focus) else Modifier)
                .onFocusChanged { focused = it.isFocused }
                // A text field keeps Up and Down for its cursor; on a TV they move between fields.
                .onPreviewKeyEvent {
                    if (it.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                    when (it.key) {
                        Key.DirectionDown -> focusManager.moveFocus(FocusDirection.Down)
                        Key.DirectionUp -> focusManager.moveFocus(FocusDirection.Up)
                        else -> false
                    }
                }
                .background(WtvColors.Surface, RoundedCornerShape(8.dp))
                .border(BorderStroke(2.dp, if (focused) WtvColors.Focus else WtvColors.Surface), RoundedCornerShape(8.dp))
                .padding(horizontal = 14.dp, vertical = 8.dp),
        )
    }
}
