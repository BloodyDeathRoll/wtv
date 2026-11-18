package com.wtv.app.ui.settings

import android.app.Activity
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
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
import com.wtv.app.WtvApplication
import com.wtv.app.data.ApiException
import com.wtv.app.data.Channel
import com.wtv.app.data.GoogleSignIn
import com.wtv.app.data.LiveCategory
import com.wtv.app.data.LiveFilters
import com.wtv.app.player.ProviderLogin
import com.wtv.app.ui.browse.isHebrew
import com.wtv.app.ui.components.Sideways
import com.wtv.app.ui.theme.WtvColors
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Settings: the app language, the Google account, Live TV (radio switch,
 * hidden channels and groups) and the provider login. `providerFirst` opens the page on the login (Play
 * sends the user here when there is none).
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
fun SettingsScreen(firstFocus: FocusRequester, providerFirst: Boolean = false) {
    val context = LocalContext.current
    val current = remember { AppLanguage.current(context) }
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(start = 88.dp, top = 48.dp, bottom = 48.dp)) {
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
        Spacer(Modifier.height(32.dp))
        AccountSection()
        Spacer(Modifier.height(32.dp))
        LiveSection()
        Spacer(Modifier.height(32.dp))
        ProviderSection(focus = if (providerFirst) firstFocus else null)
    }
}

/** The radio switch, and what is hidden on the Live TV page; selecting a hidden item shows it again. */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun LiveSection() {
    val catalog = (LocalContext.current.applicationContext as WtvApplication).catalog
    val hebrew = isHebrew()
    val scope = rememberCoroutineScope()
    var filters by remember { mutableStateOf<LiveFilters?>(null) }
    var failed by remember { mutableStateOf<String?>(null) }
    var channels by remember { mutableStateOf(emptyList<Channel>()) }
    var categories by remember { mutableStateOf(emptyList<LiveCategory>()) }
    LaunchedEffect(Unit) {
        // Names for the hidden items are a nicety; the switch needs only the filters.
        runCatching { catalog.liveFilters() }.onSuccess { filters = it }.onFailure { failed = it.message ?: it.toString() }
        runCatching { channels = catalog.channels(); categories = catalog.liveCategories() }
    }
    // A chip that goes takes the focus with it: it moves first to a neighbour, or the radio switch.
    val radio = remember { FocusRequester() }
    val chips = remember { mutableMapOf<String, FocusRequester>() }
    // Saved at once. A failed save undoes only its own change: others may have been made meanwhile.
    fun change(apply: (LiveFilters) -> LiveFilters, undo: (LiveFilters) -> LiveFilters, save: suspend () -> Unit) {
        filters = filters?.let(apply)
        scope.launch { runCatching { save() }.onFailure { filters = filters?.let(undo) } }
    }

    Text(stringResource(R.string.setting_live), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
    Spacer(Modifier.height(12.dp))
    val f = filters
    if (f == null) {
        failed?.let { Text(stringResource(R.string.load_failed, it), style = MaterialTheme.typography.bodyMedium, color = WtvColors.TextMuted) }
        return
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.setting_radio), style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextSecondary, modifier = Modifier.width(140.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            for (on in listOf(true, false)) {
                FilterChip(
                    selected = f.showRadio == on,
                    onClick = { if (f.showRadio != on) change({ it.copy(showRadio = on) }, { it.copy(showRadio = !on) }) { catalog.setShowRadio(on) } },
                    modifier = if (on) Modifier.focusRequester(radio) else Modifier,
                ) { Text(stringResource(if (on) R.string.setting_on else R.string.setting_off)) }
            }
        }
    }
    Spacer(Modifier.height(10.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.setting_hidden), style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextSecondary, modifier = Modifier.width(140.dp))
        val groups = categories.filter { it.id in f.hiddenGroups }
        val hiddenChannels = channels.filter { it.id in f.hiddenChannels }
        val keys = groups.map { "g${it.id}" } + hiddenChannels.map { "c${it.id}" }
        fun leave(key: String) {
            val i = keys.indexOf(key)
            val next = keys.getOrNull(i + 1) ?: keys.getOrNull(i - 1)
            if (next == null || runCatching { chips.getValue(next).requestFocus() }.isFailure) runCatching { radio.requestFocus() }
        }
        if (groups.isEmpty() && hiddenChannels.isEmpty()) {
            Text(stringResource(R.string.setting_hidden_none), style = MaterialTheme.typography.bodyMedium, color = WtvColors.TextMuted)
        } else {
            Sideways {
                LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp), contentPadding = PaddingValues(end = 48.dp)) {
                    items(groups, key = { "g${it.id}" }) { c ->
                        val key = "g${c.id}"
                        FilterChip(selected = false, modifier = Modifier.focusRequester(chips.getOrPut(key) { FocusRequester() }), onClick = {
                            leave(key)
                            change({ it.copy(hiddenGroups = it.hiddenGroups - c.id) }, { it.copy(hiddenGroups = it.hiddenGroups + c.id) }) {
                                catalog.setGroupHidden(c.id, false)
                            }
                        }) { Text(c.label(hebrew)) }
                    }
                    items(hiddenChannels, key = { "c${it.id}" }) { c ->
                        val key = "c${c.id}"
                        FilterChip(selected = false, modifier = Modifier.focusRequester(chips.getOrPut(key) { FocusRequester() }), onClick = {
                            leave(key)
                            change({ it.copy(hiddenChannels = it.hiddenChannels - c.id) }, { it.copy(hiddenChannels = it.hiddenChannels + c.id) }) {
                                catalog.setChannelHidden(c.id, false)
                            }
                        }) { Text(c.name) }
                    }
                }
            }
        }
    }
    Text(stringResource(R.string.setting_hidden_hint), style = MaterialTheme.typography.bodySmall, color = WtvColors.TextMuted, modifier = Modifier.padding(start = 140.dp, top = 4.dp))
}

