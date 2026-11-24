import 'package:material_ui/material_ui.dart';

import 'app_language.dart';
import 'l10n/app_localizations.dart';
import 'ui/theme.dart';
import 'ui/wtv_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadLanguage();
  runApp(const WtvApp());
}

class WtvApp extends StatelessWidget {
  const WtvApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: appLanguage,
    builder: (context, language, _) => MaterialApp(
      title: 'WTV',
      debugShowCheckedModeBanner: false,
      theme: wtvTheme,
      locale: language.locale,
      // The material package's own list: the generated one names the framework's older delegates.
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      // Around the navigator, so dialogs are scaled with the pages.
      builder: (context, child) => DesignScale(child: child!),
      home: const WtvShell(),
    ),
  );
}
