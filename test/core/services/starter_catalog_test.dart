import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_iptv/core/models/source.dart';
import 'package:open_iptv/core/services/starter_catalog.dart';
import 'package:open_iptv/core/storage/database.dart';
import 'package:open_iptv/core/storage/local_playlists.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _live = '#EXTM3U\n'
    '#EXTINF:-1 tvg-id="news" group-title="News",News\n'
    'https://example.com/live/news.m3u8\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late AppPreferences prefs;
  late Directory directory;
  late LocalPlaylists playlists;
  late Map<String, String> assets;

  void manifest(String revision, {String? checksum}) {
    assets['assets/catalog/manifest.json'] = jsonEncode({
      'revision': revision,
      'sources': [
        {
          'id': 'fire-iptv-live',
          'name': 'Free live TV',
          'file': 'live.m3u',
          'epgUrl': 'https://example.com/guide.xml',
          'sha256': checksum ?? sha256.convert(utf8.encode(_live)).toString(),
        },
      ],
    });
  }

  StarterCatalog installer() => StarterCatalog(
        db: db,
        preferences: prefs,
        playlists: playlists,
        loadAsset: (path) async => assets[path]!,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPreferences(await SharedPreferences.getInstance());
    db = AppDatabase(NativeDatabase.memory());
    directory = Directory.systemTemp.createTempSync('fire_iptv_starter');
    playlists = LocalPlaylists(baseDir: () async => directory);
    assets = {'assets/catalog/live.m3u': _live};
    manifest('one');
  });
  tearDown(() async {
    await db.close();
    directory.deleteSync(recursive: true);
  });

  test(
    'first launch works offline and repeated launch preserves choices',
    () async {
      await installer().install();
      expect((await db.getAllChannels()).single.name, 'News');
      expect(await db.getAllMovies(), isEmpty);
      expect((await db.getAllProfiles()).single.name, 'Everyone');
      expect(prefs.activeProfileId, 'fire-iptv-everyone');
      expect(prefs.refreshIntervalHours, 6);
      await prefs.setRefreshIntervalHours(12);
      expect(await installer().install(), isEmpty);
      expect(prefs.refreshIntervalHours, 12);
      expect(await db.getAllSources(), hasLength(1));
    },
  );

  test('the shipped starter supplies live TV without an old movie library',
      () async {
    final catalog = StarterCatalog(
        db: db,
        preferences: prefs,
        playlists: playlists,
        loadAsset: (path) => File(path).readAsString());
    await catalog.install();
    expect((await db.getAllChannels()).length, greaterThan(100));
    expect(await db.getAllMovies(), isEmpty);
    expect(await db.getAllSeries(), isEmpty);
    expect(
        (await db.getAllSources()).every((s) => s.epgUrl?.isNotEmpty == true),
        isTrue);
  });

  test('an existing imported setup does not receive starter sources', () async {
    await db.upsertSource(
      const Source(
        id: 'owner',
        nickname: 'My provider',
        type: SourceType.m3u,
        m3uUrl: 'https://example.com/mine.m3u',
      ),
    );
    await installer().install();
    expect((await db.getAllSources()).map((s) => s.id), ['owner']);
    expect(await db.getAllProfiles(), isEmpty);
  });

  test(
    'catalog upgrades preserve profiles, favorites and custom sources',
    () async {
      await installer().install();
      final original = (await db.getAllProfiles()).single;
      await db.upsertProfile(
        original.copyWith(
          name: 'My profile',
          favoriteChannelIds: [(await db.getAllChannels()).single.id],
        ),
      );
      await db.upsertSource(
        const Source(
          id: 'owner',
          nickname: 'My provider',
          type: SourceType.m3u,
          m3uUrl: 'https://example.com/mine.m3u',
        ),
      );
      await prefs.setAccentColor('00FF00');
      manifest('two');
      await installer().install();
      final profile = (await db.getAllProfiles()).single;
      expect(profile.name, 'My profile');
      expect(profile.favoriteChannelIds, hasLength(1));
      expect(await db.getSourceById('owner'), isNotNull);
      expect(prefs.accentColor, '00FF00');
    },
  );

  test('a removed starter source stays removed on upgrade', () async {
    await installer().install();
    await db.deleteChannelsForSource('fire-iptv-live');
    await db.deleteSource('fire-iptv-live');
    manifest('two');
    await installer().install();
    expect(await db.getAllSources(), isEmpty);
  });

  test('an edited provider URL is not replaced by a starter upgrade', () async {
    await installer().install();
    final source = (await db.getAllSources()).single;
    await db.upsertSource(source.copyWith(
        nickname: 'My provider', m3uUrl: 'https://example.com/my-playlist.m3u'));
    manifest('two');
    await installer().install();
    final saved = (await db.getAllSources()).single;
    expect(saved.nickname, 'My provider');
    expect(saved.m3uUrl, 'https://example.com/my-playlist.m3u');
  });

  test('starter upgrades preserve a chosen name and guide address', () async {
    await installer().install();
    final source = (await db.getAllSources()).single;
    await db.upsertSource(source.copyWith(
        nickname: 'Living room', epgUrl: 'https://example.com/my-guide.xml'));
    manifest('two');
    await installer().install();
    final saved = (await db.getAllSources()).single;
    expect(saved.nickname, 'Living room');
    expect(saved.epgUrl, 'https://example.com/my-guide.xml');
  });

  test(
    'a damaged catalog leaves the previous setup and revision usable',
    () async {
      await installer().install();
      final previous = (await db.getAllSources()).single;
      manifest('two', checksum: 'bad');
      await expectLater(installer().install(), throwsFormatException);
      expect(prefs.starterCatalogRevision, 'one');
      expect((await db.getAllSources()).single.m3uUrl, previous.m3uUrl);
      expect(await playlists.read(previous.m3uUrl!), _live);
      expect(await db.getAllChannels(), hasLength(1));
    },
  );
}
