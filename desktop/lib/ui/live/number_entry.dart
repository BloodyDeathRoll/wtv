import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

const maxDigits = 4;

/// The number is taken this long after the last digit; at once at [maxDigits].
const numberWait = Duration(milliseconds: 1500);

/// "No channel 57" shows this long.
const missingFor = Duration(seconds: 2);

/// A channel number typed on the number keys (top row or keypad), as on a TV
/// box: the digits show at the top right ([NumberOverlay]), and the number is
/// taken [numberWait] after the last one. `onNumber` gets each number typed
/// and answers whether a channel has it; [missing] is one that none has,
/// shown briefly.
class NumberEntry extends ChangeNotifier {
  NumberEntry(this.onNumber);

  final bool Function(int number) onNumber;

  var digits = '';
  int? missing;
  Timer? _timer;

  /// Takes a number key; true when it was one.
  bool key(KeyEvent event) {
    final digit = _digits[event.logicalKey];
    if (digit == null) return false;
    // A held key adds its digit once.
    if (event is! KeyDownEvent) return true;
    if (digits.length < maxDigits) digits += '$digit';
    missing = null;
    _timer?.cancel();
    if (digits.length < maxDigits) {
      _timer = Timer(numberWait, _take);
      notifyListeners();
    } else {
      _take();
    }
    return true;
  }

  void _take() {
    final number = int.parse(digits);
    digits = '';
    if (!onNumber(number)) {
      missing = number;
      _timer = Timer(missingFor, () {
        missing = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

final _digits = {
  for (var d = 0; d < 10; d++) ...{
    LogicalKeyboardKey(LogicalKeyboardKey.digit0.keyId + d): d,
    LogicalKeyboardKey(LogicalKeyboardKey.numpad0.keyId + d): d,
  },
};

/// The digits being typed, or "No channel 57", big at the top right (in Hebrew too, like a TV's). Goes in a [Stack].
class NumberOverlay extends StatelessWidget {
  const NumberOverlay(this.entry, {super.key});

  final NumberEntry entry;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: entry,
    builder: (context, _) {
      final typing = entry.digits.isNotEmpty;
      final missing = entry.missing;
      if (!typing && missing == null) return const SizedBox.shrink();
      final text = Theme.of(context).textTheme;
      return Positioned(
        top: 40,
        right: 56,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xCC000000), borderRadius: BorderRadius.circular(8)),
          child: Text(
            typing ? entry.digits : AppLocalizations.of(context)!.liveNoChannel(missing!),
            style: typing ? text.displayMedium : text.titleLarge,
          ),
        ),
      );
    },
  );
}
