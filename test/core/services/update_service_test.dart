import 'package:flutter_test/flutter_test.dart';
import 'package:open_iptv/core/services/update_service.dart';
import 'package:open_iptv/features/settings/car_video_addon.dart';

void main() {
  group('AppVersion', () {
    test('parses tags and pubspec versions', () {
      expect(AppVersion.tryParse('v0.10.46'), const AppVersion(0, 10, 46));
      expect(AppVersion.tryParse('0.10.46+1'), const AppVersion(0, 10, 46));
      expect(AppVersion.tryParse('1.2'), const AppVersion(1, 2, 0));
      expect(AppVersion.tryParse('native-libmpv-cc-v1'), isNull);
      expect(AppVersion.tryParse(null), isNull);
    });

    test('compares numerically, not as text', () {
      expect(AppVersion.tryParse('0.10.46')! > AppVersion.tryParse('0.10.9')!,
          isTrue);
      expect(AppVersion.tryParse('0.11.0')! > AppVersion.tryParse('0.10.99')!,
          isTrue);
      expect(AppVersion.tryParse('1.0.0')! > AppVersion.tryParse('0.99.99')!,
          isTrue);
      expect(AppVersion.tryParse('0.10.45')! > AppVersion.tryParse('0.10.45')!,
          isFalse);
    });
  });

  group('UpdateInfo.fromGitHubJson', () {
    test('reads version, notes and the APK asset', () {
      final info = UpdateInfo.fromGitHubJson({
        'tag_name': 'v0.10.46',
        'name': 'v0.10.46 — In-app updates',
        'body': '## What\'s new\n- Updates',
        'assets': [
          {'name': 'checksums.txt', 'browser_download_url': 'https://x/c'},
          {
            'name': 'fire-iptv.apk',
            'browser_download_url': 'https://x/fire-iptv.apk',
            'size': 1234,
          },
        ],
      })!;
      expect(info.version, const AppVersion(0, 10, 46));
      expect(info.title, 'v0.10.46 — In-app updates');
      expect(info.notes, startsWith('## What'));
      expect(info.apkUrl, 'https://x/fire-iptv.apk');
      expect(info.apkSize, 1234);
    });

    test('ignores a release without this client\'s file', () {
      // A release made only for another platform: never offered here.
      expect(
          UpdateInfo.fromGitHubJson({
            'tag_name': 'v0.11.0',
            'assets': [
              {
                'name': 'OpenIPTV-windows.zip',
                'browser_download_url': 'https://x/w.zip',
              },
              {'name': 'other.apk', 'browser_download_url': 'https://x/o.apk'},
            ],
          }),
          isNull);
      expect(
          UpdateInfo.fromGitHubJson(
              {'tag_name': 'v0.10.46', 'name': '', 'assets': []}),
          isNull);
    });

    test('picks only its own file from a release with every platform', () {
      final info = UpdateInfo.fromGitHubJson({
        'tag_name': 'v0.11.0',
        'name': '',
        'assets': [
          {'name': 'OpenIPTV-windows.zip', 'browser_download_url': 'https://x/w'},
          {'name': 'fire-iptv.apk', 'browser_download_url': 'https://x/a'},
        ],
      })!;
      expect(info.apkUrl, 'https://x/a');
      expect(info.title, 'v0.11.0');
    });

    test('rejects releases without a version tag', () {
      expect(UpdateInfo.fromGitHubJson({'tag_name': 'nightly'}), isNull);
    });

    test('finds the car video add-on, and the app never takes it', () {
      final release = {
        'tag_name': 'v0.11.30',
        'assets': [
          {'name': carVideoAddonAsset, 'browser_download_url': 'https://x/c'},
          {'name': 'fire-iptv.apk', 'browser_download_url': 'https://x/a'},
        ],
      };
      expect(
          UpdateInfo.fromGitHubJson(release, assetName: carVideoAddonAsset)!
              .apkUrl,
          'https://x/c');
      expect(UpdateInfo.fromGitHubJson(release)!.apkUrl, 'https://x/a');
    });
  });

  test('car video add-on status follows its installed version', () {
    expect(carVideoAddonStatus(null), CarVideoAddonStatus.missing);
    expect(carVideoAddonStatus(carVideoAddonVersion - 1),
        CarVideoAddonStatus.outdated);
    expect(carVideoAddonStatus(carVideoAddonVersion),
        CarVideoAddonStatus.installed);
    expect(carVideoAddonStatus(carVideoAddonVersion + 1),
        CarVideoAddonStatus.installed);
  });
}
