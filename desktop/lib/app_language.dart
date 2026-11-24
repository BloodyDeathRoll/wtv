import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app's language, chosen in Settings: English (the default) or Hebrew.
/// Menus and layout direction (Hebrew is right to left) follow it.
enum AppLanguage {
  english('en'),
  hebrew('he');

  const AppLanguage(this.tag);
  final String tag;

  Locale get locale => Locale(tag);

  /// The language for a stored tag; English for none or an unknown one.
  static AppLanguage fromTag(String? tag) => values.firstWhere((l) => l.tag == tag, orElse: () => english);
}

const _key = 'language';

/// The language in use; the app rebuilds when it changes.
final appLanguage = ValueNotifier(AppLanguage.english);

Future<void> loadLanguage() async =>
    appLanguage.value = AppLanguage.fromTag((await SharedPreferences.getInstance()).getString(_key));

Future<void> saveLanguage(AppLanguage language) async {
  appLanguage.value = language;
  await (await SharedPreferences.getInstance()).setString(_key, language.tag);
}
