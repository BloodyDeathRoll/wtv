import 'package:flutter_test/flutter_test.dart';
import 'package:wtv/data/provider_login.dart';

void main() {
  const login = ProviderLogin('provider.example:443/', 'user', 'p@ss word');

  test('movie, episode and live addresses, https by default, encoded credentials', () {
    expect(streamUrl(login, StreamKind.movie, 387982, 'mp4'), 'https://provider.example:443/movie/user/p%40ss%20word/387982.mp4');
    expect(streamUrl(login, StreamKind.episode, 369702, 'mkv'), 'https://provider.example:443/series/user/p%40ss%20word/369702.mkv');
    expect(streamUrl(login, StreamKind.live, 85956, null), 'https://provider.example:443/live/user/p%40ss%20word/85956.ts');
  });

  test('a server with a scheme keeps it', () {
    const http = ProviderLogin('http://p.example', 'u', 'p');
    expect(streamUrl(http, StreamKind.movie, 1, null), 'http://p.example/movie/u/p/1.mp4');
  });

  test('a path in the server is kept, any scheme case', () {
    const path = ProviderLogin('p.example/xtream/', 'u', 'p');
    expect(streamUrl(path, StreamKind.movie, 1, 'mkv'), 'https://p.example/xtream/movie/u/p/1.mkv');
    const upper = ProviderLogin('HTTP://p.example', 'u', 'p');
    expect(streamUrl(upper, StreamKind.live, 2, null), 'HTTP://p.example/live/u/p/2.ts');
  });

  test('the password is sent exactly as saved, spaces included', () {
    const spaces = ProviderLogin('p.example', ' u ', ' pw ');
    expect(streamUrl(spaces, StreamKind.movie, 1, null), 'https://p.example/movie/u/%20pw%20/1.mp4');
  });

  test('a login with an empty field is not complete', () {
    expect(const ProviderLogin('p.example', 'u', ' ').isComplete, isFalse);
  });
}
