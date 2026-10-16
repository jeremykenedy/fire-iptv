import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Thrown when a playlist file picked from the device can't be used.
class LocalPlaylistException implements Exception {
  const LocalPlaylistException(this.code);

  /// `not_m3u` — the file isn't an M3U playlist;
  /// `empty` — it's a playlist with no channels, movies or series in it;
  /// `missing` — the app's saved copy is gone (e.g. restored from a backup
  /// made before playlist files were included).
  final String code;

  @override
  String toString() => 'local_playlist_$code';
}

/// Playlist files picked from the device ("Playlist File" in the setup
/// wizard). The picked file is *copied* into app storage — the picker's own
/// reference is temporary on Android — and the source stores a `file://` URI
/// to the copy as its `m3uUrl`, so refresh, backup and the rest of the M3U
/// path work unchanged.
class LocalPlaylists {
  LocalPlaylists({Future<Directory> Function()? baseDir})
      : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _baseDir;

  static bool isLocal(String? url) => url != null && url.startsWith('file://');

  /// Decodes a picked file, tolerating a UTF-8 BOM and invalid bytes, and
  /// checks it's really an M3U playlist.
  static String decode(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final head = text.length > 4096 ? text.substring(0, 4096) : text;
    if (!head.contains('#EXTM3U') && !head.contains('#EXTINF')) {
      throw const LocalPlaylistException('not_m3u');
    }
    return text;
  }

  Future<Directory> _dir() async {
    final dir = Directory('${(await _baseDir()).path}/playlists');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Saves [content] as the playlist file for [sourceId]; returns its URI.
  Future<String> save(String sourceId, String content) async {
    final file = File('${(await _dir()).path}/$sourceId.m3u');
    await file.writeAsString(content, flush: true);
    return file.uri.toString();
  }

  /// Reads the saved playlist at [url] (a URI from [save]).
  Future<String> read(String url) async {
    final file = File.fromUri(Uri.parse(url));
    if (!file.existsSync()) throw const LocalPlaylistException('missing');
    return file.readAsString();
  }

  /// Keep the last working managed catalog if a download or write fails.
  Future<void> replace(String url, String content) async {
    final target = File.fromUri(Uri.parse(url));
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  /// Removes the saved copy, if any. Safe to call for any URL.
  Future<void> delete(String? url) async {
    if (!isLocal(url)) return;
    final file = File.fromUri(Uri.parse(url!));
    if (file.existsSync()) await file.delete();
  }
}
