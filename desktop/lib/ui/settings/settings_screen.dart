import 'package:material_ui/material_ui.dart';

import '../../app_language.dart';
import '../../l10n/app_localizations.dart';
import '../components/chips.dart';
import '../theme.dart';

/// Settings. For now the language; the provider login, WTW and the account come with their work packages.
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
        ],
      ),
    );
  }
}
