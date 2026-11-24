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

/// Reads the saved language. A settings file that cannot be read leaves English: it must not stop the app from starting.
Future<void> loadLanguage() async {
  try {
    appLanguage.value = AppLanguage.fromTag((await SharedPreferences.getInstance()).getString(_key));
  } catch (e) {
    debugPrint('Reading the saved language failed: $e');
  }
}

/// Switches the language at once and keeps it for the next start. A failed write leaves the switch in place for this run.
Future<void> saveLanguage(AppLanguage language) async {
  appLanguage.value = language;
  try {
    await (await SharedPreferences.getInstance()).setString(_key, language.tag);
  } catch (e) {
    debugPrint('Saving the language failed: $e');
  }
}
