import 'package:flutter_test/flutter_test.dart';
import 'package:wtv/data/catalog.dart';
import 'package:wtv/data/json.dart';

void main() {
  // The TV app reads JSON with Android's org.json: these are its rules.
  final JsonObject o = {
    'n': 5,
    'd': 7.9,
    's': '12',
    'none': null,
    'blank': ' ',
    'yes': 'TRUE',
    'list': [1, '2', 3.0],
    'object': {'a': 1},
  };

  test('a missing value and a JSON null are both null', () {
    expect((o.isNull('none'), o.isNull('missing'), o.isNull('n')), (true, true, false));
  });

  test('a number is read from a number or from text that holds one; without one, get throws and opt gives 0', () {
    expect((o.getInt('n'), o.getInt('d'), o.getInt('s'), o.getDouble('n'), o.getDouble('s')), (5, 7, 12, 5.0, 12.0));
    for (final key in ['missing', 'none', 'blank', 'object']) {
      expect(() => o.getInt(key), throwsFormatException, reason: key);
      expect(() => o.getDouble(key), throwsFormatException, reason: key);
      expect(o.optInt(key), 0, reason: key);
    }
    expect(o.optInt('s'), 12);
    // Text that is a number but no whole one.
    for (final text in ['NaN', 'Infinity', '-Infinity']) {
      expect(() => {'x': text}.getInt('x'), throwsFormatException, reason: text);
      expect({'x': text}.optInt('x'), 0, reason: text);
    }
    expect(o.optArray('list')!.ints(), [1, 2, 3]);
    expect(() => ['x'].ints(), throwsFormatException);
  });

  test('text is read from any value, a JSON null as "null"; only a missing one throws or is empty', () {
    expect((o.getString('s'), o.getString('n'), o.getString('none'), o.getString('object')), ('12', '5', 'null', '{"a":1}'));
    expect(() => o.getString('missing'), throwsFormatException);
    expect((o.optString('missing'), o.optString('none'), o.optString('blank')), ('', 'null', ' '));
  });

  test('text for the app is null when missing, null or blank', () {
    expect((o.text('missing'), o.text('none'), o.text('blank'), o.text('s'), o.text('n')), (null, null, null, '12', '5'));
  });

  test('a flag is read from a flag or the words true and false, else the fallback', () {
    expect((o.optBoolean('yes'), o.optBoolean('missing'), o.optBoolean('missing', true), o.optBoolean('n', true)), (true, false, true, true));
    expect({'f': 'False'}.optBoolean('f', true), isFalse);
  });

  test('objects and lists are read only from objects and lists', () {
    expect(o.optObject('object'), {'a': 1});
    expect((o.optObject('list'), o.optObject('missing'), o.optArray('object')), (null, null, null));
    expect(o.getObject('object'), {'a': 1});
    expect(() => o.getObject('n'), throwsFormatException);
    expect(jsonObject('{"a":1}'), {'a': 1});
    expect(() => jsonObject('[]'), throwsFormatException);
    expect(() => jsonObject('not json'), throwsFormatException);
  });
}
