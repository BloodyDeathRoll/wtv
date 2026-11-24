import 'dart:convert';

/// A JSON object and a JSON array, as `jsonDecode` gives them.
typedef JsonObject = Map<String, Object?>;
typedef JsonArray = List<Object?>;

/// `text` as a JSON object; a [FormatException] when it is not one.
JsonObject jsonObject(String text) => switch (jsonDecode(text)) {
  final JsonObject object => object,
  _ => throw const FormatException('Not a JSON object'),
};

/// The reads of Android's `org.json` that the TV app's code is written with,
/// with its rules: a number is also read from text that holds one, text from
/// any value (a JSON null is the text "null"), a `get` of a missing or
/// unreadable value throws (here a [FormatException]) and an `opt` gives a
/// fallback instead.
extension JsonObjectReads on JsonObject {
  /// True for a missing key and for a JSON null.
  bool isNull(String key) => this[key] == null;

  int getInt(String key) => _int(this[key]) ?? (throw FormatException('No number at $key'));

  double getDouble(String key) => _number(this[key])?.toDouble() ?? (throw FormatException('No number at $key'));

  String getString(String key) => containsKey(key) ? _text(this[key]) : throw FormatException('No value for $key');

  JsonObject getObject(String key) => optObject(key) ?? (throw FormatException('No object at $key'));

  int optInt(String key) => _int(this[key]) ?? 0;

  bool optBoolean(String key, [bool fallback = false]) => switch (this[key]) {
    final bool value => value,
    final String value when value.toLowerCase() == 'true' => true,
    final String value when value.toLowerCase() == 'false' => false,
    _ => fallback,
  };

  String optString(String key) => containsKey(key) ? _text(this[key]) : '';

  JsonObject? optObject(String key) => switch (this[key]) {
    final JsonObject value => value,
    _ => null,
  };

  JsonArray? optArray(String key) => switch (this[key]) {
    final JsonArray value => value,
    _ => null,
  };
}

extension JsonArrayReads on JsonArray {
  /// Every element as a whole number.
  List<int> ints() => [for (final value in this) _int(value) ?? (throw const FormatException('Not a number'))];
}

num? _number(Object? value) => switch (value) {
  final num number => number,
  final String text => double.tryParse(text),
  _ => null,
};

// "NaN" and "Infinity" are no whole number: `toInt` on them throws an Error, which no `on Exception` catches.
int? _int(Object? value) => switch (_number(value)) {
  final num number when number.isFinite => number.toInt(),
  _ => null,
};

String _text(Object? value) => value is String ? value : jsonEncode(value);
