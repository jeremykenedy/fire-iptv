import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_iptv/core/models/content_details.dart';
import 'package:open_iptv/core/models/source.dart';
import 'package:open_iptv/core/parsers/m3u_parser.dart';
import 'package:open_iptv/core/parsers/xtream_client.dart';
import 'package:open_iptv/core/services/epg_service.dart';
import 'package:open_iptv/core/services/profile_service.dart';
import 'package:open_iptv/core/services/starter_catalog.dart';
import 'package:open_iptv/core/storage/database.dart';
import 'package:open_iptv/core/storage/local_playlists.dart';
import 'package:open_iptv/shared/utils/redact.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

part 'source_manager.g.dart';

const _uuid = Uuid();

enum SourceDetectionResult { m3u, xtream, failed }

/// Outcome of a single source's background refresh — reported per-phase so a
/// failure notification can be accurate instead of implying total failure.
class SourceRefreshResult {
  const SourceRefreshResult({
    required this.sourceId,
    required this.nickname,
    this.playlistError,
    this.epgError,
  });

  final String sourceId;
  final String nickname;
  final Object? playlistError;
  final Object? epgError;

  bool get succeeded => playlistError == null && epgError == null;
}

@Riverpod(keepAlive: true)
SourceManager sourceManager(SourceManagerRef ref) {
  return SourceManager(
    db: ref.watch(appDatabaseProvider),
    epgService: ref.watch(epgServiceProvider),
  );
}

@Riverpod(keepAlive: true)
Future<List<Source>> allSources(AllSourcesRef ref) {
  return ref.watch(appDatabaseProvider).getAllSources();
}

final _defaultLocalPlaylists = LocalPlaylists();

class SourceManager {
  const SourceManager({
    required this.db,
    required this.epgService,
    this.localPlaylists,
  });

  final AppDatabase db;
  final EpgService epgService;
  // Injectable for tests; defaults to app storage.
  final LocalPlaylists? localPlaylists;

  LocalPlaylists get _local => localPlaylists ?? _defaultLocalPlaylists;

  // ---------------------------------------------------------------------------
  // Auto-detection
  // ---------------------------------------------------------------------------

  Future<SourceDetectionResult> detectSourceType({
    String? url,
    String? xtreamHost,
    String? username,
    String? password,
  }) async {
    if (xtreamHost != null && username != null && password != null) {
      final client = XtreamClient(
        host: xtreamHost,
        username: username,
        password: password,
        sourceId: '',
      );
      final valid = await client.validate();
      client.dispose();
      return valid ? SourceDetectionResult.xtream : SourceDetectionResult.failed;
    }

    if (url != null && url.isNotEmpty) {
      final result = await _probeM3u(url);
      return result ? SourceDetectionResult.m3u : SourceDetectionResult.failed;
    }

    return SourceDetectionResult.failed;
  }

