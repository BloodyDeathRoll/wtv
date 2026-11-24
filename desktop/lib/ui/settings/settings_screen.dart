import 'package:material_ui/material_ui.dart';

import '../../app_language.dart';
import '../../config.dart';
import '../../data/google_sign_in.dart';
import '../../data/live.dart';
import '../../data/provider_login.dart';
import '../../data/session.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/buttons.dart';
import '../components/chips.dart';
import '../components/fields.dart';
import '../components/rows.dart';
import '../theme.dart';

/// Settings: the app language, the Google account and WTW, Live TV (the radio
/// switch, hidden channels and groups), the provider login, and About.
/// `providerFirst` opens the page on the login (Play sends the user here when
/// there is none).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.firstFocus, this.providerFirst = false});

  final FocusNode firstFocus;
  final bool providerFirst;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // The chip focused when the page opens. It keeps that focus node when the language changes under it.
  final _opened = appLanguage.value;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    return NearestRows(
      child: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(start: 88, top: 48, bottom: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.railSettings, style: text.displayMedium),
            const SizedBox(height: 32),
            Row(
              spacing: 10,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 14),
                  child: Text(l.settingLanguage, style: text.titleMedium!.copyWith(color: WtvColors.textSecondary)),
                ),
                for (final language in AppLanguage.values)
                  OptionChip(
                    selected: language == appLanguage.value,
                    focusNode: language == _opened && !widget.providerFirst ? widget.firstFocus : null,
                    onPressed: () => saveLanguage(language),
                    // Each language is named in itself, so it can be found whatever the current one.
                    label: switch (language) {
                      AppLanguage.english => l.languageEnglish,
                      AppLanguage.hebrew => l.languageHebrew,
                    },
                  ),
              ],
            ),
            const SizedBox(height: 32),
            const _AccountSection(),
            const SizedBox(height: 32),
            const _LiveSection(),
            const SizedBox(height: 32),
            _ProviderSection(focus: widget.providerFirst ? widget.firstFocus : null),
            const SizedBox(height: 32),
            const _AboutSection(),
          ],
        ),
      ),
    );
  }
}

