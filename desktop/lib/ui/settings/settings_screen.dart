import 'package:material_ui/material_ui.dart';

import '../../app_language.dart';
import '../../data/google_sign_in.dart';
import '../../data/session.dart';
import '../../l10n/app_localizations.dart';
import '../../services.dart';
import '../components/buttons.dart';
import '../components/chips.dart';
import '../theme.dart';

/// Settings. For now the language and the account; the provider login, WTW and the rest come with their work packages.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.firstFocus});

  final FocusNode firstFocus;

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
    return SingleChildScrollView(
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
                  focusNode: language == _opened ? widget.firstFocus : null,
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
        ],
      ),
    );
  }
}

/// Google sign-in: a code to enter on the phone, then a WTV session. The app
/// frame is built again afterwards, so every screen reads as the new user.
class _AccountSection extends StatefulWidget {
  const _AccountSection();

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  GoogleCode? _code;
  String? _error;
  // A sign-in is under way. Cancel starts a new attempt number, which the old attempt sees.
  bool _busy = false;
  int _attempt = 0;
  // Set once the phone has approved: the sign-in then finishes whatever Cancel says.
  bool _finishing = false;
  // The focused button leaves the screen when the code appears or goes; the focus follows to the new one.
  final _startFocus = FocusNode();
  final _cancelFocus = FocusNode();

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

  Future<void> _signIn() async {
    if (_busy) return;
    final attempt = ++_attempt;
    bool cancelled() => attempt != _attempt;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final code = await services.google.start();
      if (cancelled()) return;
      _show(() => _code = code, _cancelFocus);
      final idToken = await services.google.awaitIdToken(code, cancelled: cancelled);
      if (idToken == null) return;
      _finishing = true;
      await services.session.signInWithGoogle(idToken, link: true);
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
      appGeneration.value++;
    } on ApiException catch (e) {
      // A refused sign-out changed nothing (see `Session.signOut`): the screens stay, with the reason.
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final secondary = text.bodyLarge!.copyWith(color: WtvColors.textSecondary);
    final email = services.session.email;
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
              ActionButton(label: l.signInGoogle, focusNode: _startFocus, onPressed: _signIn),
              Flexible(child: Text(_error == null ? l.accountSignedOut : l.signInFailed(_error!), style: secondary)),
            ],
          )
        else
          Row(
            children: [
              Text(l.signedIn, style: secondary),
              const SizedBox(width: 8),
              Flexible(child: Text(email, textDirection: TextDirection.ltr, style: text.bodyLarge)),
              const SizedBox(width: 24),
              ActionButton(label: l.signOut, onPressed: _signOut),
              if (_error != null) ...[const SizedBox(width: 16), Flexible(child: Text(_error!, style: secondary))],
            ],
          ),
      ],
    );
  }
}
