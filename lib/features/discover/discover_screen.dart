import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_iptv/core/models/movie.dart';
import 'package:open_iptv/core/models/series.dart';
import 'package:open_iptv/core/providers/channel_providers.dart';
import 'package:open_iptv/core/providers/theme_providers.dart';
import 'package:open_iptv/core/services/parental_service.dart';
import 'package:open_iptv/core/services/profile_service.dart';
import 'package:open_iptv/core/services/streaming_apps.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/features/discover/discovery.dart';
import 'package:open_iptv/shared/widgets/media_rail.dart';
import 'package:open_iptv/shared/widgets/tv_focusable.dart';
import 'package:open_iptv/ui/platform_helper.dart';

final _moviesProvider = StreamProvider<List<Movie>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final source = ref.watch(activeSourceIdProvider);
  final profile = ref.watch(activeProfileIdProvider);
  return source == null
      ? db.watchAllMovies(profileId: profile)
      : db.watchMoviesForSource(source, profileId: profile);
});

final _seriesProvider = StreamProvider<List<Series>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final source = ref.watch(activeSourceIdProvider);
  return source == null ? db.watchAllSeries() : db.watchSeriesForSource(source);
});

class DiscoverScreen extends ConsumerWidget {
  const DiscoverScreen({super.key});

  Future<void> _openApp(BuildContext context, StreamingApp app) async {
    try {
      await StreamingApps.open(app);
    } on PlatformException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This streaming app could not be opened.'),
          ),
        );
      }
    } on MissingPluginException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Open streaming apps on your Fire TV.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final prefs = ref.watch(appPreferencesProvider).valueOrNull;
    final unlocked = ref.watch(parentalSessionUnlockedProvider);
    bool visible(String sourceId, String? genre) => canDiscover(
          sourceId: sourceId,
          genre: genre,
          profile: profile,
          preferences: prefs,
          unlocked: unlocked,
        );
    final movieState = ref.watch(_moviesProvider);
    final seriesState = ref.watch(_seriesProvider);
    final channelState = ref.watch(allChannelsProvider);
    final movies = (movieState.valueOrNull ?? [])
        .where((m) => visible(m.sourceId, m.genre))
        .toList();
    final series = (seriesState.valueOrNull ?? [])
        .where((s) => visible(s.sourceId, s.genre))
        .toList();
    final channels = (channelState.valueOrNull ?? [])
        .where((c) => visible(c.sourceId, c.groupTitle))
        .toList();
    final sports = channels.where(isSportsChannel).toList();
    final recommended = recommendedMovies(
      movies,
      (profile?.favoriteMovieIds ?? []).toSet(),
    );
    final releases = recentReleases(movies, currentYear: DateTime.now().year);
    final loading =
        movieState.isLoading || seriesState.isLoading || profile == null;
    final failed =
        movieState.hasError || seriesState.hasError || channelState.hasError;
    void movie(Movie m) => context.push('/movies/${m.id}');
    final isTV = PlatformHelper.isTV(context);

    Widget movieRail(String title, List<Movie> list) => MediaRail(
          title: title,
          items: list
              .take(20)
              .map(
                (m) => RailItem(
                  title: m.title,
                  subtitle: m.year,
                  imageUrl: m.posterUrl,
                  progress: m.isInProgress ? m.watchProgress : null,
                  onTap: () => movie(m),
                ),
              )
              .toList(),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('fire-iptv'),
        actions: [
          TextButton.icon(
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search),
            label: const Text('Search'),
          ),
          if (profile?.isAdmin == true)
            TextButton.icon(
              onPressed: () => context.push('/onboarding'),
              icon: const Icon(Icons.add),
              label: const Text('Add provider'),
            ),
          const SizedBox(width: 16),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find your next favorite.',
                  style: Theme.of(context)
                      .textTheme
                      .headlineLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Live channels, a proper guide, and your movies and shows.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _Tile(
                      title: 'TV guide',
                      subtitle: '${channels.length} live channels',
                      icon: Icons.calendar_view_week,
                      autofocus: true,
                      onTap: () => context.go('/live'),
                    ),
                    _Tile(
                      title: 'All sports',
                      subtitle: '${sports.length} sports channels',
                      icon: Icons.sports,
                      onTap: () => context.go('/sports'),
                    ),
                    if (movies.isNotEmpty)
                      _Tile(
                        title: 'Surprise me',
                        subtitle: 'Pick from your movie library',
                        icon: Icons.shuffle,
                        onTap: () {
                          final selected = randomMovie(movies, Random());
                          if (selected != null) movie(selected);
                        },
                      ),
                    _Tile(
                      title: movies.isEmpty &&
                              series.isEmpty &&
                              profile?.isAdmin == true
                          ? 'Add movies & shows'
                          : 'Movies & shows',
                      subtitle: movies.isEmpty &&
                              series.isEmpty &&
                              profile?.isAdmin == true
                          ? 'Connect your provider'
                          : '${movies.length} movies · ${series.length} series',
                      icon: Icons.movie_outlined,
                      onTap: () => movies.isEmpty &&
                              series.isEmpty &&
                              profile?.isAdmin == true
                          ? context.push('/onboarding')
                          : context.go('/movies'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (failed)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The library could not be loaded. Check your sources in Settings.',
              ),
            ),
          if (loading) const LinearProgressIndicator(),
          if (!loading && !failed && movies.isEmpty && series.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                profile.isAdmin
                    ? 'Want on-demand movies and shows? Add a provider with a movie and series library. The free starter channels supply live TV.'
                    : 'Your selected source has no on-demand movies or shows. Ask your profile administrator to add a provider.',
              ),
            ),
          if (isTV &&
              profile != null &&
              profile.isAdmin &&
              !profile.isKidsProfile)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'More movies & shows',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Open the streaming app to browse its own catalog.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _Tile(
                        title: 'Tubi',
                        subtitle: 'Free movies, shows & live TV',
                        icon: Icons.play_circle_outline,
                        onTap: () => _openApp(context, StreamingApp.tubi),
                      ),
                      _Tile(
                        title: 'Plex',
                        subtitle: 'Movies, shows & your media',
                        icon: Icons.video_library_outlined,
                        onTap: () => _openApp(context, StreamingApp.plex),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (movies.any((m) => m.isInProgress))
            movieRail(
              'Continue watching',
              movies.where((m) => m.isInProgress).toList(),
            ),
          if (releases.isNotEmpty) movieRail('New releases', releases),
          if (recommended.isNotEmpty)
            movieRail('Recommended for you', recommended),
          if (series.isNotEmpty)
            MediaRail(
              title: 'Explore shows',
              onSeeAll: () => context.go('/series'),
              items: series
                  .take(20)
                  .map(
                    (s) => RailItem(
                      title: s.title,
                      subtitle: s.year,
                      imageUrl: s.posterUrl,
                      onTap: () => context.push('/series/${s.id}'),
                    ),
                  )
                  .toList(),
            ),
          if (sports.isNotEmpty)
            MediaRail(
              title: 'Sports, every day',
              shape: RailShape.logo,
              onSeeAll: () => context.go('/sports'),
              items: sports
                  .take(20)
                  .map(
                    (c) => RailItem(
                      title: c.name,
                      imageUrl: c.logoUrl,
                      subtitle: c.categories.last,
                      onTap: () => context.push(
                        '/player',
                        extra: {
                          'streamUrl': c.streamUrl,
                          'title': c.name,
                          'contentId': c.id,
                          'contentType': 'live',
                        },
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.autofocus = false,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TvFocusable(
        onTap: onTap,
        autofocus: autofocus,
        ensureVisibleOnFocus: true,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Theme.of(context).colorScheme.outline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  color: Theme.of(context).colorScheme.primary, size: 30),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
}
