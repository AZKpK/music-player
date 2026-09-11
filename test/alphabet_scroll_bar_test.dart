// Unit test za `buildAlphabetIndex`/`alphabetLetterFor` (Faza 7.5, P0/N3 -
// A-Z hitro drsenje). Testira samo čisto funkcijo, glej `alphabet_scroll_bar.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/shared/widgets/alphabet_scroll_bar.dart';

void main() {
  group('alphabetLetterFor', () {
    test('vrne veliko ASCII črko za normalen naslov', () {
      expect(alphabetLetterFor('Mr. Brightside'), 'M');
      expect(alphabetLetterFor('take me out'), 'T');
    });

    test('vrne # za prazno vrednost', () {
      expect(alphabetLetterFor(''), '#');
      expect(alphabetLetterFor('   '), '#');
    });

    test('vrne # za vrednost, ki se začne s številko', () {
      expect(alphabetLetterFor('2step'), '#');
    });

    test('vrne # za ne-ASCII začetnico (npr. šumnik)', () {
      expect(alphabetLetterFor('Črna kronika'), '#');
    });
  });

  group('buildAlphabetIndex', () {
    test('poveže vsako oznako z indeksom prvega elementa s to oznako', () {
      final items = ['Alfa', 'Ana', 'Beta', 'Cyan', '2step', ''];
      final index = buildAlphabetIndex(items, (item) => item);

      expect(index, {'A': 0, 'B': 2, 'C': 3, '#': 4});
    });

    test('prazen seznam vrne prazen indeks', () {
      expect(buildAlphabetIndex(<String>[], (item) => item), isEmpty);
    });
  });
}