/// Google sign-in: a code to enter on the phone, then a WTV session. Connecting
/// WTW is a separate step, for people who already use WTW: signing in to WTW
/// with a new Google account would create a WTW account, and this app never
/// writes to WTW. The app frame is built again afterwards, so every screen
/// reads as the new user.
class _AccountSection extends StatefulWidget {
  const _AccountSection();

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  GoogleCode? _code;
  // Why a sign-in (or Connect WTW) failed, and why a sign-out did.
  String? _error;
  String? _signOutError;
  // Connect WTW asks first: WTW is read-only for this app, so nothing can check that the account exists.
  bool _confirmWtw = false;
  // A sign-in is under way. Cancel starts a new attempt number, which the old attempt sees.
  bool _busy = false;
  int _attempt = 0;
  // Set once the phone has approved: the sign-in then finishes whatever Cancel says.
  bool _finishing = false;
  // The focused button leaves the screen when the code appears or goes; the focus follows to the new one.
  final _startFocus = FocusNode();
  final _cancelFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // A WTW session left without a WTV one (an interrupted sign-out) is ended, not shown.
    if (services.session.email == null && services.wtw.email != null) _endWtw();
  }

  /// Best effort: a keyring that refuses leaves the WTW session, which the next start ends.
  Future<void> _endWtw() async {
    try {
      await services.wtw.signOut();
    } on ApiException catch (e) {
      debugPrint('Ending the WTW session failed: ${e.message}');
    }
  }

  @override
  void dispose() {
    // Ends the wait for the phone, unless it has approved already.
    _attempt++;
    _startFocus.dispose();
    _cancelFocus.dispose();
    super.dispose();
  }

  void _show(VoidCallback change, FocusNode focus) {
    if (!mounted) return;
    setState(change);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  /// Shows a code; once the phone approves, `signIn` runs with the ID token and the app frame is built again.
  Future<void> _start(Future<void> Function(String idToken) signIn) async {
    if (_busy) return;
    final attempt = ++_attempt;
    bool cancelled() => attempt != _attempt;
    setState(() {
      _busy = true;
      _error = null;
      // Every Connect WTW attempt is confirmed again, also after a cancel or an error.
      _confirmWtw = false;
    });
    try {
      final code = await services.google.start();
      if (cancelled()) return;
      _show(() => _code = code, _cancelFocus);
      final idToken = await services.google.awaitIdToken(code, cancelled: cancelled);
      if (idToken == null) return;
      _finishing = true;
      await signIn(idToken);
      appGeneration.value++;
    } on ApiException catch (e) {
      if (!cancelled()) {
        _show(() {
          _error = e.message;
          _code = null;
        }, _startFocus);
      }
    } finally {
      _finishing = false;
      if (!cancelled() && mounted) setState(() => _busy = false);
    }
  }

  void _cancel() {
    if (_finishing) return;
    _attempt++;
    _show(() {
      _code = null;
      _busy = false;
    }, _startFocus);
  }

  Future<void> _signOut() async {
    try {
      await services.session.signOut();
      await _endWtw();
      appGeneration.value++;
    } on ApiException catch (e) {
      // A refused sign-out changed nothing (see `Session.signOut`): the screens stay, with the reason.
      if (mounted) setState(() => _signOutError = e.message);
    }
  }

  Future<void> _disconnectWtw() async {
    try {
      await services.wtw.signOut();
      appGeneration.value++;
    } on ApiException catch (e) {
      if (mounted) setState(() => _signOutError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final secondary = text.bodyLarge!.copyWith(color: WtvColors.textSecondary);
    final note = text.bodyMedium!.copyWith(color: WtvColors.textSecondary);
    final email = services.session.email;
    final wtwEmail = services.wtw.email;
    final code = _code;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.settingAccount, style: text.titleMedium),
        const SizedBox(height: 12),
        if (code != null)
          Row(
            spacing: 24,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.signInCode(code.url.replaceFirst('https://', '').replaceFirst('www.', '')), style: secondary),
                    // Latin letters: read left to right in Hebrew too.
                    Text(
                      code.userCode,
                      textDirection: TextDirection.ltr,
                      style: text.displaySmall!.copyWith(color: WtvColors.accent),
                    ),
                  ],
                ),
              ),
              ActionButton(label: l.cancel, focusNode: _cancelFocus, onPressed: _cancel),
            ],
          )
        else if (email == null)
          Row(
            spacing: 16,
            children: [
              ActionButton(
                label: l.signInGoogle,
                focusNode: _startFocus,
                onPressed: () => _start((idToken) => services.session.signInWithGoogle(idToken, link: true)),
              ),
              Flexible(child: Text(_error == null ? l.accountSignedOut : l.signInFailed(_error!), style: secondary)),
            ],
          )
        else ...[
          Row(
            children: [
              Text(l.signedIn, style: secondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(email, textDirection: TextDirection.ltr, style: text.bodyLarge),
              ),
              const SizedBox(width: 24),
              ActionButton(label: l.signOut, onPressed: _signOut),
              if (_signOutError != null) ...[const SizedBox(width: 16), Flexible(child: Text(_signOutError!, style: secondary))],
            ],
          ),
          const SizedBox(height: 10),
          if (wtwEmail != null)
            Row(
              spacing: 24,
              children: [
                Flexible(child: Text(l.wtwConnected(wtwEmail), style: note)),
                ActionButton(label: l.signOutWtw, onPressed: _disconnectWtw),
              ],
            )
          else
            Row(
              spacing: 16,
              children: [
                ActionButton(
                  label: _confirmWtw ? l.connectWtwConfirm : l.connectWtw,
                  focusNode: _startFocus,
                  onPressed: () => _confirmWtw ? _start((idToken) => services.wtw.signInWithGoogle(idToken, link: false)) : setState(() => _confirmWtw = true),
                ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.connectWtwHint, style: note),
                      if (_error != null) Text(l.signInFailed(_error!), style: note),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

/// The radio switch, and what is hidden on the Live TV page; selecting a hidden item shows it again.
class _LiveSection extends StatefulWidget {
  const _LiveSection();

  @override
  State<_LiveSection> createState() => _LiveSectionState();
}

class _LiveSectionState extends State<_LiveSection> {
  LiveFilters? _filters;
  String? _failed;
  // Names for the hidden items are a nicety; the switch needs only the filters.
  var _channels = const <Channel>[];
  var _categories = const <LiveCategory>[];
  // A chip that goes takes the focus with it: it moves first to a neighbour, or the radio switch.
  final _radio = FocusNode();
  final _chips = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _radio.dispose();
    for (final node in _chips.values) {
      node.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final catalog = services.catalog;
    try {
      final filters = await catalog.liveFilters();
      if (mounted) setState(() => _filters = filters);
    } on Exception catch (e) {
      if (mounted) setState(() => _failed = e is ApiException ? e.message : e.toString());
    }
    try {
      final (channels, categories) = await (catalog.channels(), catalog.liveCategories()).wait;
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _categories = categories;
      });
    } on Exception {
      // The hidden items then show no names.
    } on ParallelWaitError {
      // The same.
    }
  }

  /// Saved at once. A failed save undoes only its own change: others may have been made meanwhile.
  Future<void> _change(LiveFilters Function(LiveFilters) apply, LiveFilters Function(LiveFilters) undo, Future<void> Function() save) async {
    setState(() => _filters = apply(_filters!));
    try {
      await save();
    } on Exception {
      if (mounted) setState(() => _filters = undo(_filters!));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final hebrew = isHebrew(context);
    final catalog = services.catalog;
    final label = text.bodyLarge!.copyWith(color: WtvColors.textSecondary);
    final muted = text.bodyMedium!.copyWith(color: WtvColors.textMuted);
    final f = _filters;
    final heading = Text(l.settingLive, style: text.titleMedium);
    if (f == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          heading,
          const SizedBox(height: 12),
          if (_failed != null) Text(l.loadFailed(_failed!), style: muted),
        ],
      );
    }
    final groups = [
      for (final c in _categories)
        if (f.hiddenGroups.contains(c.id)) c,
    ];
    final channels = [
      for (final c in _channels)
        if (f.hiddenChannels.contains(c.id)) c,
    ];
    final keys = [for (final c in groups) 'g${c.id}', for (final c in channels) 'c${c.id}'];
    FocusNode node(String key) => _chips.putIfAbsent(key, FocusNode.new);
    void leave(String key) {
      final i = keys.indexOf(key);
      final next = i + 1 < keys.length ? keys[i + 1] : (i > 0 ? keys[i - 1] : null);
      (next == null ? _radio : node(next)).requestFocus();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        heading,
        const SizedBox(height: 12),
        Row(
          spacing: 10,
          children: [
            SizedBox(width: 130, child: Text(l.settingRadio, style: label)),
            for (final on in const [true, false])
              OptionChip(
                selected: f.showRadio == on,
                focusNode: on ? _radio : null,
                label: on ? l.settingOn : l.settingOff,
                onPressed: () {
                  if (f.showRadio == on) return;
                  _change((f) => f.copyWith(showRadio: on), (f) => f.copyWith(showRadio: !on), () => catalog.setShowRadio(on));
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(width: 140, child: Text(l.settingHidden, style: label)),
            if (keys.isEmpty)
              Text(l.settingHiddenNone, style: muted)
            else
              Expanded(
                child: SizedBox(
                  // A chip's height.
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsetsDirectional.only(end: 48),
                    children: [
                      for (final c in groups)
                        Padding(
                          key: ValueKey('g${c.id}'),
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: OptionChip(
                            selected: false,
                            focusNode: node('g${c.id}'),
                            label: c.label(hebrew: hebrew),
                            onPressed: () {
                              leave('g${c.id}');
                              _change(
                                (f) => f.copyWith(hiddenGroups: {...f.hiddenGroups}..remove(c.id)),
                                (f) => f.copyWith(hiddenGroups: {...f.hiddenGroups, c.id}),
                                () => catalog.setGroupHidden(c.id, false),
                              );
                            },
                          ),
                        ),
                      for (final c in channels)
                        Padding(
                          key: ValueKey('c${c.id}'),
                          padding: const EdgeInsetsDirectional.only(end: 10),
                          child: OptionChip(
                            selected: false,
                            focusNode: node('c${c.id}'),
                            label: c.name,
                            onPressed: () {
                              leave('c${c.id}');
                              _change(
                                (f) => f.copyWith(hiddenChannels: {...f.hiddenChannels}..remove(c.id)),
                                (f) => f.copyWith(hiddenChannels: {...f.hiddenChannels, c.id}),
                                () => catalog.setChannelHidden(c.id, false),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 140, top: 4),
          child: Text(l.settingHiddenHint, style: text.bodySmall!.copyWith(color: WtvColors.textMuted)),
        ),
      ],
    );
  }
}

enum _Saved { yes, incomplete, failed }

/// Server, user name and password of the provider, kept in the system keyring.
/// Closed behind Edit once saved; open when there is no login yet, or when Play sent the user here.
class _ProviderSection extends StatefulWidget {
  const _ProviderSection({this.focus});

  /// The page's first focus, when the page opens on the login.
  final FocusNode? focus;

  @override
  State<_ProviderSection> createState() => _ProviderSectionState();
}

class _ProviderSectionState extends State<_ProviderSection> {
  final ProviderLogin? _stored = services.provider.login;
  late final _server = TextEditingController(text: _stored?.server ?? '');
  late final _user = TextEditingController(text: _stored?.user ?? '');
  late final _password = TextEditingController(text: _stored?.password ?? '');
  late var _editing = widget.focus != null || !(_stored?.isComplete ?? false);
  // Null: nothing to say; else the message after Save.
  _Saved? _result;
  final _edit = FocusNode();
  final _ownField = FocusNode();

  FocusNode get _firstField => widget.focus ?? _ownField;

  @override
  void dispose() {
    _server.dispose();
    _user.dispose();
    _password.dispose();
    _edit.dispose();
    _ownField.dispose();
    super.dispose();
  }

  void _show(VoidCallback change, FocusNode focus) {
    setState(change);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  Future<void> _save() async {
    final login = ProviderLogin(_server.text, _user.text, _password.text);
    final result = !login.isComplete
        ? _Saved.incomplete
        : await services.provider.save(login)
        ? _Saved.yes
        : _Saved.failed;
    if (!mounted) return;
    if (result == _Saved.yes) {
      // Save closes the fields under the focus: Edit takes it.
      _show(() {
        _result = result;
        _editing = false;
      }, _edit);
    } else {
      setState(() => _result = result);
    }
  }

  void _typed(String _) {
    if (_result != null) setState(() => _result = null);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final heading = Text(l.settingProvider, style: text.titleMedium);
    if (!_editing) {
      return Row(
        children: [
          heading,
          const SizedBox(width: 24),
          ActionButton(
            label: l.edit,
            focusNode: _edit,
            onPressed: () => _show(() {
              _result = null;
              _editing = true;
            }, _firstField),
          ),
          if (_result == _Saved.yes) ...[const SizedBox(width: 16), Text(l.saved, style: text.bodyMedium!.copyWith(color: WtvColors.accent))],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 10,
      children: [
        Padding(padding: const EdgeInsets.only(bottom: 2), child: heading),
        _SettingField(l.providerServer, _server, focusNode: _firstField, onChanged: _typed),
        _SettingField(l.providerUser, _user, onChanged: _typed),
        _SettingField(l.providerPassword, _password, secret: true, onChanged: _typed),
        Row(
          spacing: 16,
          children: [
            ActionButton(label: l.save, onPressed: _save),
            if (_result != null)
              Text(switch (_result!) {
                _Saved.yes => l.saved,
                _Saved.incomplete => l.providerIncomplete,
                _Saved.failed => l.providerSaveFailed,
              }, style: text.bodyMedium!.copyWith(color: WtvColors.textSecondary)),
          ],
        ),
      ],
    );
  }
}

/// A labelled one-line text field. Up and Down move between the fields; Enter goes to the next one (or Save).
class _SettingField extends StatelessWidget {
  const _SettingField(this.label, this.controller, {this.focusNode, this.secret = false, required this.onChanged});

  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool secret;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: text.bodyLarge!.copyWith(color: WtvColors.textSecondary)),
        ),
        SizedBox(
          width: 420,
          child: FieldKeys(
            controller: controller,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: secret,
              autocorrect: false,
              enableSuggestions: false,
              // An address, a name, a password: read left to right in Hebrew too.
              textDirection: TextDirection.ltr,
              style: text.bodyLarge!.copyWith(color: WtvColors.textPrimary),
              cursorColor: WtvColors.textPrimary,
              textInputAction: TextInputAction.next,
              // Back in a field the text is typed on, not replaced.
              selectAllOnFocus: false,
              onChanged: onChanged,
              onEditingComplete: () {},
              onSubmitted: (_) => Actions.invoke(context, const DirectionalFocusIntent(TraversalDirection.down)),
              // A click on the page's background leaves the focus where it is.
              onTapOutside: (_) {},
              decoration: fieldDecoration(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
            ),
          ),
        ),
      ],
    );
  }
}

/// TMDB's required credit (logo and notice) and the app version. It takes the focus so the arrow keys can scroll it into view.
class _AboutSection extends StatefulWidget {
  const _AboutSection();

  @override
  State<_AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<_AboutSection> {
  var _focused = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final secondary = text.bodyMedium!.copyWith(color: WtvColors.textSecondary);
    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _focused ? WtvColors.textPrimary : Colors.transparent, width: 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l.settingAbout, style: text.titleMedium!.copyWith(color: WtvColors.textSecondary)),
            ),
            Image.asset('assets/tmdb_logo.png', height: 20, semanticLabel: 'TMDB'),
            Text(l.aboutTmdb, style: secondary),
            Text(l.aboutVersion(appVersion), style: secondary),
          ],
        ),
      ),
    );
  }
}
