import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_iptv/core/models/source.dart';
import 'package:open_iptv/core/services/epg_service.dart';
import 'package:open_iptv/core/services/source_manager.dart';
import 'package:open_iptv/core/storage/backup_manager.dart';
import 'package:open_iptv/core/storage/database.dart';
import 'package:open_iptv/core/storage/local_playlists.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/open.dart';

const _playlist = '#EXTM3U\n'
    '#EXTINF:-1 group-title="News",Channel One\n'
    'http://example.com/live/1.m3u8\n';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  if (Platform.isLinux &&
      File('/lib/x86_64-linux-gnu/libsqlite3.so.0').existsSync()) {
    open.overrideFor(
        OperatingSystem.linux, () => DynamicLibrary.open('libsqlite3.so.0'));
  }

  late Directory tmp;
  late LocalPlaylists store;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('otv_playlists');
    store = LocalPlaylists(baseDir: () async => tmp);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  group('decode', () {
    test('accepts a playlist and strips a UTF-8 BOM', () {
      final text = LocalPlaylists.decode(_bytes('﻿$_playlist'));
      expect(text.startsWith('#EXTM3U'), isTrue);
    });

    test('accepts entries without an #EXTM3U header', () {
      expect(
          () => LocalPlaylists.decode(
              _bytes('#EXTINF:-1,One\nhttp://example.com/1\n')),
          returnsNormally);
    });

    test('rejects files that are not playlists', () {
      expect(
        () => LocalPlaylists.decode(_bytes('just some notes')),
        throwsA(isA<LocalPlaylistException>()
            .having((e) => e.code, 'code', 'not_m3u')),
      );
    });
  });

  test('save, read and delete round trip', () async {
    final url = await store.save('src1', _playlist);
    expect(LocalPlaylists.isLocal(url), isTrue);
    expect(await store.read(url), _playlist);

    await store.delete(url);
    expect(
      () => store.read(url),
      throwsA(isA<LocalPlaylistException>()
          .having((e) => e.code, 'code', 'missing')),
    );
  });

  test('delete ignores remote URLs', () async {
    await store.delete('https://example.com/list.m3u');
    await store.delete(null);
  });

  test('a playlist file travels inside a backup', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPreferences(await SharedPreferences.getInstance());

    // Export from one "device"...
    final db = AppDatabase(NativeDatabase.memory());
    final url = await store.save('src1', _playlist);
    await db.upsertSource(Source(
        id: 'src1', nickname: 'My File', type: SourceType.m3u, m3uUrl: url));
    final backup = await BackupManager(
            db: db, prefs: prefs, localPlaylists: store)
        .exportAll();
    await db.close();

    // ...and restore on another, where the file doesn't exist.
    final otherDir = Directory.systemTemp.createTempSync('otv_playlists2');
    addTearDown(() => otherDir.deleteSync(recursive: true));
    final otherStore = LocalPlaylists(baseDir: () async => otherDir);
    final db2 = AppDatabase(NativeDatabase.memory());
    addTearDown(db2.close);
    await BackupManager(db: db2, prefs: prefs, localPlaylists: otherStore)
        .importAll(backup);

    final restored = (await db2.getSourceById('src1'))!;
    expect(restored.m3uUrl, startsWith('file://${otherDir.path}'));
    expect(await otherStore.read(restored.m3uUrl!), _playlist);
  });

  group('adding a playlist from a file', () {
    late AppDatabase db;
    late SourceManager manager;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      manager = SourceManager(
          db: db, epgService: EpgService(db: db), localPlaylists: store);
    });
    tearDown(() => db.close());

    Future<Source> managedSource() async {
      final url = await store.save('fire-iptv-live', _playlist);
      final source = Source(id: 'fire-iptv-live', nickname: 'Free live TV',
          type: SourceType.m3u, m3uUrl: url);
      await db.upsertSource(source);
      return source;
    }

    test('a managed refresh uses the last working catalog during an outage', () async {
      final source = await managedSource();
      await http.runWithClient(() => manager.refreshPlaylist(source),
          () => MockClient((_) async => http.Response('Unavailable', 503)));
      expect((await db.getAllChannels()).single.name, 'Channel One');
      expect(await store.read(source.m3uUrl!), _playlist);
    });

    test('a managed refresh saves valid live TV and ignores an on-demand feed', () async {
      final source = await managedSource();
      final replacement = _playlist.replaceAll('Channel One', 'Channel Two');
      await http.runWithClient(() => manager.refreshPlaylist(source),
          () => MockClient((request) async {
            expect(request.url.host, 'raw.githubusercontent.com');
            return http.Response(replacement, 200);
          }));
      expect((await db.getAllChannels()).single.name, 'Channel Two');
      expect(await store.read(source.m3uUrl!), replacement);
      await http.runWithClient(() => manager.refreshPlaylist(source),
          () => MockClient((_) async => http.Response('#EXTM3U\n'
              '#EXTINF:-1 group-title="Movies",Old film\n'
              'https://example.com/movie.mp4\n', 200)));
      expect((await db.getAllChannels()).single.name, 'Channel Two');
      expect(await db.getAllMovies(), isEmpty);
      expect(await store.read(source.m3uUrl!), replacement);
    });

    test('saves the file and loads its channels', () async {
      final source = await manager.addSource(
        nickname: 'My File',
        type: SourceType.m3u,
        m3uFileContent: _playlist,
      );
      expect(LocalPlaylists.isLocal(source.m3uUrl), isTrue);
      final channels = await db.getAllChannels();
      expect(channels.map((c) => c.name), ['Channel One']);

      await manager.deleteSource(source.id);
      expect(tmp.listSync(recursive: true).whereType<File>(), isEmpty);
    });

    test('an empty playlist fails and leaves nothing behind', () async {
      await expectLater(
        manager.addSource(
          nickname: 'Empty',
          type: SourceType.m3u,
          m3uFileContent: '#EXTM3U\n',
        ),
        throwsA(isA<LocalPlaylistException>()
            .having((e) => e.code, 'code', 'empty')),
      );
      expect(await db.getAllSources(), isEmpty);
      expect(tmp.listSync(recursive: true).whereType<File>(), isEmpty);
    });
  });
}
