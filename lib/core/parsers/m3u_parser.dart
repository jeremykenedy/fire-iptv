import 'dart:isolate';

import 'package:open_iptv/core/models/channel.dart';
import 'package:open_iptv/core/models/episode.dart';
import 'package:open_iptv/core/models/movie.dart';
import 'package:open_iptv/core/models/series.dart';

class M3uParseResult {
  const M3uParseResult({
    required this.channels,
    required this.movies,
    required this.series,
    required this.episodes,
    this.epgUrl,
  });

  final List<Channel> channels;
  final List<Movie> movies;
  final List<Series> series;
  final List<Episode> episodes;
  final String? epgUrl;
}

class M3uParser {
  /// Parses an M3U/M3U+ string in a separate isolate so the UI never blocks.
  static Future<M3uParseResult> parse(String content, String sourceId) {
    return Isolate.run(() => _parse(content, sourceId));
  }

  static M3uParseResult _parse(String content, String sourceId) {
    final lines = content.split('\n');

    String? epgUrl;
    final channels = <Channel>[];
    final movies = <Movie>[];
    final seriesMap = <String, Series>{};
    final episodes = <Episode>[];

    String? pendingExtinf;
    int sortIndex = 0;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTM3U')) {
        epgUrl = _extractAttr(line, 'url-tvg') ??
            _extractAttr(line, 'x-tvg-url');
        continue;
      }

      if (line.startsWith('#EXTINF')) {
        pendingExtinf = line;
        continue;
      }

      if (line.startsWith('#')) continue;

      // This line is a stream URL — pair it with the previous #EXTINF.
      if (pendingExtinf == null) continue;

      final streamUrl = line;
      final attrs = _parseExtinf(pendingExtinf);
      pendingExtinf = null;

      final name = attrs['name'] ?? 'Unknown';
      final group = attrs['group-title'] ?? '';
      final id = _generateId(sourceId, streamUrl);

      final groupLower = group.toLowerCase();

      if (_isVod(groupLower, streamUrl)) {
        if (_isSeries(groupLower, name)) {
          final seriesTitle = _extractSeriesTitle(name);
          final seriesId = _generateId(sourceId, seriesTitle);

          seriesMap.putIfAbsent(
            seriesId,
            () => Series(
              id: seriesId,
              sourceId: sourceId,
              title: seriesTitle,
              posterUrl: attrs['tvg-logo'],
              genre: group,
            ),
          );

          final nums = _parseEpisodeNumbers(name);
          episodes.add(Episode(
            id: id,
            seriesId: seriesId,
            sourceId: sourceId,
            season: nums.$1,
            episode: nums.$2,
            title: name,
            streamUrl: streamUrl,
          ));
        } else {
          movies.add(Movie(
            id: id,
            sourceId: sourceId,
            title: name,
            posterUrl: attrs['tvg-logo'],
            streamUrl: streamUrl,
            genre: group.isNotEmpty ? group : null,
            year: attrs['year'],
            rating: attrs['rating'],
            description: attrs['plot'] ?? attrs['description'],
          ));
        }
      } else {
        channels.add(Channel(
          id: id,
          sourceId: sourceId,
          name: name,
          logoUrl: attrs['tvg-logo'],
          streamUrl: streamUrl,
          groupTitle: group.isNotEmpty ? group : null,
          tvgId: attrs['tvg-id'],
          tvgName: attrs['tvg-name'],
          sortOrder: sortIndex++,
        ));
      }
    }

    return M3uParseResult(
      channels: channels,
      movies: movies,
      series: seriesMap.values.toList(),
      episodes: episodes,
      epgUrl: epgUrl,
    );
  }

  // ---------------------------------------------------------------------------
  // Attribute extraction
  // ---------------------------------------------------------------------------

  static String? _extractAttr(String line, String attr) {
    final pattern = RegExp('$attr="([^"]*)"', caseSensitive: false);
    return pattern.firstMatch(line)?.group(1);
  }

  static final _attrPattern = RegExp(r'(\w[\w-]*)="([^"]*)"');

  /// Parses all key="value" attributes from an #EXTINF line plus the channel name.
  static Map<String, String> _parseExtinf(String line) {
    final result = <String, String>{};

    for (final m in _attrPattern.allMatches(line)) {
      result[m.group(1)!.toLowerCase()] = m.group(2)!;
    }

    // Channel name is everything after the final comma.
    final commaIdx = line.lastIndexOf(',');
    if (commaIdx != -1 && commaIdx < line.length - 1) {
      result['name'] = line.substring(commaIdx + 1).trim();
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Classification helpers
  // ---------------------------------------------------------------------------

  static const _vodKeywords = [
    'vod', 'movie', 'movies', 'film', 'films', 'series', 'shows',
  ];

  static final _vodFileExt =
      RegExp(r'\.(mp4|mkv|avi|mov|m4v|webm|flv|wmv|mpg|mpeg)$');
  static final _liveFileExt = RegExp(r'\.(m3u8|ts)$');

  /// Whether an entry is on-demand (movie/episode) rather than a live
  /// channel. The stream URL is the strongest signal: a media file, or an
  /// Xtream-style /movie/ or /series/ path, is VOD; HLS/MPEG-TS or a /live/
  /// path is live. Only when the URL says nothing does the group name
  /// decide — group keywords alone misfiled live channels in playlists
  /// like iptv-org, whose groups read "Movies;Series" for 24/7 channels.
  /// [groupLower] is the already-lowercased group title.
  static bool _isVod(String groupLower, String streamUrl) {
    final path = (Uri.tryParse(streamUrl)?.path ?? streamUrl).toLowerCase();
    if (path.contains('/movie/') || path.contains('/series/')) return true;
    if (_vodFileExt.hasMatch(path)) return true;
    if (path.contains('/live/') || _liveFileExt.hasMatch(path)) return false;
    return _vodKeywords.any((kw) => groupLower.contains(kw));
  }

  static final _episodePattern = RegExp(r'[Ss](\d+)[Ee](\d+)');

  /// [groupLower] is the already-lowercased group title.
  static bool _isSeries(String groupLower, String name) {
    if (groupLower.contains('series') || groupLower.contains('shows')) {
      return true;
    }
    return _episodePattern.hasMatch(name);
  }

  static String _extractSeriesTitle(String episodeName) {
    final match = _episodePattern.firstMatch(episodeName);
    if (match == null) return episodeName;
    return episodeName.substring(0, match.start).trim().trimRight();
  }

  static (int, int) _parseEpisodeNumbers(String name) {
    final match = _episodePattern.firstMatch(name);
    if (match == null) return (1, 1);
    return (int.parse(match.group(1)!), int.parse(match.group(2)!));
  }

  static String _generateId(String sourceId, String key) {
    // Deterministic ID from source + key so re-parsing the same feed
    // produces the same IDs and upserts work correctly.
    return '${sourceId}_${key.hashCode.abs()}';
  }
}
