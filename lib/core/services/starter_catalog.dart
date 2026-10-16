import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:open_iptv/core/models/profile.dart';
import 'package:open_iptv/core/models/source.dart';
import 'package:open_iptv/core/parsers/m3u_parser.dart';
import 'package:open_iptv/core/storage/database.dart';
import 'package:open_iptv/core/storage/local_playlists.dart';
import 'package:open_iptv/core/storage/preferences.dart';

const managedCatalogUrls = {
  'fire-iptv-live':
      'https://raw.githubusercontent.com/jeremykenedy/fire-iptv/main/assets/catalog/live.m3u',
  'fire-iptv-samsung':
      'https://raw.githubusercontent.com/jeremykenedy/fire-iptv/main/assets/catalog/samsung.m3u',
};

/// Installs bundled catalogs as one transaction, without importing anyone's
/// account, replacing an existing profile, or requiring an internet connection.
class StarterCatalog {
  StarterCatalog({
    required this.db,
    required this.preferences,
    LocalPlaylists? playlists,
    Future<String> Function(String)? loadAsset,
  })  : playlists = playlists ?? LocalPlaylists(),
        loadAsset = loadAsset ?? rootBundle.loadString;

  final AppDatabase db;
  final AppPreferences preferences;
  final LocalPlaylists playlists;
  final Future<String> Function(String) loadAsset;

  Future<List<Source>> install() async {
    final manifest = jsonDecode(
      await loadAsset('assets/catalog/manifest.json'),
    ) as Map<String, dynamic>;
    final revision = manifest['revision'] as String;
    if (!RegExp(r'^[a-zA-Z0-9.-]+$').hasMatch(revision)) {
      throw const FormatException('Invalid catalog revision');
    }
    if (preferences.starterCatalogRevision == revision) return [];

    final existing = await db.getAllSources();
    final profiles = await db.getAllProfiles();
    final firstInstall = preferences.starterCatalogRevision == null;
    // An imported setup belongs to its owner. Adding the starter library
    // must not be a side effect of opening that setup for the first time.
    if (firstInstall && existing.isNotEmpty) {
      await preferences.setStarterCatalogRevision(revision);
      return [];
    }

    final prepared = <({Source source, M3uParseResult catalog})>[];
    for (final value in manifest['sources'] as List) {
      final entry = value as Map<String, dynamic>;
      final id = entry['id'] as String;
      if (!managedCatalogUrls.containsKey(id)) {
        throw const FormatException('Unknown starter source');
      }
      // A source removed by the owner stays removed during future upgrades.
      final previous = existing.where((s) => s.id == id).firstOrNull;
      if (!firstInstall && previous == null) continue;
      if (previous != null) {
        final uri = Uri.tryParse(previous.m3uUrl ?? '');
        if (previous.type != SourceType.m3u ||
            uri?.scheme != 'file' ||
            !(uri?.pathSegments.lastOrNull?.startsWith('$id-') ?? false)) {
          continue;
        }
      }
      final content = await loadAsset('assets/catalog/${entry['file']}');
      final checksum = sha256.convert(utf8.encode(content)).toString();
      if (checksum != entry['sha256']) {
        throw const FormatException('Catalog checksum does not match');
      }
      final catalog = await M3uParser.parse(content, id);
      if (catalog.channels.isEmpty ||
          catalog.movies.isNotEmpty ||
          catalog.series.isNotEmpty) {
        throw const FormatException('Starter catalogs must contain live TV only');
      }
      prepared.add((
        source: Source(
          id: id,
          nickname: previous?.nickname ?? entry['name'] as String,
          type: SourceType.m3u,
          m3uUrl: await playlists.save('$id-$revision', content),
          epgUrl: previous?.epgUrl ?? entry['epgUrl'] as String,
        ),
        catalog: catalog,
      ));
    }

    await db.transaction(() async {
      for (final item in prepared) {
        final id = item.source.id;
        await db.upsertSource(item.source);
        await db.replaceChannelsForSource(id, item.catalog.channels);
        await db.replaceMoviesForSource(id, item.catalog.movies);
        await db.replaceSeriesForSource(id, item.catalog.series);
        await db.replaceEpisodesForSource(id, item.catalog.episodes);
      }
      if (profiles.isEmpty) {
        final now = DateTime.now();
        await db.upsertProfile(
          Profile(
            id: 'fire-iptv-everyone',
            name: 'Everyone',
            avatarEmoji: '📺',
            isAdmin: true,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
    });

    if (firstInstall && profiles.isEmpty) {
      await preferences.setActiveProfileId('fire-iptv-everyone');
      await preferences.setRefreshIntervalHours(6);
      await preferences.setRefreshNotificationsEnabled(false);
      await preferences.setAccentColor('FFB54A');
    }
    await preferences.setStarterCatalogRevision(revision);
    return prepared.map((item) => item.source).toList();
  }
}