  /// Whether [url] serves an M3U playlist. Reads only the start of the
  /// response — enough for the `#EXTM3U` / `#EXTINF` header — rather than
  /// downloading a playlist that can be tens of megabytes. (It used to send
  /// HEAD first and then test the empty HEAD body, so every server that
  /// answered HEAD looked like it had no playlist.)
  Future<bool> _probeM3u(String url) async {
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return false;
      final head = <int>[];
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 15))) {
        head.addAll(chunk);
        if (head.length >= 1024) break;
      }
      final text = utf8
          .decode(head, allowMalformed: true)
          .replaceFirst('\uFEFF', '')
          .trimLeft();
      return text.startsWith('#EXTM3U') || text.startsWith('#EXTINF');
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Add / refresh / remove
  // ---------------------------------------------------------------------------

  Future<Source> addSource({
    required String nickname,
    required SourceType type,
    String? m3uUrl,
    // Contents of a playlist file picked from the device (instead of
    // [m3uUrl]); saved to app storage, see [LocalPlaylists].
    String? m3uFileContent,
    String? xtreamHost,
    String? xtreamUsername,
    String? xtreamPassword,
    String? epgUrl,
    void Function(String)? onProgress,
  }) async {
    final id = _uuid.v4();
    final source = Source(
      id: id,
      nickname: nickname,
      type: type,
      m3uUrl: m3uFileContent != null
          ? await _local.save(id, m3uFileContent)
          : m3uUrl,
      xtreamHost: xtreamHost,
      xtreamUsername: xtreamUsername,
      xtreamPassword: xtreamPassword,
      epgUrl: epgUrl,
    );

    await db.upsertSource(source);
    try {
      await refreshSource(source, onProgress: onProgress);
    } catch (e) {
      // Fetch/parse failed — remove the orphaned source entry so the user
      // doesn't see a broken playlist in their list.
      await deleteSource(source.id);
      rethrow;
    }
    return source;
  }

  /// Full refresh: playlist (channels/movies/series) then EPG fires in background.
  Future<void> refreshSource(Source source, {void Function(String)? onProgress}) async {
    Source updated;
    if (source.type == SourceType.m3u) {
      updated = await _refreshM3u(source, onProgress: onProgress);
    } else {
      updated = await _refreshXtream(source, onProgress: onProgress);
    }
    await db.updateSourceRefreshTime(source.id, DateTime.now());
    // Hand back the space the swap freed (the old lists).
    await db.compact();
    // Pass the updated source so the auto-set EPG URL is included.
    // Background: a failed guide is logged, and mustn't fail the playlist.
    unawaited(epgService.refreshEpg(updated).catchError((Object _) {}));
  }

  /// Refreshes playlist and EPG concurrently instead of sequentially, for use
  /// by the background auto-refresh task only — manual refresh call sites
  /// (pull-to-refresh, Settings buttons) are unaffected and keep using
  /// [refreshSource]/[refreshPlaylist] above.
  ///
  /// The EPG fetch starts immediately using the source's already-persisted
  /// `epgUrl` (set during the source's original `addSource()` call), running
  /// alongside the playlist fetch rather than waiting for it. This only
  /// applies once a source already has a known EPG URL — true for every
  /// source the background task ever sees, since a brand-new source without
  /// one yet is always added via the sequential `addSource()`/`refreshSource()`
  /// path first. If the playlist refresh discovers a *different* EPG URL
  /// (e.g. an M3U provider changed its embedded `url-tvg`), that's picked up
  /// on the next cycle rather than this one — low-stakes, since the old URL
  /// still gets a valid EPG fetch in the meantime.
  Future<SourceRefreshResult> refreshSourceConcurrent(Source source) async {
    final playlistFuture = source.type == SourceType.m3u
        ? _refreshM3u(source)
        : _refreshXtream(source);
    final hasKnownEpgUrl = source.epgUrl != null && source.epgUrl!.isNotEmpty;
    // Errors captured as values right away: the guide often fails while the
    // playlist is still loading, and a failed Future with no listener yet is
    // reported as an unhandled exception.
    final epgFuture = hasKnownEpgUrl
        ? epgService
            .refreshEpg(source)
            .then<Object?>((_) => null, onError: (Object e) => e)
        : null;

    Object? playlistError;
    Source? updated;
    try {
      updated = await playlistFuture;
    } catch (e) {
      playlistError = e;
      _logRefreshError(source, 'playlist', e);
    }

    Object? epgError;
    if (epgFuture != null) {
      epgError = await epgFuture;
    } else if (updated != null &&
        updated.epgUrl != null &&
        updated.epgUrl!.isNotEmpty) {
      // Playlist refresh just discovered an EPG URL for the first time
      // (only possible for M3U sources) — fetch it now, sequentially.
      try {
        await epgService.refreshEpg(updated);
      } catch (e) {
        epgError = e;
      }
    }

    if (updated != null) {
      await db.updateSourceRefreshTime(source.id, DateTime.now());
    // Hand back the space the swap freed (the old lists).
    await db.compact();
    }

    return SourceRefreshResult(
      sourceId: source.id,
      nickname: source.nickname,
      playlistError: playlistError,
      epgError: epgError,
    );
  }

  /// One playlist's step of "refresh everything" in Settings: the catalog
  /// ([playlist]) and/or the TV guide ([guide]), one after the other — a
  /// 2 GB TV can't hold a big catalog and a big guide in memory at once.
  /// Never throws; each phase's failure is reported in the result.
  Future<SourceRefreshResult> refreshSourceParts(
    Source source, {
    bool playlist = true,
    bool guide = true,
  }) async {
    var current = source;
    Object? playlistError;
    if (playlist) {
      try {
        current = source.type == SourceType.m3u
            ? await _refreshM3u(source)
            : await _refreshXtream(source);
        await db.updateSourceRefreshTime(source.id, DateTime.now());
    // Hand back the space the swap freed (the old lists).
    await db.compact();
      } catch (e) {
        playlistError = e;
        _logRefreshError(source, 'playlist', e);
      }
    }
    Object? epgError;
    if (guide) {
      try {
        // The playlist refresh may have just found (or changed) the URL.
        await epgService.refreshEpg(current);
      } catch (e) {
        epgError = e; // EpgService logs it.
      }
    }
    return SourceRefreshResult(
      sourceId: source.id,
      nickname: source.nickname,
      playlistError: playlistError,
      epgError: epgError,
    );
  }

  /// Refreshes only the playlist (channels/movies/series) — no EPG.
  /// Used by the "Refresh Playlist" button in Settings.
  Future<void> refreshPlaylist(Source source) async {
    try {
      if (source.type == SourceType.m3u) {
        await _refreshM3u(source);
      } else {
        await _refreshXtream(source);
      }
    } catch (e) {
      _logRefreshError(source, 'playlist', e);
      rethrow;
    }
    await db.updateSourceRefreshTime(source.id, DateTime.now());
    // Hand back the space the swap freed (the old lists).
    await db.compact();
  }


  /// Refreshes only the EPG for a source.
  /// Used by the "Refresh TV Guide" button in Settings.
  Future<void> refreshEpgOnly(Source source) async {
    await epgService.refreshEpg(source);
  }

  /// Refreshes only live channels then EPG in background (for Live TV pull-to-refresh).
  Future<void> refreshChannels(Source source) async {
    if (source.type == SourceType.m3u) {
      final url = source.m3uUrl;
      if (url == null) return;
      final result = await _fetchM3u(url, source.id);
      if (source.epgUrl == null && result.epgUrl != null) {
        await db.upsertSource(source.copyWith(epgUrl: result.epgUrl));
      }
      await db.replaceChannelsForSource(source.id, result.channels);
    } else {
      await _withXtream(source, (client) async {
        final channels = await client.getLiveStreams();
        await db.replaceChannelsForSource(source.id, channels);
      });
    }
    await db.updateSourceRefreshTime(source.id, DateTime.now());
    // Hand back the space the swap freed (the old lists).
    await db.compact();
    // Background: a failed guide is logged, and mustn't fail the playlist.
    unawaited(epgService.refreshEpg(source).catchError((Object _) {}));
  }

  /// Refreshes only movies for a source.
  Future<void> refreshMovies(Source source) async {
    if (source.type == SourceType.m3u) {
      final url = source.m3uUrl;
      if (url == null) return;
      final result = await _fetchM3u(url, source.id);
      await db.replaceMoviesForSource(source.id, result.movies);
    } else {
      await _withXtream(source, (client) async {
        final movies = await client.getVodStreams();
        await db.replaceMoviesForSource(source.id, movies);
      });
    }
    await db.updateSourceRefreshTime(source.id, DateTime.now());
    // Hand back the space the swap freed (the old lists).
    await db.compact();
  }

  /// Refreshes only series for a source.
  Future<void> refreshSeries(Source source) async {
    if (source.type == SourceType.m3u) {
      final url = source.m3uUrl;
      if (url == null) return;
      final result = await _fetchM3u(url, source.id);
      await db.replaceSeriesForSource(source.id, result.series);
    } else {
      await _withXtream(source, (client) async {
        final seriesList = await client.getAllSeries();
        await db.replaceSeriesForSource(source.id, seriesList);
      });
    }
    await db.updateSourceRefreshTime(source.id, DateTime.now());
    // Hand back the space the swap freed (the old lists).
    await db.compact();
  }

  // Fetches episodes for a single series on demand (Xtream only).
  // Called lazily from the series detail screen the first time a series is opened.
  Future<void> fetchEpisodesForSeries(String seriesId, String sourceId) async {
    final source = await db.getSourceById(sourceId);
    if (source == null || source.type != SourceType.xtream) return;
    // App internal ID format: "${sourceId}_ser_${xtreamSeriesId}"
    final xtreamId = seriesId.replaceFirst('${sourceId}_ser_', '');
    await _withXtream(source, (client) async {
      final episodes = await client.getSeriesEpisodes(xtreamId);
      if (episodes.isNotEmpty) await db.upsertEpisodes(episodes);
    });
  }

  /// Artwork and metadata for a movie's detail page, or null for sources
  /// that don't provide it (M3U) or when the provider can't be reached.
  Future<ContentDetails?> fetchMovieDetails(
      String movieId, String sourceId) async {
    final source = await db.getSourceById(sourceId);
    if (source == null || source.type != SourceType.xtream) return null;
    final xtreamId = movieId.replaceFirst('${sourceId}_mov_', '');
    try {
      return await _withXtream(source, (client) async =>
          ContentDetails.fromXtream(await client.getVodInfo(xtreamId)));
    } catch (_) {
      return null;
    }
  }

  /// Like [fetchMovieDetails], for a series (with per-episode details).
  Future<ContentDetails?> fetchSeriesDetails(
      String seriesId, String sourceId) async {
    final source = await db.getSourceById(sourceId);
    if (source == null || source.type != SourceType.xtream) return null;
    final xtreamId = seriesId.replaceFirst('${sourceId}_ser_', '');
    try {
      return await _withXtream(source, (client) async =>
          ContentDetails.fromXtream(await client.getSeriesInfo(xtreamId)));
    } catch (_) {
      return null;
    }
  }

  /// The TV guide address a playlist would get automatically, so the edit
  /// screen can show "automatic" instead of a link with the login inside.
  static String? automaticGuideUrl(Source s) {
    if (s.type != SourceType.xtream ||
        s.xtreamHost == null ||
        s.xtreamUsername == null ||
        s.xtreamPassword == null) {
      return null;
    }
    final client = XtreamClient(
      host: s.xtreamHost!,
      username: s.xtreamUsername!,
      password: s.xtreamPassword!,
      sourceId: s.id,
    );
    final url = client.xmltvUrl;
    client.dispose();
    return url;
  }

  /// Saves edits to a playlist: a new name, server address, login (a null
  /// or empty [xtreamPassword] keeps the current one), playlist link or TV
  /// guide address (empty = automatic).
  ///
  /// Changed connection details are checked first — nothing is saved if
  /// the provider won't accept them ([SourceEditException]). Once saved,
  /// the catalog is refreshed so every stream link uses the new details;
  /// item ids don't change, so favourites and watch progress carry over.
  /// Returns the refresh result, or null when only the name changed.
  Future<SourceRefreshResult?> updateSource(
    Source original, {
    required String nickname,
    String? m3uUrl,
    String? xtreamHost,
    String? xtreamUsername,
    String? xtreamPassword,
    String? epgUrl,
  }) async {
    String? clean(String? v) => v == null || v.trim().isEmpty ? null : v.trim();
    final name = clean(nickname) ?? original.nickname;
    final isXtream = original.type == SourceType.xtream;
    final isFile = LocalPlaylists.isLocal(original.m3uUrl);

    final host = isXtream ? clean(xtreamHost) ?? original.xtreamHost : null;
    final user =
        isXtream ? clean(xtreamUsername) ?? original.xtreamUsername : null;
    final pass =
        isXtream ? clean(xtreamPassword) ?? original.xtreamPassword : null;
    final url = isXtream || isFile ? original.m3uUrl : clean(m3uUrl);
    if (!isXtream && url == null) {
      throw const SourceEditException('m3u_missing');
    }

    final connectionChanged = host != original.xtreamHost ||
        user != original.xtreamUsername ||
        pass != original.xtreamPassword ||
        url != original.m3uUrl;

    // Guide: a typed address wins; empty means automatic — for Xtream that
    // is derived from the (possibly new) login on the next refresh, for M3U
    // it's whatever the playlist itself names.
    final wasAutomatic = original.epgUrl == null ||
        original.epgUrl!.isEmpty ||
        original.epgUrl == automaticGuideUrl(original);
    final typedGuide = clean(epgUrl);
    final guide = typedGuide ??
        (wasAutomatic && !connectionChanged ? original.epgUrl : null);
    final guideChanged = guide != original.epgUrl;

    if (connectionChanged) {
      if (isXtream) {
        final client = XtreamClient(
            host: host!, username: user!, password: pass!, sourceId: '');
        final ok = await client.validate();
        client.dispose();
        if (!ok) throw const SourceEditException('xtream_login');
      } else if (!await _probeM3u(url!)) {
        throw const SourceEditException('m3u_unreachable');
      }
    }

    final updated = Source(
      id: original.id,
      nickname: name,
      type: original.type,
      m3uUrl: url,
      xtreamHost: host,
      xtreamUsername: user,
      xtreamPassword: pass,
      epgUrl: guide,
      lastRefreshed: original.lastRefreshed,
    );
    await db.upsertSource(updated);
    if (!connectionChanged && !guideChanged) return null;
    return refreshSourceParts(updated, playlist: connectionChanged);
  }

  Future<void> deleteSource(String sourceId) async {
    final source = await db.getSourceById(sourceId);
    await _local.delete(source?.m3uUrl);
    await db.deleteChannelsForSource(sourceId);
    await db.deleteMoviesForSource(sourceId);
    await db.deleteSeriesForSource(sourceId);
    await db.deleteEpisodesForSource(sourceId);
    await db.deleteProgrammesForSource(sourceId);
    await db.deleteSource(sourceId);
    await db.compact();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Downloads and parses an M3U playlist. [onFetched] fires between the
  /// download and the parse, for progress reporting.
  Future<M3uParseResult> _fetchM3u(
    String url,
    String sourceId, {
    void Function()? onFetched,
  }) async {
    if (LocalPlaylists.isLocal(url)) {
      var content = await _local.read(url);
      final managedUrl = managedCatalogUrl(sourceId, url);
      if (managedUrl != null) {
        try {
          final response = await http
              .get(Uri.parse(managedUrl))
              .timeout(const Duration(seconds: 8));
          if (response.statusCode == 200 &&
              response.body.trimLeft().startsWith('#EXTM3U')) {
            final updated = await M3uParser.parse(response.body, sourceId);
            if (updated.channels.isNotEmpty &&
                updated.movies.isEmpty &&
                updated.series.isEmpty) {
              await _local.replace(url, response.body);
              content = response.body;
            }
          }
        } catch (_) {
          // The bundled or previously cached catalog remains available.
        }
      }
      onFetched?.call();
      final result = await M3uParser.parse(content, sourceId);
      if (result.channels.isEmpty &&
          result.movies.isEmpty &&
          result.series.isEmpty) {
        throw const LocalPlaylistException('empty');
      }
      return result;
    }
    final response =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('http_${response.statusCode}');
    }
    onFetched?.call();
    return M3uParser.parse(response.body, sourceId);
  }

  /// Logs why a refresh failed — the summary the user sees only says that
  /// it did. Provider logins in the error (e.g. a request URL) are masked.
  void _logRefreshError(Source source, String phase, Object e) {
    debugPrint('[Source] ${source.nickname}: $phase refresh failed: '
        '${redactUrl('$e')}');
  }

  /// Runs [fn] with an [XtreamClient] for [source], disposing it afterwards.
  Future<T> _withXtream<T>(
    Source source,
    Future<T> Function(XtreamClient client) fn,
  ) async {
    final client = XtreamClient.fromSource(source);
    try {
      return await fn(client);
    } finally {
      client.dispose();
    }
  }

  // ---------------------------------------------------------------------------
  // M3U refresh
  // ---------------------------------------------------------------------------

  Future<Source> _refreshM3u(Source source, {void Function(String)? onProgress}) async {
    final url = source.m3uUrl;
    if (url == null) return source;

    onProgress?.call(LocalPlaylists.isLocal(url)
        ? 'Reading your playlist file…'
        : 'Connecting to provider…');
    final result = await _fetchM3u(
      url,
      source.id,
      onFetched: () => onProgress?.call('Parsing channels…'),
    );

    Source updated = source;
    if (source.epgUrl == null && result.epgUrl != null) {
      updated = source.copyWith(epgUrl: result.epgUrl);
      await db.upsertSource(updated);
    }

    onProgress?.call('Saving to database…');
    await db.transaction(() async {
      await db.replaceChannelsForSource(source.id, result.channels);
      await db.replaceMoviesForSource(source.id, result.movies);
      await db.replaceSeriesForSource(source.id, result.series);
      await db.replaceEpisodesForSource(source.id, result.episodes);
    });
    return updated;
  }

  // ---------------------------------------------------------------------------
  // Xtream refresh
  // ---------------------------------------------------------------------------

  Future<Source> _refreshXtream(Source source, {void Function(String)? onProgress}) {
    return _withXtream(source, (client) async {
      // Auto-set XMLTV EPG URL for Xtream sources if not already configured.
      Source updated = source;
      if (source.epgUrl == null || source.epgUrl!.isEmpty) {
        updated = source.copyWith(epgUrl: client.xmltvUrl);
        await db.upsertSource(updated);
      }

      // Everything is downloaded before anything is replaced: a provider
      // that drops out halfway leaves the playlist as it was instead of
      // empty.
      onProgress?.call('Connecting to provider…');
      onProgress?.call('Fetching channels…');
      var t = DateTime.now();
      final channels = await client.getLiveStreams();
      debugPrint('[Source] channels: ${channels.length} in ${DateTime.now().difference(t).inMilliseconds}ms');

      onProgress?.call('Fetching movies…');
      t = DateTime.now();
      final movies = await client.getVodStreams();
      debugPrint('[Source] movies: ${movies.length} in ${DateTime.now().difference(t).inMilliseconds}ms');

      onProgress?.call('Fetching series…');
      t = DateTime.now();
      final seriesList = await client.getAllSeries();
      debugPrint('[Source] series: ${seriesList.length} in ${DateTime.now().difference(t).inMilliseconds}ms');

      t = DateTime.now();
      onProgress?.call('Saving ${channels.length} channels…');
      await db.replaceChannelsForSource(source.id, channels);
      debugPrint('[Source] saved channels in ${DateTime.now().difference(t).inMilliseconds}ms');
      t = DateTime.now();
      onProgress?.call('Saving ${movies.length} movies…');
      await db.replaceMoviesForSource(source.id, movies);
      debugPrint('[Source] saved movies in ${DateTime.now().difference(t).inMilliseconds}ms');
      t = DateTime.now();
      onProgress?.call('Saving ${seriesList.length} series…');
      await db.replaceSeriesForSource(source.id, seriesList);
      debugPrint('[Source] saved series in ${DateTime.now().difference(t).inMilliseconds}ms');
      // Episodes are fetched per series when one is opened.
      await db.deleteEpisodesForSource(source.id);
      return updated;
    });
  }
}

/// Why edited playlist details weren't saved (see
/// [SourceManager.updateSource]); worded by `friendlySourceErrorMessage`.
class SourceEditException implements Exception {
  const SourceEditException(this.code);

  /// `xtream_login`, `m3u_unreachable` or `m3u_missing`.
  final String code;

  @override
  String toString() => 'SourceEditException($code)';
}
