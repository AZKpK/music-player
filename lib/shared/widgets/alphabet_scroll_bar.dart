import 'package:flutter/material.dart';

/// Oznake abecednega traka: '#' za vse, kar se ne začne z A-Z, nato A-Z.
const List<String> kAlphabetScrollLabels = [
  '#',
  'A',
  'B',
  'C',
  'D',
  'E',
  'F',
  'G',
  'H',
  'I',
  'J',
  'K',
  'L',
  'M',
  'N',
  'O',
  'P',
  'Q',
  'R',
  'S',
  'T',
  'U',
  'V',
  'W',
  'X',
  'Y',
  'Z',
];

/// Za (že sortiran) `items` in `keyOf`, ki izlušči polje po katerem je
/// sortiran (npr. naslov/izvajalec/album pesmi), zgradi mapo
/// {oznaka -> indeks prvega elementa s to oznako}, glej [alphabetLetterFor]
/// za nabor možnih oznak. Čista funkcija (testabilna brez Flutter/platform
/// odvisnosti) - uporablja jo `_SongListView` (`library_screen.dart`) za
/// `ScrollController.jumpTo(index * itemExtent)`.
Map<String, int> buildAlphabetIndex<T>(
  List<T> items,
  String Function(T item) keyOf,
) {
  final index = <String, int>{};
  for (var i = 0; i < items.length; i++) {
    final letter = alphabetLetterFor(keyOf(items[i]));
    index.putIfAbsent(letter, () => i);
  }
  return index;
}

/// Oznaka za dano vrednost: velika ASCII črka A-Z, sicer '#' (števke, prazna
/// vrednost, ne-ASCII črke npr. šumniki/cirilica ...).
String alphabetLetterFor(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '#';
  final letter = trimmed[0].toUpperCase();
  final code = letter.codeUnitAt(0);
  final isAsciiUpper = code >= 65 && code <= 90; // 'A'..'Z'
  return isAsciiUpper ? letter : '#';
}

/// Interaktiven navpičen trak ob desnem robu seznama (tap + vertical-drag) -
/// skoči na `onLetterSelected(oznaka)`. Oznake brez elementov v trenutnem
/// seznamu (`availableLetters`) so prikazane zbledele in jih ni mogoče izbrati.
class AlphabetScrollBar extends StatelessWidget {
  const AlphabetScrollBar({
    super.key,
    required this.availableLetters,
    required this.onLetterSelected,
  });

  final Set<String> availableLetters;
  final ValueChanged<String> onLetterSelected;

  void _handleTouch(Offset localPosition, double height) {
    final itemExtent = height / kAlphabetScrollLabels.length;
    if (itemExtent <= 0) return;
    final rawIndex = (localPosition.dy / itemExtent).floor();
    final index = rawIndex.clamp(0, kAlphabetScrollLabels.length - 1);
    final letter = kAlphabetScrollLabels[index];
    if (availableLetters.contains(letter)) {
      onLetterSelected(letter);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (details) =>
              _handleTouch(details.localPosition, constraints.maxHeight),
          onVerticalDragStart: (details) =>
              _handleTouch(details.localPosition, constraints.maxHeight),
          onVerticalDragUpdate: (details) =>
              _handleTouch(details.localPosition, constraints.maxHeight),
          child: Container(
            width: 20,
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Column(
              children: [
                for (final letter in kAlphabetScrollLabels)
                  Expanded(
                    child: Center(
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: availableLetters.contains(letter)
                              ? theme.colorScheme.primary
                              : theme.disabledColor,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
