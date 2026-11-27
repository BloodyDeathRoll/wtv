import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'app_language.dart';
import 'data/api.dart';
import 'data/catalog.dart';
import 'config.dart' as config;
import 'data/google_sign_in.dart';
import 'data/provider_login.dart';
import 'data/session.dart';
import 'l10n/app_localizations.dart';
import 'services.dart';
import 'ui/theme.dart';
import 'ui/wtv_app.dart';
import 'window.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  watchFullScreen();
  final client = http.Client();
  final session = Session(client);
  services = Services(
    session: session,
    wtw: Session(
      client,
      name: 'wtw_session',
      url: config.wtwSupabaseUrl,
      key: config.wtwSupabaseKey,
      anonymous: false,
      settingNames: 'WTW_SUPABASE_URL, WTW_SUPABASE_ANON_KEY',
    ),
    google: GoogleSignIn(client),
    catalog: Catalog(Api(session, client)),
    provider: ProviderLoginStore(),
    http: client,
  );
  await loadLanguage();
  // So Settings knows who is signed in. A failure shows again, with its reason, at the first use of the session.
  // One try for both: a WTW session read without the WTV one would be ended by Settings as a leftover.
  try {
    await services.session.load();
    await services.wtw.load();
  } on ApiException catch (e) {
    debugPrint('Reading the session failed: $e');
  }
  await services.provider.load();
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
      builder: (context, child) => FullScreenKeys(child: DesignScale(child: child!)),
      // A new frame after sign-in or sign-out: back on the tabs, every screen read again.
      home: WtvShell(key: ValueKey(appGeneration.value)),
    ),
  );
}
