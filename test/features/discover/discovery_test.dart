import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_iptv/core/models/channel.dart';
import 'package:open_iptv/core/models/movie.dart';
import 'package:open_iptv/core/models/profile.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/features/discover/discovery.dart';
import 'package:shared_preferences/shared_preferences.dart';

Movie film(String id, String year, {String genre = 'Drama'}) => Movie(
      id: id,
      sourceId: 'provider',
      title: id,
      year: year,
      genre: genre,
      streamUrl: 'https://example.com/$id.mp4',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('recent releases use release years, never catalog order', () {
    final films = [
      film('Classic', '1940'),
      film('Recent', '2026'),
      film('Last year', '2025'),
      film('Future', '2027'),
      film('Unknown', ''),
    ];
    expect(recentReleases(films, currentYear: 2026).map((m) => m.id), [
      'Recent',
      'Last year',
    ]);
  });

  test('sports includes provider categories and major sports networks', () {
    Channel channel(String name, String genre) => Channel(
          id: name,
          sourceId: 's',
          name: name,
          groupTitle: genre,
          sortOrder: 0,
          streamUrl: 'https://example.com/live',
        );
    expect(isSportsChannel(channel('Match', 'Sports;Football')), isTrue);
    expect(isSportsChannel(channel('ESPN 2', 'USA')), isTrue);
    expect(isSportsChannel(channel('Cricket Live', 'Cricket')), isTrue);
    expect(isSportsChannel(channel('Cinema', 'Entertainment')), isFalse);
  });

  test(
    'discovery respects hidden, restricted, adult and unselected sources',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = AppPreferences(await SharedPreferences.getInstance());
      await prefs.setParentalProtectionEnabled(true);
      await prefs.setParentalLockedCategories(['Horror']);
      final profile = Profile(
        id: 'kid',
        name: 'Kid',
        avatarEmoji: 'K',
        isKidsProfile: true,
        sourceIds: ['allowed'],
        hiddenCategories: ['Drama'],
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );
      bool visible(
        String source,
        String genre, {
        Set<String> unlocked = const {},
      }) =>
          canDiscover(
            sourceId: source,
            genre: genre,
            profile: profile,
            preferences: prefs,
            unlocked: unlocked,
          );
      expect(visible('allowed', 'Comedy'), isTrue);
      expect(visible('other', 'Comedy'), isFalse);
      expect(visible('allowed', 'Drama;Comedy'), isFalse);
      expect(visible('allowed', 'Horror'), isFalse);
      expect(visible('allowed', 'Adult'), isFalse);
      expect(visible('allowed', 'Horror', unlocked: {'Horror'}), isTrue);
      expect(
        canDiscover(
          sourceId: 'allowed',
          genre: 'Comedy',
          profile: null,
          preferences: prefs,
          unlocked: {},
        ),
        isFalse,
      );
    },
  );

  test(
      'recommendations use favorites and random picks stay in the visible library',
      () {
    final films = [
      film('Favorite', '2020', genre: 'Comedy'),
      film('Drama', '2026'),
      film('Comedy', '2025', genre: 'Comedy'),
    ];
    expect(recommendedMovies(films, {'Favorite'}).first.id, 'Comedy');
    final random = Random(12);
    for (var i = 0; i < 30; i++) {
      expect(films, contains(randomMovie(films, random)));
    }
    expect(randomMovie([], random), isNull);
  });
}
