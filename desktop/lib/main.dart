import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'app_language.dart';
import 'data/google_sign_in.dart';
import 'data/session.dart';
import 'l10n/app_localizations.dart';
import 'services.dart';
import 'ui/theme.dart';
import 'ui/wtv_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final client = http.Client();
  services = Services(session: Session(client), google: GoogleSignIn(client));
  await loadLanguage();
  // So Settings knows who is signed in. A failure shows again, with its reason, at the first use of the session.
  try {
    await services.session.load();
  } on ApiException catch (e) {
    debugPrint('Reading the session failed: $e');
  }
  runApp(const WtvApp());
}

class WtvApp extends StatelessWidget {
  const WtvApp({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([appLanguage, appGeneration]),
    builder: (context, _) => MaterialApp(
      title: 'WTV',
      debugShowCheckedModeBanner: false,
      theme: wtvTheme,
      locale: appLanguage.value.locale,
      // The material package's own list: the generated one names the framework's older delegates.
      localizationsDelegates: const [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      // Around the navigator, so dialogs are scaled with the pages.
      builder: (context, child) => DesignScale(child: child!),
      // A new frame after sign-in or sign-out: back on the tabs, every screen read again.
      home: WtvShell(key: ValueKey(appGeneration.value)),
    ),
  );
}
