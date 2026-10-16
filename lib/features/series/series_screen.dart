import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_iptv/features/player/cast_ui.dart';
import 'package:open_iptv/core/models/episode.dart';
import 'package:open_iptv/core/models/series.dart';
import 'package:open_iptv/core/services/profile_service.dart';
import 'package:open_iptv/core/providers/theme_providers.dart';
import 'package:open_iptv/core/services/parental_service.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/shared/theme/app_theme.dart';
import 'package:open_iptv/shared/utils/display_name.dart';
import 'package:open_iptv/shared/utils/genre_icons.dart';
import 'package:open_iptv/shared/widgets/app_logo.dart';
import 'package:open_iptv/shared/widgets/browse_app_bar_actions.dart';
import 'package:open_iptv/shared/widgets/category_tile.dart';
import 'package:open_iptv/shared/widgets/detail_header.dart';
import 'package:open_iptv/shared/widgets/empty_state_view.dart';
import 'package:open_iptv/shared/widgets/media_rail.dart';
import 'package:open_iptv/shared/widgets/error_state_view.dart';
import 'package:open_iptv/shared/widgets/parental_pin_dialog.dart';
import 'package:open_iptv/shared/widgets/poster_image.dart';
import 'package:open_iptv/shared/widgets/skeleton.dart';
import 'package:open_iptv/shared/widgets/star_button.dart';
import 'package:open_iptv/shared/widgets/tv_focusable.dart';
import 'package:open_iptv/shared/utils/pull_refresh.dart';
import 'package:open_iptv/ui/platform_helper.dart';

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

final _allSeriesProvider = StreamProvider<List<Series>>((ref) {
  final activeSourceId = ref.watch(activeSourceIdProvider);
  final db = ref.watch(appDatabaseProvider);
  if (activeSourceId != null) {
    return db.watchSeriesForSource(activeSourceId);
  }
  return db.watchAllSeries();
});

final _episodesInProgressProvider = StreamProvider<List<Episode>>((ref) {
  // Only the profile id matters here, so a favorite/watch-progress toggle
  // elsewhere (which invalidates activeProfileProvider) doesn't tear down
  // this stream.
  final profileId = ref.watch(activeProfileIdProvider);
  final db = ref.watch(appDatabaseProvider);
  if (profileId == null) return const Stream.empty();
  // Follow the active playlist, like the rest of the Series tab.
  final sourceId = ref.watch(activeSourceIdProvider);
  return db.watchEpisodesInProgress(profileId).map((eps) => sourceId == null
      ? eps
      : eps.where((e) => e.sourceId == sourceId).toList());
});

