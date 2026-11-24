import 'epg.dart';

/// The Xtream provider login, typed in Settings and kept on this device only.
class ProviderLogin {
  const ProviderLogin(this.server, this.user, this.password);

  final String server;
  final String user;
  final String password;

  bool get isComplete => server.trim().isNotEmpty && user.trim().isNotEmpty && password.trim().isNotEmpty;
}

/// What to play: a movie copy, an episode, or (P5) a channel.
enum StreamKind {
  movie('movie'),
  episode('series'),
  live('live');

  const StreamKind(this.path);

  final String path;
}

/// The provider's stream URL: `<server>/<movie|series|live>/<user>/<password>/<id>.<ext>`.
/// A server without a scheme is https; user and password are path-encoded.
String streamUrl(ProviderLogin login, StreamKind kind, int extId, String? containerExt) {
  final server = serverBase(login);
  final blank = containerExt == null || containerExt.trim().isEmpty;
  final ext = blank ? (kind == StreamKind.live ? 'ts' : 'mp4') : containerExt;
  // The password is sent exactly as saved; the user name is trimmed, as on save.
  return '$server/${kind.path}/${_seg(login.user.trim())}/${_seg(login.password)}/$extId.$ext';
}

/// The server as saved, without a trailing slash; https when it names no scheme.
String serverBase(ProviderLogin login) {
  final server = login.server.trim().replaceFirst(RegExp(r'/+$'), '');
  return RegExp('^https?://', caseSensitive: false).hasMatch(server) ? server : 'https://$server';
}

/// A catch-up address for a past programme: `<server>/timeshift/<user>/<password>/<minutes>/<YYYY-MM-DD:HH-MM>/<id>.ts`.
/// The start is the provider's own text (its server's time), so no time zone is guessed. Null without it.
String? timeshiftUrl(ProviderLogin login, int streamId, Programme programme) {
  final parts = providerStartParts(programme.providerStart);
  if (parts == null) return null;
  final (day, hour, minute) = parts;
  final whole = (programme.end - programme.start + 59) ~/ 60;
  final minutes = whole < 1 ? 1 : whole;
  return '${serverBase(login)}/timeshift/${_seg(login.user.trim())}/${_seg(login.password)}/$minutes/$day:$hour-$minute/$streamId.ts';
}

/// Java's `URLEncoder.encode` with a space as `%20`: the addresses are the TV app's byte for byte.
String _seg(String text) =>
    Uri.encodeQueryComponent(text).replaceAll('+', '%20').replaceAll('%2A', '*').replaceAll('~', '%7E');
