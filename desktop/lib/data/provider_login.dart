import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'epg.dart';

/// The Xtream provider login, typed in Settings and kept on this device only.
class ProviderLogin {
  const ProviderLogin(this.server, this.user, this.password);

  final String server;
  final String user;
  final String password;

  bool get isComplete => server.trim().isNotEmpty && user.trim().isNotEmpty && password.trim().isNotEmpty;
}

/// Keeps the login in the system keyring (libsecret), as the session is: never in a file, never sent anywhere but to the provider.
class ProviderLoginStore {
  ProviderLoginStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;
  static const _key = 'provider_login';

  /// The saved login; null when there is none (or before [load]).
  ProviderLogin? get login => _login;
  ProviderLogin? _login;

  /// Reads the saved login, once at the start. One that cannot be read counts as none: Settings then asks for it.
  Future<void> load() async {
    try {
      final text = await _storage.read(key: _key);
      final json = text == null ? null : jsonDecode(text);
      if (json is! Map) return;
      String field(String name) => json[name] is String ? json[name] as String : '';
      _login = ProviderLogin(field('server'), field('user'), field('password'));
    } catch (_) {
      // Never printed: the error may quote the stored value.
    }
  }

  /// False if the keyring refused; nothing is stored then. Server and user name are trimmed, the password is kept as typed.
  Future<bool> save(ProviderLogin login) async {
    final trimmed = ProviderLogin(login.server.trim(), login.user.trim(), login.password);
    try {
      await _storage.write(
        key: _key,
        value: jsonEncode({'server': trimmed.server, 'user': trimmed.user, 'password': trimmed.password}),
      );
    } catch (_) {
      return false;
    }
    _login = trimmed;
    return true;
  }
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
