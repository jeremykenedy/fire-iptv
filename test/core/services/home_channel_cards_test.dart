import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_iptv/core/models/channel.dart';
import 'package:open_iptv/core/models/profile.dart';
import 'package:open_iptv/core/services/home_channel_cards.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppPreferences prefs;
  final now = DateTime(2026, 10, 22);
  final profile = Profile(
    id: 'everyone',
    name: 'Everyone',
    avatarEmoji: 'TV',
    createdAt: now,
    updatedAt: now,
  );
  Channel channel(String id,
          {String source = 'public',
          String genre = 'News',
          String? art,
          int order = 0,
          DateTime? watched}) =>
      Channel(
        id: id,
        sourceId: source,
        name: 'Channel $id',
        streamUrl: 'https://private.example/live/secret/stream',
        sortOrder: order,
        groupTitle: genre,
        logoUrl: art,
        lastWatchedAt: watched,
      );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = AppPreferences(await SharedPreferences.getInstance());
  });
  tearDown(
      () => messenger.setMockMethodCallHandler(HomeChannelCards.channel, null));

  test('cards contain actual channels and stable links without stream secrets',
      () {
    final cards = homeChannelCards([channel('abc / 12')], profile, prefs);
    expect(cards.single['title'], 'Channel abc / 12');
    expect(homeChannelId(cards.single['intentUri']), 'abc / 12');
    expect(cards.single['artUri'], startsWith('android.resource:'));
    expect(cards.toString(), isNot(contains('private.example')));
    expect(cards.toString(), isNot(contains('secret')));
  });

  test('favorites then recently watched lead a bounded deterministic row', () {
    final cards = homeChannelCards([
      for (var i = 0; i < 20; i++) channel('$i', order: i),
      channel('recent', watched: now),
      channel('favorite'),
    ], profile.copyWith(favoriteChannelIds: ['favorite']), prefs);
    expect(cards.length, 12);
    expect(cards.map((x) => x['id']).take(3), ['favorite', 'recent', '0']);
  });

  test('missing and PIN-protected profiles publish nothing', () {
    expect(homeChannelCards([channel('news')], null, prefs), isEmpty);
    final locked = profile.copyWith(pinHash: 'private-hash');
    expect(homeChannelCards([channel('news')], locked, prefs), isEmpty);
    expect(canOpenHomeChannel(channel('news'), locked, prefs), isFalse);
  });

  test('source membership and current playlist apply to cards and link targets',
      () async {
    final limited = profile.copyWith(sourceIds: ['public']);
    expect(
        homeChannelCards(
                [channel('1'), channel('2', source: 'other')], limited, prefs)
            .map((x) => x['id']),
        ['1']);
    await prefs.setActiveSourceId('other');
    expect(
        homeChannelCards(
                [channel('1'), channel('2', source: 'other')], profile, prefs)
            .map((x) => x['id']),
        ['2']);
    expect(canOpenHomeChannel(channel('1'), profile, prefs), isFalse);
  });

  test('hidden, locked and child-inappropriate categories are never published',
      () async {
    await prefs.setParentalProtectionEnabled(true);
    await prefs.setParentalLockedCategories(['Sports']);
    final restricted =
        profile.copyWith(isKidsProfile: true, hiddenCategories: ['Hidden']);
    final cards = homeChannelCards([
      channel('news'),
      channel('hidden', genre: 'Hidden'),
      channel('locked', genre: 'Sports'),
      channel('adult', genre: 'Adult'),
      channel('mixed', genre: 'News;Sports'),
    ], restricted, prefs);
    expect(cards.map((x) => x['id']), ['news']);
    expect(
        canOpenHomeChannel(
            channel('locked', genre: 'Sports'), restricted, prefs),
        isFalse);
  });

  test('credential-bearing and nonpublic artwork use packaged artwork', () {
    for (final art in [
      'https://user:password@example.com/a.png',
      'https://example.com/a.png?token=secret',
      'file:///data/private.png',
      'content://another.app/private',
      'https://example.com/a.png#secret'
    ]) {
      expect(
          homeChannelCards([channel('1', art: art)], profile, prefs)
              .single['artUri'],
          startsWith('android.resource:'));
    }
    expect(
        homeChannelCards([channel('1', art: 'https://example.com/logo.png')],
                profile, prefs)
            .single['artUri'],
        'https://example.com/logo.png');
  });

  test('removed channels clear the row rather than creating placeholder cards',
      () {
    expect(homeChannelCards([], profile, prefs), isEmpty);
  });

  test('external links cannot supply URLs, query parameters or malformed IDs',
      () {
    for (final link in [
      null,
      '',
      'https://channel/1',
      'fireiptv://channel/',
      'fireiptv://channel/1/2',
      'fireiptv://user@channel/1',
      'fireiptv://channel:123/1',
      'fireiptv://channel/1?url=https://evil.example',
      'fireiptv://channel/1#other',
      'fireiptv://channel/%00'
    ]) {
      expect(homeChannelId(link), isNull, reason: link);
    }
  });

  test('native publication status distinguishes empty, error and unsupported',
      () async {
    messenger.setMockMethodCallHandler(
        HomeChannelCards.channel, (_) async => {'status': 'published'});
    expect(await HomeChannelCards.sync([]), isTrue);
    messenger.setMockMethodCallHandler(
        HomeChannelCards.channel, (_) async => {'status': 'empty'});
    expect(await HomeChannelCards.sync([]), isTrue);
    messenger.setMockMethodCallHandler(
        HomeChannelCards.channel, (_) async => {'status': 'unsupported'});
    expect(await HomeChannelCards.sync([]), isFalse);
    messenger.setMockMethodCallHandler(HomeChannelCards.channel, (_) async {
      throw PlatformException(code: 'provider_failed');
    });
    expect(await HomeChannelCards.sync([]), isFalse);
  });
}
