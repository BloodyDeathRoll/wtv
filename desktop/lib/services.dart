import 'package:flutter/foundation.dart';

import 'data/catalog.dart';
import 'data/google_sign_in.dart';
import 'data/provider_login.dart';
import 'data/session.dart';
import 'player/engine.dart';
import 'player/mpv_engine.dart';

/// The app-wide services (the TV app's `WtvApplication`).
class Services {
  Services({
    required this.session,
    required this.wtw,
    required this.google,
    required this.catalog,
    required this.provider,
    VideoEngine Function() engine = MpvEngine.new,
  }) : _newEngine = engine;

  final Session session;

  /// WTW is read-only for this app: its session only reads the user's taste profile and ratings.
  final Session wtw;
  final GoogleSignIn google;
  final Catalog catalog;
  final ProviderLoginStore provider;

  final VideoEngine Function() _newEngine;

  /// The one video engine, for films and Live TV. Started at the first play: the browse screens do not wait for it.
  late final VideoEngine engine = _newEngine();
}

/// Set once in `main`, before the app is shown.
late Services services;

/// Raised after sign-in and sign-out: the app frame is built again, so every screen reads as the new user.
final appGeneration = ValueNotifier(0);

/// Raised when a saved position changed (a player closed, a position was removed): Continue watching is read again.
final progressVersion = ValueNotifier(0);
