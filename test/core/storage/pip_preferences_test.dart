import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_iptv/core/providers/theme_providers.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh installs keep PiP off before and after preferences load',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(pipEnabledProvider), isFalse);
    final preferences = AppPreferences(await SharedPreferences.getInstance());
    expect(preferences.pipEnabled, isFalse);
  });

  for (final enabled in [true, false]) {
    test('a saved PiP choice of $enabled survives an update', () async {
      SharedPreferences.setMockInitialValues({'pip_enabled': enabled});
      final preferences = AppPreferences(await SharedPreferences.getInstance());

      expect(preferences.pipEnabled, enabled);
    });
  }

  test('PiP opt-in and opt-out persist without changing the selected source',
      () async {
    SharedPreferences.setMockInitialValues({
      'active_profile_id': 'profile-one',
      'active_source_id': 'source-one',
    });
    final stored = await SharedPreferences.getInstance();
    final preferences = AppPreferences(stored);

    await preferences.setPipEnabled(true);
    await stored.reload();
    expect(AppPreferences(stored).pipEnabled, isTrue);

    await preferences.setPipEnabled(false);
    await stored.reload();
    final reloaded = AppPreferences(stored);
    expect(reloaded.pipEnabled, isFalse);
    expect(reloaded.activeProfileId, 'profile-one');
    expect(reloaded.activeSourceId, 'source-one');
  });
}
