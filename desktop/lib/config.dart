/// The app's own keys, set at build time from a git-ignored file
/// (`--dart-define-from-file=.env`, see the README). Empty in a build without one.
library;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
/// WTW's database, read only for this app: the user's taste profile and ratings.
const wtwSupabaseUrl = String.fromEnvironment('WTW_SUPABASE_URL');
const wtwSupabaseKey = String.fromEnvironment('WTW_SUPABASE_ANON_KEY');
const googleClientId = String.fromEnvironment('GOOGLE_TV_CLIENT_ID');

/// Not a real secret: Google's device flow has every app carry it, as the TV app's build does.
const googleClientSecret = String.fromEnvironment('GOOGLE_TV_CLIENT_SECRET');

/// Shown in Settings → About. A test keeps it equal to the version in `pubspec.yaml`.
const appVersion = '0.1.0';
