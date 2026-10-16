import 'package:flutter/services.dart';

enum StreamingApp { tubi, plex }

class StreamingApps {
  static const _channel = MethodChannel('fireiptv/streaming-apps');

  static Future<void> open(StreamingApp app) =>
      _channel.invokeMethod<void>('open', app.name);
}
