import 'package:flutter/foundation.dart';

import 'data/catalog.dart';
import 'data/google_sign_in.dart';
import 'data/session.dart';

/// The app-wide services (the TV app's `WtvApplication`).
class Services {
  Services({required this.session, required this.google, required this.catalog});

  final Session session;
  final GoogleSignIn google;
  final Catalog catalog;
}

/// Set once in `main`, before the app is shown.
late Services services;

/// Raised after sign-in and sign-out: the app frame is built again, so every screen reads as the new user.
final appGeneration = ValueNotifier(0);

/// Raised when a saved position changed (a player closed, a position was removed): Continue watching is read again.
final progressVersion = ValueNotifier(0);
