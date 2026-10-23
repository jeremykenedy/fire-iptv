import 'package:flutter/services.dart';
import 'package:open_iptv/core/models/channel.dart';
import 'package:open_iptv/core/models/profile.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/features/discover/discovery.dart';
import 'package:open_iptv/shared/utils/display_name.dart';

bool canOpenHomeChannel(
  Channel channel,
  Profile? profile,
  AppPreferences preferences,
) =>
    profile != null &&
    !profile.hasPin &&
    (preferences.activeSourceId == null ||
        preferences.activeSourceId == channel.sourceId) &&
    canDiscover(
      sourceId: channel.sourceId,
      genre: channel.groupTitle,
      profile: profile,
      preferences: preferences,
      unlocked: const {},
    );

List<Map<String, String>> homeChannelCards(
  Iterable<Channel> channels,
  Profile? profile,
  AppPreferences preferences,
) {
  // Home cards are visible outside the app's profile PIN screen.
  if (profile == null || profile.hasPin) return const [];
  final visible = channels
      .where((channel) => canOpenHomeChannel(channel, profile, preferences))
      .toList();
  final favorites = profile.favoriteChannelIds.toSet();
  visible.sort((a, b) {
    final favorite = (favorites.contains(b.id) ? 1 : 0)
        .compareTo(favorites.contains(a.id) ? 1 : 0);
    if (favorite != 0) return favorite;
    final recent = (b.lastWatchedAt?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.lastWatchedAt?.millisecondsSinceEpoch ?? 0);
    if (recent != 0) return recent;
    final order = a.sortOrder.compareTo(b.sortOrder);
    return order != 0 ? order : a.id.compareTo(b.id);
  });
  return visible.take(12).map((channel) {
    final art = Uri.tryParse(channel.logoUrl ?? '');
    final publicArt = art != null &&
        (art.scheme == 'https' || art.scheme == 'http') &&
        art.host.isNotEmpty &&
        art.userInfo.isEmpty &&
        !art.hasQuery &&
        !art.hasFragment;
    return {
      'id': channel.id,
      'title': preferences.cleanNames
          ? cleanDisplayName(channel.name)
          : channel.name,
      'artUri': publicArt
          ? art.toString()
          : 'android.resource://com.jeremykenedy.fireiptv/drawable/tv_banner',
      'intentUri': Uri(
        scheme: 'fireiptv',
        host: 'channel',
        pathSegments: [channel.id],
      ).toString(),
    };
  }).toList();
}

String? homeChannelId(String? link) {
  if (link == null || link.length > 2048) return null;
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'fireiptv' ||
      uri.host != 'channel' ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.pathSegments.length != 1) {
    return null;
  }
  final id = uri.pathSegments.single;
  return id.isEmpty || id.length > 256 || id.contains(RegExp(r'[\x00-\x1f]'))
      ? null
      : id;
}

class HomeChannelCards {
  static const channel = MethodChannel('fireiptv/home-cards');

  static Future<bool> sync(List<Map<String, String>> cards) async {
    try {
      final result =
          await channel.invokeMapMethod<String, dynamic>('sync', cards);
      return result?['status'] == 'published' || result?['status'] == 'empty';
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  static Future<String?> takePendingLink() async {
    try {
      return await channel.invokeMethod<String>('takePendingLink');
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