/**
 * Google sign-in: a code to enter on the phone, then a WTV session. Connecting
 * WTW is a separate step, for people who already use WTW: signing in to WTW
 * with a new Google account would create a WTW account, and WTV never writes
 * to WTW. The page is rebuilt afterwards, so every screen reads as the new user.
 */
@OptIn(ExperimentalTvMaterial3Api::class)
@Composable
private fun AccountSection() {
    val context = LocalContext.current
    val app = context.applicationContext as WtvApplication
    val scope = rememberCoroutineScope()
    val email = remember { app.session.email }
    val wtwEmail = remember { app.wtw.email }
    // Connect WTW asks first: WTW is read-only for us, so nothing can check that the account exists.
    var confirmWtw by remember { mutableStateOf(false) }
    // A WTW session left without a WTV one (an interrupted sign-out) is ended, not shown.
    LaunchedEffect(Unit) { if (email == null && wtwEmail != null) app.wtw.signOut() }
    var code by remember { mutableStateOf<GoogleSignIn.Code?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var job by remember { mutableStateOf<Job?>(null) }
    // Set once the phone has approved: the sign-in then finishes whatever Cancel says.
    var finishing by remember { mutableStateOf(false) }
    // On whichever button starts a sign-in (Sign in, or Connect WTW).
    val startFocus = remember { FocusRequester() }
    val cancelFocus = remember { FocusRequester() }
    var codeShown by remember { mutableStateOf(false) }
    // The focused button leaves the screen when the code appears or goes; focus follows to the new one.
    LaunchedEffect(code) {
        if (code != null) {
            codeShown = true
            cancelFocus.requestFocus()
        } else if (codeShown) {
            startFocus.requestFocus()
        }
    }

    /** Shows a code; once the phone approves, `signIn` runs with the ID token and the page is rebuilt. */
    fun start(signIn: suspend (String) -> Unit) {
        if (job?.isActive == true || finishing) return
        error = null
        job = scope.launch {
            try {
                val started = app.google.start()
                code = started
                val idToken = app.google.awaitIdToken(started)
                // Cancel stops the wait only: once approved, the sign-in runs to the end.
                finishing = true
                withContext(NonCancellable) {
                    signIn(idToken)
                    (context as? Activity)?.recreate()
                }
            } catch (e: ApiException) {
                error = e.message
                code = null
            } finally {
                finishing = false
            }
        }
    }

    @Composable
    fun Note(text: String) = Text(text, style = MaterialTheme.typography.bodyMedium, color = WtvColors.TextSecondary)

    Text(stringResource(R.string.setting_account), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
    Spacer(Modifier.height(12.dp))
    val shown = code
    if (shown != null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column {
                Text(
                    stringResource(R.string.sign_in_code, shown.url.removePrefix("https://").removePrefix("www.")),
                    style = MaterialTheme.typography.bodyLarge,
                    color = WtvColors.TextSecondary,
                )
                Text(shown.userCode, style = MaterialTheme.typography.displaySmall, color = WtvColors.Accent)
            }
            Spacer(Modifier.width(24.dp))
            Button(
                onClick = {
                    if (!finishing) {
                        job?.cancel()
                        code = null
                    }
                },
                modifier = Modifier.focusRequester(cancelFocus),
            ) { Text(stringResource(R.string.cancel)) }
        }
        return
    }
    if (email == null) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(
                onClick = { start { app.session.signInWithGoogle(it, link = true) } },
                modifier = Modifier.focusRequester(startFocus),
            ) { Text(stringResource(R.string.sign_in_google)) }
            Spacer(Modifier.width(16.dp))
            Note(error?.let { stringResource(R.string.sign_in_failed, it) } ?: stringResource(R.string.account_signed_out))
        }
        return
    }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(stringResource(R.string.signed_in), style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextSecondary)
        Spacer(Modifier.width(8.dp))
        Text(email, style = MaterialTheme.typography.bodyLarge, color = WtvColors.TextPrimary)
        Spacer(Modifier.width(24.dp))
        Button(onClick = {
            scope.launch(NonCancellable) {
                app.session.signOut()
                app.wtw.signOut()
                (context as? Activity)?.recreate()
            }
        }) { Text(stringResource(R.string.sign_out)) }
    }
    Spacer(Modifier.height(10.dp))
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (wtwEmail != null) {
            Note(stringResource(R.string.wtw_connected, wtwEmail))
        } else {
            Button(
                onClick = {
                    if (confirmWtw) start { app.wtw.signInWithGoogle(it, link = false) } else confirmWtw = true
                },
                modifier = Modifier.focusRequester(startFocus),
            ) { Text(stringResource(if (confirmWtw) R.string.connect_wtw_confirm else R.string.connect_wtw)) }
            Spacer(Modifier.width(16.dp))
            Column {
                Note(stringResource(R.string.connect_wtw_hint))
                error?.let { Note(stringResource(R.string.sign_in_failed, it)) }
            }
        }
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
    // Null: nothing to say; else the message after Save.
    var result by remember { mutableStateOf<Int?>(null) }

    Text(stringResource(R.string.setting_provider), style = MaterialTheme.typography.titleMedium, color = WtvColors.TextPrimary)
    Spacer(Modifier.height(12.dp))
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SettingField(stringResource(R.string.provider_server), server, { server = it; result = null }, focus = focus)
        SettingField(stringResource(R.string.provider_user), user, { user = it; result = null })
        SettingField(stringResource(R.string.provider_password), password, { password = it; result = null }, secret = true)
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = {
                val login = ProviderLogin(server, user, password)
                result = when {
                    !login.isComplete -> R.string.provider_incomplete
                    ProviderLogin.save(context, login) -> R.string.saved
                    else -> R.string.provider_save_failed
                }
            }) { Text(stringResource(R.string.save)) }
            result?.let {
                Spacer(Modifier.width(16.dp))
                Text(
                    stringResource(it),
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (it == R.string.saved) WtvColors.Accent else WtvColors.TextSecondary,
                )
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
