import 'dart:math';

import 'package:open_iptv/core/models/channel.dart';
import 'package:open_iptv/core/models/movie.dart';
import 'package:open_iptv/core/models/profile.dart';
import 'package:open_iptv/core/services/parental_service.dart';
import 'package:open_iptv/core/storage/preferences.dart';

bool isSportsChannel(Channel channel) {
  final categories = channel.categories.join(' ').toLowerCase();
  return RegExp(
        r'\b(sports?|football|soccer|basketball|baseball|hockey|cricket|'
        r'rugby|golf|tennis|motorsports?|racing|wrestling|boxing|mma)\b',
      ).hasMatch(categories) ||
      RegExp(
        r'\b(espn|nfl|nba|nhl|mlb|ufc|bein)\b',
        caseSensitive: false,
      ).hasMatch(channel.name);
}

bool canDiscover({
  required String sourceId,
  required String? genre,
  required Profile? profile,
  required AppPreferences? preferences,
  required Set<String> unlocked,
}) {
  // Wait for the active profile before showing any recommendations.
  if (profile == null || preferences == null) return false;
  if (profile.sourceIds.isNotEmpty && !profile.sourceIds.contains(sourceId)) {
    return false;
  }
  final genres = splitGenres(genre);
  if (genres.any(profile.hiddenCategories.contains)) return false;
  if (profile.isKidsProfile && isAdultGenre(genre)) return false;
  return !isGenreLocked(genre, preferences, unlocked);
}

List<Movie> recentReleases(List<Movie> movies, {required int currentYear}) {
  return movies.where((movie) {
    final year = int.tryParse(movie.year ?? '');
    return year != null && year >= currentYear - 1 && year <= currentYear;
  }).toList()
    ..sort((a, b) => b.year!.compareTo(a.year!));
}

List<Movie> recommendedMovies(List<Movie> visible, Set<String> favorites) {
  final preferred = <String>{};
  for (final movie in visible) {
    if (favorites.contains(movie.id) || movie.isInProgress || movie.isWatched) {
      preferred.addAll(splitGenres(movie.genre));
    }
  }
  int score(Movie movie) =>
      splitGenres(movie.genre).where(preferred.contains).length;
  return visible.where((m) => !m.isWatched && !m.isInProgress).toList()
    ..sort((a, b) {
      final affinity = score(b).compareTo(score(a));
      if (affinity != 0) return affinity;
      final year = (int.tryParse(b.year ?? '') ?? 0).compareTo(
        int.tryParse(a.year ?? '') ?? 0,
      );
      return year != 0 ? year : a.title.compareTo(b.title);
    });
}

Movie? randomMovie(List<Movie> visible, Random random) =>
    visible.isEmpty ? null : visible[random.nextInt(visible.length)];
