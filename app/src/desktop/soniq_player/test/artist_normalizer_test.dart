import 'package:flutter_test/flutter_test.dart';

import 'package:soniq_player/metadata/artist_normalizer.dart';

void main() {
  group('ArtistNormalizer.key', () {
    test('keeps primary artist for ft/feat/featuring', () {
      expect(ArtistNormalizer.key('HEALTH ft. Sierra'), 'health');
      expect(ArtistNormalizer.key('HEALTH feat Sierra'), 'health');
      expect(ArtistNormalizer.key('HEALTH featuring Sierra'), 'health');
      expect(ArtistNormalizer.key('HEALTH (feat. Sierra)'), 'health');
    });

    test('keeps primary artist for separators', () {
      expect(ArtistNormalizer.key('HEALTH & Sierra'), 'health');
      expect(ArtistNormalizer.key('HEALTH x Sierra'), 'health');
      expect(ArtistNormalizer.key('HEALTH × Sierra'), 'health');
      expect(ArtistNormalizer.key('HEALTH, Sierra'), 'health');
      expect(ArtistNormalizer.key('HEALTH + Sierra'), 'health');
    });

    test('normalizes whitespace and casing', () {
      expect(ArtistNormalizer.key('  HeAlTh   ft.   Sierra  '), 'health');
    });

    test('empty stays empty', () {
      expect(ArtistNormalizer.key(null), '');
      expect(ArtistNormalizer.key(''), '');
      expect(ArtistNormalizer.key('   '), '');
    });

    test("doesn't split artist names that contain '/' like AC/DC", () {
      expect(ArtistNormalizer.key('AC/DC'), 'ac/dc');
      expect(ArtistNormalizer.primaryDisplay('AC/DC'), 'AC/DC');
    });

    test('splits on spaced slash separator', () {
      expect(ArtistNormalizer.key('A / B'), 'a');
      expect(ArtistNormalizer.primaryDisplay('A / B'), 'A');
    });
  });

  group('ArtistNormalizer.primaryDisplay', () {
    test('returns primary display portion', () {
      expect(ArtistNormalizer.primaryDisplay('HEALTH ft. Sierra'), 'HEALTH');
      expect(ArtistNormalizer.primaryDisplay('HEALTH & Sierra'), 'HEALTH');
      expect(ArtistNormalizer.primaryDisplay('  HEALTH   (feat. Sierra)  '), 'HEALTH');
    });
  });
}
