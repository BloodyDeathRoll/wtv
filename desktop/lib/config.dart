/// The app's own keys, set at build time from a git-ignored file
/// (`--dart-define-from-file=.env`, see the README). Empty in a build without one.
library;

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
const googleClientId = String.fromEnvironment('GOOGLE_TV_CLIENT_ID');

/// Not a real secret: Google's device flow has every app carry it, as the TV app's build does.
const googleClientSecret = String.fromEnvironment('GOOGLE_TV_CLIENT_SECRET');
