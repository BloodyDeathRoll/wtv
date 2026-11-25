import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The system keyring: libsecret on Linux, the login keychain on a Mac.
/// On a Mac the newer "data protection" keychain needs an Apple provisioning profile,
/// which an unsigned build has none of; the login keychain needs nothing.
const keyring = FlutterSecureStorage(mOptions: MacOsOptions(usesDataProtectionKeychain: false));