Future<void> _refreshSeries(BuildContext context, WidgetRef ref) async {
  try {
    await refreshBrowsedPlaylists(
        context, ref, (manager, s) => manager.refreshSeries(s));
  } finally {
    ref.invalidate(_allSeriesProvider);
    await ref.read(_allSeriesProvider.future);
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class SeriesScreen extends ConsumerStatefulWidget {
  const SeriesScreen({super.key});

  @override
  ConsumerState<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends ConsumerState<SeriesScreen> {
  Future<void> _tapGenre(String g) async {
    if (await ensureCategoryUnlocked(context, ref, g) && mounted) {
      unawaited(context.push('/series/genre/${Uri.encodeComponent(g)}'));
    }
  }

  List<String> _buildGenres(
      List<Series> all, Set<String> hidden, String sort) {
    final seen = <String>{};
    final genres = <String>[];
    for (final s in all) {
      for (final g in splitGenres(s.genre)) {
        if (g.isNotEmpty && !hidden.contains(g) && seen.add(g)) genres.add(g);
      }
    }
    if (sort == 'az') genres.sort();
    return genres;
  }

  // Poster view: one rail per genre with its first [_railLength] titles.
  static const _railLength = 20;

  /// The first [_railLength] visible series of each genre, in [genres] order.
  /// Series that also sit in a locked genre are left out of every rail, and
  /// kids profiles never see adult titles.
  Map<String, List<Series>> _buildRails(
      List<Series> all, List<String> genres, Set<String> locked,
      {required bool isKid}) {
    final rails = {
      for (final g in genres)
        if (!locked.contains(g)) g: <Series>[],
    };
    for (final s in all) {
      if (isKid && isAdultGenre(s.genre)) continue;
      final sg = splitGenres(s.genre);
      if (sg.any(locked.contains)) continue;
      for (final g in sg) {
        final rail = rails[g];
        if (rail != null && rail.length < _railLength) rail.add(s);
      }
    }
    return rails;
  }

  Future<void> _hideGenre(String profileId, String g) async {
    unawaited(HapticFeedback.mediumImpact());
    final hide = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              autofocus: true,
              leading: const Icon(Icons.visibility_off_outlined),
              title: const Text('Hide Genre'),
              subtitle: Text(context.displayName(g),
                  style: Theme.of(sheetContext).textTheme.bodySmall),
              onTap: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (hide == true) {
      await ref.read(profileServiceProvider).hideCategory(profileId, g);
      ref.invalidate(activeProfileProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(_allSeriesProvider);
    final profileAsync = ref.watch(activeProfileProvider);
    final profile = profileAsync.valueOrNull;
    final profileId = profile?.id;

    final sort = ref.watch(contentSortProvider);
    final posterView = ref.watch(homeLayoutSeriesProvider) != 'compact';
    final parentalPrefs = ref.watch(appPreferencesProvider).valueOrNull;
    final sessionUnlocked = ref.watch(parentalSessionUnlockedProvider);
    final inProgress =
        ref.watch(_episodesInProgressProvider).valueOrNull ?? [];
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogo(),
        title: const Text('Series'),
        actions: [
          HomeLayoutToggleAction(
            provider: homeLayoutSeriesProvider,
            setLayout: setHomeLayoutSeries,
          ),
          const SortToggleAction(),
          const CastAction(),
        ],
      ),
      body: allAsync.when(
        loading: () => const SkeletonList(leadingSize: 28),
        error: (_, __) => ErrorStateView(
          message: "Couldn't load series. Try again.",
          onRetry: () => _refreshSeries(context, ref),
        ),
        data: (all) {
          if (all.isEmpty) {
            final admin = profile?.isAdmin == true;
            return EmptyStateView(
              icon: Icons.video_library_outlined,
              title: 'Your show library starts here',
              message: admin
                  ? 'Add a provider with TV series to browse show posters, seasons and episodes. The starter supplies live TV.'
                  : 'This source has no series. Ask your profile administrator to add a series provider.',
              actionLabel: admin ? 'Add provider' : null,
              onAction: admin ? () => context.push('/onboarding') : null,
            );
          }
          final isKid = profile?.isKidsProfile ?? false;
          final favIdSet = (profile?.favoriteSeriesIds ?? []).toSet();
          final favorites = all
              .where((s) => favIdSet.contains(s.id))
              .where((s) => !isKid || !isAdultGenre(s.genre))
              .toList();
          final seriesById = {for (final s in all) s.id: s};
          final visibleInProgress = inProgress.where((e) {
            if (!isKid) return true;
            final series = seriesById[e.seriesId];
            return series == null || !isAdultGenre(series.genre);
          }).toList();
          final hidden = profile?.hiddenCategories.toSet() ?? {};
          final genres = _buildGenres(all, hidden, sort)
              .where((g) => !isKid || !isAdultCategory(g))
              .toList();
          final lockedGenres = parentalPrefs == null
              ? const <String>{}
              : genres
                  .where((g) =>
                      isCategoryLocked(g, parentalPrefs, sessionUnlocked))
                  .toSet();
          // Whichever section renders first gets its first item autofocused
          // so the D-pad can start navigating immediately once the page
          // loads, without an extra "warm-up" press.
          final firstSectionIsContinueWatching = visibleInProgress.isNotEmpty;
          final firstSectionIsFavorites =
              !firstSectionIsContinueWatching && favorites.isNotEmpty;
          final firstSectionIsGenres =
              !firstSectionIsFavorites && !firstSectionIsContinueWatching;
          return RefreshIndicator(
            onRefresh: () => _refreshSeries(context, ref),
            child: CustomScrollView(
              slivers: [
                if (visibleInProgress.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _EpisodeContinueWatchingRow(
                      episodes: visibleInProgress,
                      autofocusFirst: firstSectionIsContinueWatching,
                    ),
                  ),
                if (favorites.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _HorizontalPosterRow(
                      title: 'Favorites',
                      items: favorites,
                      profileId: profileId,
                      isFavoritesRow: true,
                      autofocusFirst: firstSectionIsFavorites,
                    ),
                  ),
                if (posterView)
                  ..._genreRails(
                    all: all,
                    genres: genres,
                    lockedGenres: lockedGenres,
                    isKid: isKid,
                    profileId: profileId,
                    autofocusFirst: firstSectionIsGenres,
                  )
                else
                  ..._genreList(
                    all: all,
                    genres: genres,
                    lockedGenres: lockedGenres,
                    profileId: profileId,
                    autofocusFirst: firstSectionIsGenres,
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Poster view: a rail per genre, built lazily as it scrolls into view.
  List<Widget> _genreRails({
    required List<Series> all,
    required List<String> genres,
    required Set<String> lockedGenres,
    required bool isKid,
    required String? profileId,
    required bool autofocusFirst,
  }) {
    if (genres.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: _HorizontalPosterRow(
            title: 'All Series',
            items: all.take(_railLength).toList(),
            profileId: profileId,
            onSeeAll: () => _tapGenre('All'),
            autofocusFirst: autofocusFirst,
          ),
        ),
      ];
    }
    final rails = _buildRails(all, genres, lockedGenres, isKid: isKid);
    final shown = [
      for (final g in genres)
        if (lockedGenres.contains(g) || (rails[g]?.isNotEmpty ?? false)) g,
    ];
    return [
      SliverList.builder(
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final g = shown[i];
          final onHide =
              profileId == null ? null : () => _hideGenre(profileId, g);
          if (lockedGenres.contains(g)) {
            return LockedRail(
              title: context.displayName(g),
              onUnlock: () => _tapGenre(g),
              onHeaderLongPress: onHide,
              autofocusFirst: autofocusFirst && i == 0,
            );
          }
          return _HorizontalPosterRow(
            title: context.displayName(g),
            items: rails[g]!,
            profileId: profileId,
            onSeeAll: () => _tapGenre(g),
            onHeaderLongPress: onHide,
            autofocusFirst: autofocusFirst && i == 0,
          );
        },
      ),
    ];
  }

  /// Compact view: the plain genre list with counts.
  List<Widget> _genreList({
    required List<Series> all,
    required List<String> genres,
    required Set<String> lockedGenres,
    required String? profileId,
    required bool autofocusFirst,
  }) {
    final genreCounts = <String, int>{};
    for (final s in all) {
      for (final g in splitGenres(s.genre)) {
        if (g.isEmpty) continue;
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
      }
    }
    return [
      const SliverToBoxAdapter(child: RailHeader(title: 'Browse by Genre')),
      SliverToBoxAdapter(
        child: _GenreTileList(
          genres: genres.isEmpty ? ['All'] : genres,
          seriesCounts: {
            if (genres.isEmpty) 'All': all.length,
            for (final g in genres) g: genreCounts[g] ?? 0,
          },
          onTap: _tapGenre,
          lockedGenres: lockedGenres,
          profileId: profileId,
          autofocusFirst: autofocusFirst,
          onHideGenre:
              profileId == null ? null : (g) => _hideGenre(profileId, g),
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Series genre screen (pushed as a route — back pops naturally)
// ---------------------------------------------------------------------------

class SeriesGenreScreen extends ConsumerStatefulWidget {
  const SeriesGenreScreen({super.key, required this.genre});
  final String genre;

  @override
  ConsumerState<SeriesGenreScreen> createState() => _SeriesGenreScreenState();
}

class _SeriesGenreScreenState extends ConsumerState<SeriesGenreScreen> {
  // Always a fresh list — the caller sorts it in place, and 'All' must not
  // mutate the provider's cached list.
  List<Series> _filtered(List<Series> all) {
    if (widget.genre == 'All') return List.of(all);
    // Exact match on the split genre names — the same split that built the
    // genre list. A substring match put "XXX - Movies" titles under
    // "Movies", slipping adult titles past the category's parental lock.
    final genre = widget.genre.toLowerCase();
    return all
        .where((s) =>
            splitGenres(s.genre).any((g) => g.toLowerCase() == genre))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(_allSeriesProvider);
    final profileAsync = ref.watch(activeProfileProvider);
    final profile = profileAsync.valueOrNull;
    final columns = PlatformHelper.posterColumns(context);
    final sort = ref.watch(contentSortProvider);
    final viewMode = ref.watch(viewModeSeriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.genre == 'All'
            ? 'All Series'
            : context.displayName(widget.genre)),
        actions: [
          ViewModeToggleAction(
            provider: viewModeSeriesProvider,
            setMode: setViewModeSeries,
          ),
          const SortToggleAction(),
          const CastAction(),
        ],
      ),
      body: allAsync.when(
        loading: () => const SkeletonList(leadingSize: 48),
        error: (_, __) => ErrorStateView(
          message: "Couldn't load series. Try again.",
          onRetry: () => _refreshSeries(context, ref),
        ),
        data: (all) {
          final filtered = _filtered(all);
          if (sort == 'az') {
            filtered.sort((a, b) => a.title.compareTo(b.title));
          }
          return RefreshIndicator(
            onRefresh: () => _refreshSeries(context, ref),
            child: CustomScrollView(
              key: ValueKey('${widget.genre}_${sort}_$viewMode'),
              slivers: [
                if (filtered.isEmpty)
                  const SliverFillRemaining(
                    child: EmptyStateView(
                      icon: Icons.video_library_outlined,
                      message: 'No series found.',
                    ),
                  )
                else if (viewMode == 'list')
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _SeriesListTile(
                        key: ValueKey(filtered[i].id),
                        series: filtered[i],
                        profileId: profile?.id,
                        autofocus: i == 0,
                      ),
                      childCount: filtered.length,
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    sliver: SliverGrid(
                      delegate: SliverChildBuilderDelegate(
                        (context, i) => _PosterCard(
                          key: ValueKey(filtered[i].id),
                          series: filtered[i],
                          profileId: profile?.id,
                          autofocus: i == 0,
                        ),
                        childCount: filtered.length,
                      ),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: AppTheme.posterAspectRatio,
                      ),
                    ),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 24)),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Genre tile list
// ---------------------------------------------------------------------------

class _GenreTileList extends StatelessWidget {
  const _GenreTileList({
    required this.genres,
    required this.seriesCounts,
    required this.onTap,
    this.profileId,
    this.onHideGenre,
    this.lockedGenres = const {},
    this.autofocusFirst = false,
  });

  final List<String> genres;
  final Map<String, int> seriesCounts;
  final void Function(String) onTap;
  final String? profileId;
  final void Function(String)? onHideGenre;
  final Set<String> lockedGenres;
  final bool autofocusFirst;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < genres.length; i++)
          CategoryTile(
            label: genres[i],
            count: seriesCounts[genres[i]] ?? 0,
            icon: genres[i] == 'All'
                ? Icons.video_library_outlined
                : genreIcon(genres[i], fallback: Icons.category_outlined),
            isLocked: lockedGenres.contains(genres[i]),
            onTap: () => onTap(genres[i]),
            onLongPress: genres[i] == 'All' || onHideGenre == null
                ? null
                : () => onHideGenre!(genres[i]),
            autofocus: autofocusFirst && i == 0,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Horizontal favorites row
// ---------------------------------------------------------------------------

class _HorizontalPosterRow extends ConsumerWidget {
  const _HorizontalPosterRow({
    required this.title,
    required this.items,
    required this.profileId,
    this.isFavoritesRow = false,
    this.autofocusFirst = false,
    this.onSeeAll,
    this.onHeaderLongPress,
  });

  final String title;
  final List<Series> items;
  final String? profileId;
  final bool isFavoritesRow;
  final bool autofocusFirst;
  final VoidCallback? onSeeAll;
  final VoidCallback? onHeaderLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Favorites and genre rails share the same favorite-toggle sheet — it
    // reads "Remove from Favorites" for anything already favorited.
    return MediaRail(
      title: title,
      onSeeAll: onSeeAll,
      onHeaderLongPress: onHeaderLongPress,
      autofocusFirst: autofocusFirst,
      fallbackIcon: Icons.video_library_outlined,
      items: [
        for (final s in items)
          RailItem(
            title: context.displayName(s.title),
            imageUrl: s.posterUrl,
            heroTag: posterHeroTag(title, s.id),
            onTap: () => context.push('/series/${s.id}',
                extra: posterHeroTag(title, s.id)),
            onLongPress: profileId == null
                ? null
                : () => _showSeriesOptions(context, ref, s, profileId!),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Series list tile (list view)
// ---------------------------------------------------------------------------

/// Long-press sheet shared by [_SeriesListTile] and [_PosterCard].
void _showSeriesOptions(
    BuildContext context, WidgetRef ref, Series series, String profileId) {
  HapticFeedback.mediumImpact();
  final isFav = ref
          .read(activeProfileProvider)
          .valueOrNull
          ?.favoriteSeriesIds
          .contains(series.id) ??
      false;
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            autofocus: true,
            leading: Icon(isFav ? Icons.star_border : Icons.star),
            title: Text(isFav ? 'Remove from Favorites' : 'Add to Favorites'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await ref
                  .read(profileServiceProvider)
                  .toggleFavoriteSeries(profileId, series.id);
              ref.invalidate(activeProfileProvider);
            },
          ),
        ],
      ),
    ),
  );
}

class _SeriesListTile extends ConsumerWidget {
  const _SeriesListTile({
    super.key,
    required this.series,
    required this.profileId,
    this.autofocus = false,
  });

  final Series series;
  final String? profileId;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(activeProfileProvider.select(
        (a) => a.valueOrNull?.favoriteSeriesIds.contains(series.id) ?? false));
    void onTap() => context.push('/series/${series.id}');
    return TvFocusable(
      wrapsGesture: false,
      onTap: onTap,
      autofocus: autofocus,
      ensureVisibleOnFocus: true,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: PosterImage(
              posterUrl: series.posterUrl, width: 40, height: 56),
        ),
        title: Text(context.displayName(series.title),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: series.genre != null && series.genre!.isNotEmpty
            ? Text(context.displayName(splitGenres(series.genre).first),
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        // A tappable IconButton, not a static status Icon — favoriting stays
        // consistent with Live TV's directly-tappable channel-row star.
        trailing: IconButton(
          icon: Icon(
            isFav ? Icons.star : Icons.star_border,
            color: isFav
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.onSurfaceVariant,
            size: 20,
          ),
          tooltip: isFav ? 'Remove from Favorites' : 'Add to Favorites',
          onPressed: profileId == null
              ? null
              : () async {
                  await ref
                      .read(profileServiceProvider)
                      .toggleFavoriteSeries(profileId!, series.id);
                  ref.invalidate(activeProfileProvider);
                },
        ),
        onTap: onTap,
        onLongPress:
            profileId == null ? null : () => _showSeriesOptions(context, ref, series, profileId!),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Poster card (grid)
// ---------------------------------------------------------------------------

class _PosterCard extends ConsumerWidget {
  const _PosterCard({
    super.key,
    required this.series,
    required this.profileId,
    this.autofocus = false,
  });

  final Series series;
  final String? profileId;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFav = ref.watch(activeProfileProvider.select(
        (a) => a.valueOrNull?.favoriteSeriesIds.contains(series.id) ?? false));

    return TvFocusable(
      onTap: () => context.push('/series/${series.id}',
          extra: posterHeroTag('grid', series.id)),
      onLongPress: profileId == null ? null : () => _showSeriesOptions(context, ref, series, profileId!),
      autofocus: autofocus,
      ensureVisibleOnFocus: true,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: posterHeroTag('grid', series.id),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.cardRadius),
              child: PosterImage(posterUrl: series.posterUrl),
            ),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: StarButton(
              isFavorite: isFav,
              onTap: profileId == null
                  ? null
                  : () async {
                      await ref
                          .read(profileServiceProvider)
                          .toggleFavoriteSeries(profileId!, series.id);
                      ref.invalidate(activeProfileProvider);
                    },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode continue watching row
// ---------------------------------------------------------------------------

class _EpisodeContinueWatchingRow extends ConsumerWidget {
  const _EpisodeContinueWatchingRow({
    required this.episodes,
    this.autofocusFirst = false,
  });
  final List<Episode> episodes;
  final bool autofocusFirst;

  void _showRemoveSheet(BuildContext context, WidgetRef ref, Episode ep) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              autofocus: true,
              leading: Icon(Icons.remove_circle_outline,
                  color: Theme.of(context).colorScheme.error),
              title: const Text('Remove from Continue Watching'),
              onTap: () async {
                Navigator.pop(sheetContext);
                final profileId =
                    ref.read(activeProfileProvider).valueOrNull?.id;
                if (profileId == null) return;
                await ref
                    .read(appDatabaseProvider)
                    .clearEpisodeProgress(profileId, ep.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Series lookup so each card can show the series poster (stills are
    // often absent) and name — "S01E01 · Episode 1" alone doesn't say which
    // show it is.
    final seriesById = {
      for (final s in ref.watch(_allSeriesProvider).valueOrNull ?? const [])
        s.id: s,
    };
    return MediaRail(
      title: 'Continue Watching',
      autofocusFirst: autofocusFirst,
      fallbackIcon: Icons.video_library_outlined,
      items: [
        for (final ep in episodes)
          RailItem(
            title: context
                .displayName(seriesById[ep.seriesId]?.title ?? ep.displayTitle),
            subtitle: seriesById[ep.seriesId] == null
                ? ep.episodeLabel
                : '${ep.episodeLabel} · ${ep.displayTitle}',
            imageUrl: seriesById[ep.seriesId]?.posterUrl ?? ep.stillUrl,
            progress: ep.watchProgress,
            onTap: () => context.push('/player', extra: {
              'streamUrl': ep.streamUrl,
              'title': '${ep.episodeLabel} – ${ep.displayTitle}',
              'contentId': ep.id,
              'contentType': 'episode',
              // Needed for Up Next to find the following episode.
              'seriesId': ep.seriesId,
              'resumePosition': ep.watchedDuration,
            }),
            onLongPress: () => _showRemoveSheet(context, ref, ep),
          ),
      ],
    );
  }
}
