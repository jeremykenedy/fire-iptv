import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_iptv/core/models/source.dart';
import 'package:open_iptv/core/parsers/xtream_client.dart';
import 'package:open_iptv/core/providers/theme_providers.dart';
import 'package:open_iptv/core/services/auto_refresh_service.dart';
import 'package:open_iptv/core/services/profile_service.dart';
import 'package:open_iptv/core/services/source_manager.dart';
import 'package:open_iptv/core/storage/local_playlists.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/features/settings/car_video_addon.dart';
import 'package:open_iptv/features/settings/edit_playlist_screen.dart';
import 'package:open_iptv/features/settings/profile_picker_screen.dart';
import 'package:open_iptv/features/settings/refresh_all.dart';
import 'package:open_iptv/features/updates/update_dialog.dart';
import 'package:open_iptv/shared/theme/app_theme.dart';
import 'package:open_iptv/shared/utils/format.dart';
import 'package:open_iptv/shared/utils/friendly_error.dart';
import 'package:open_iptv/shared/utils/redact.dart';
import 'package:open_iptv/shared/widgets/info_tooltip.dart';
import 'package:open_iptv/shared/widgets/loading_view.dart';
import 'package:open_iptv/shared/widgets/profile_avatar.dart';
import 'package:open_iptv/shared/widgets/settings_group.dart';
import 'package:open_iptv/shared/widgets/tv_focusable.dart';
import 'package:open_iptv/ui/platform_helper.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tooltipController = InfoTooltipController();
    final theme = Theme.of(context);

    // Derive active profile for the subtitle.
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final isAdmin = profile?.isAdmin ?? false;

    return InfoTooltipScope(
      controller: tooltipController,
      child: Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: ListView(
          children: [
            // --------------- PROFILES ---------------
            SettingsGroup(title: 'Account', children: [
              InfoTooltip(
                id: 'settings_profile',
                title: 'Profile',
                body: 'fire-iptv supports multiple profiles on one device. '
                    'Each profile has its own watch history, favorites, hidden '
                    'categories, and PIN lock. Tap to manage profiles.',
                child: _NavTile(
                  autofocus: true,
                  leading: profile != null
                      ? ProfileAvatar(
                          emoji: profile.avatarEmoji, name: profile.name)
                      : const Icon(Icons.person_outline),
                  title: profile?.name ?? 'Profile',
                  subtitle: Text(
                    profile == null
                        ? 'No profile selected'
                        : '${profile.isAdmin ? 'Admin' : profile.isKidsProfile ? 'Kids profile' : 'Standard profile'} · Manage profiles',
                    style: theme.textTheme.bodySmall,
                  ),
                  onTap: () => context.push('/settings/profiles'),
                ),
              ),
              Consumer(builder: (context, ref, _) {
                final all = ref.watch(allProfilesProvider);
                final count = all.valueOrNull?.length ?? 0;
                if (count <= 1) return const SizedBox.shrink();
                return InfoTooltip(
                  id: 'settings_switch_profile',
                  title: 'Switch Profile',
                  body: 'Quickly change the active profile without going into '
                      'profile management. Useful when sharing a device with '
                      'family or roommates.',
                  child: _NavTile(
                    leading: const Icon(Icons.switch_account_outlined),
                    title: 'Switch Profile',
                    subtitle: Text('$count profiles available',
                        style: theme.textTheme.bodySmall),
                    onTap: () => showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => ProfilePickerScreen(
                        onPicked: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                );
              }),
            ]),
            // --------------- SOURCES (admin only) ---------------
            if (isAdmin) ...[
              SettingsGroup(title: 'Playlists', children: [
                Consumer(builder: (context, ref, _) {
                  final sources = ref.watch(allSourcesProvider);
                  return InfoTooltip(
                    id: 'settings_sources',
                    title: 'Playlists',
                    body: 'A playlist is your provider connection — either '
                        'an M3U playlist URL or Xtream Codes credentials. '
                        'Playlists supply your channels, movies, and series. '
                        'You can add multiple playlists and refresh them here.',
                    child: _NavTile(
                      leading: const Icon(Icons.playlist_play_outlined),
                      title: 'Playlists',
                      subtitle: sources.when(
                        loading: () => null,
                        error: (_, __) => null,
                        data: (list) => Text(
                          list.isEmpty
                              ? 'No playlists added'
                              : '${list.length} playlist${list.length == 1 ? '' : 's'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      onTap: () => _openSourcesPage(context),
                    ),
                  );
                }),
                const RefreshAllTiles(),
              ]),
              // --------------- BACKUP (admin only) ---------------
              SettingsGroup(title: 'Data', children: [
                InfoTooltip(
                  id: 'settings_backup',
                  title: 'Backup & Restore',
                  body: 'Export your profiles and playlists to a single '
                      '.zip file you can store anywhere. Restore it '
                      'later to move to a new device or recover from a reset. '
                      'Stream credentials are included — keep the file safe.',
                  child: _NavTile(
                    leading: const Icon(Icons.backup_outlined),
                    title: 'Backup & Restore',
                    subtitle: Text(
                      'Export or import your profile and playlists',
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => context.push('/settings/backup'),
                  ),
                ),

                // --------------- AUTO-REFRESH (admin only) ---------------
                Consumer(builder: (context, ref, _) {
                  final hours = ref.watch(refreshIntervalHoursProvider);
                  return InfoTooltip(
                    id: 'settings_auto_refresh',
                    title: 'Auto-Refresh',
                    body: 'Automatically refreshes your playlists and TV guide '
                        'in the background so channels and schedules stay '
                        'current without manual refreshing.',
                    child: _NavTile(
                      leading: const Icon(Icons.autorenew),
                      title: 'Auto-Refresh',
                      subtitle: Text(
                        _refreshIntervalLabel(hours),
                        style: theme.textTheme.bodySmall,
                      ),
                      onTap: () => _showAutoRefreshDialog(context, ref, hours),
                    ),
                  );
                }),
                Consumer(builder: (context, ref, _) {
                  final hours = ref.watch(refreshIntervalHoursProvider);
                  if (hours <= 0) return const SizedBox.shrink();
                  final notifyEnabled =
                      ref.watch(refreshNotificationsEnabledProvider);
                  return InfoTooltip(
                    id: 'settings_refresh_notifications',
                    title: 'Refresh Notifications',
                    body: 'Lets you know when a background refresh finishes, '
                        'or if a playlist failed to refresh.',
                    child: _ToggleTile(
                      icon: Icons.notifications_outlined,
                      title: 'Refresh Notifications',
                      value: notifyEnabled,
                      onChanged: (v) async {
                        final prefs =
                            await ref.read(appPreferencesProvider.future);
                        await setRefreshNotificationsEnabled(ref, v, prefs);
                      },
                    ),
                  );
                }),
              ]),
              // --------------- PARENTAL (admin only) ---------------
              SettingsGroup(title: 'Family', children: [
                InfoTooltip(
                  id: 'settings_parental',
                  title: 'Parental Controls',
                  body: 'Hide adult categories and lock any category you '
                      'choose behind an admin PIN. Locked categories stay '
                      'unlocked until the app is restarted.',
                  child: _NavTile(
                    leading: const Icon(Icons.family_restroom_outlined),
                    title: 'Parental Controls',
                    subtitle: Text(
                      'PIN-protect adult and locked categories',
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => context.push('/settings/parental'),
                  ),
                ),
              ]),
            ],

            // --------------- PLAYBACK ---------------
            SettingsGroup(title: 'Playback', children: [
              InfoTooltip(
                id: 'settings_continue_watching',
                title: 'Continue Watching',
                body: 'When this is on, fire-iptv remembers where you left off '
                    'in movies and series. The next time you open them, '
                    "you'll be offered the option to resume.",
                child: _ToggleTile(
                  icon: Icons.play_circle_outline,
                  title: 'Continue Watching',
                  value:
                      true, // TODO: wire from AppPreferences in Phase 1 completion
                  onChanged: (_) {},
                ),
              ),
              Consumer(builder: (context, ref, _) {
                final pipEnabled = ref.watch(pipEnabledProvider);
                return InfoTooltip(
                  id: 'settings_pip',
                  title: 'Picture-in-Picture',
                  body: 'When enabled, pressing Home while a video is playing '
                      'shrinks it into a small floating window so you can '
                      'keep watching while using other apps.',
                  child: _ToggleTile(
                    icon: Icons.picture_in_picture_alt_outlined,
                    title: 'Picture-in-Picture',
                    value: pipEnabled,
                    onChanged: (v) async {
                      final prefs =
                          await ref.read(appPreferencesProvider.future);
                      await setPipEnabled(ref, v, prefs);
                    },
                  ),
                );
              }),
              Consumer(builder: (context, ref, _) {
                final notifyEnabled =
                    ref.watch(mediaNotificationEnabledProvider);
                return InfoTooltip(
                  id: 'settings_media_notification',
                  title: 'Media Notification',
                  body: 'Shows a "Now Playing" notification with play/pause '
                      'controls while content is playing, so you can control '
                      'playback from the notification shade or lock screen.',
                  child: _ToggleTile(
                    icon: Icons.notifications_active_outlined,
                    title: 'Media Notification',
                    value: notifyEnabled,
                    onChanged: (v) async {
                      final prefs =
                          await ref.read(appPreferencesProvider.future);
                      await setMediaNotificationEnabled(ref, v, prefs);
                    },
                  ),
                );
              }),
              // Android Auto video add-on (phones; installing apps is
              // an admin job).
              if (isAdmin && Platform.isAndroid && !PlatformHelper.isTVDevice)
                const CarVideoAddonTile(),
              Consumer(builder: (context, ref, _) {
                final sort = ref.watch(contentSortProvider);
                return InfoTooltip(
                  id: 'settings_sort_order',
                  title: 'Content Sort Order',
                  body: 'Controls how channels, movies, and series are listed. '
                      'Provider order shows them in the sequence your IPTV '
                      'provider sends them. A–Z sorts them alphabetically.',
                  child: _NavTile(
                    leading: const Icon(Icons.sort),
                    title: 'Content Sort Order',
                    subtitle: Text(
                      sort == 'az' ? 'A–Z' : 'Provider order',
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => _showSortOrderDialog(context, ref, sort),
                  ),
                );
              }),
            ]),
            // --------------- APPEARANCE ---------------
            SettingsGroup(title: 'Appearance', children: [
              Consumer(builder: (context, ref, _) {
                final accent = ref.watch(accentColorProvider);
                return InfoTooltip(
                  id: 'settings_accent_color',
                  title: 'Accent Color',
                  body: 'Changes the highlight color used throughout the app — '
                      'active buttons, selected items, progress bars, and '
                      'other indicators. Pick whichever color you like best.',
                  child: _NavTile(
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: accent.withValues(alpha: 0.14),
                      child: CircleAvatar(backgroundColor: accent, radius: 10),
                    ),
                    title: 'Accent Color',
                    subtitle: Text(
                      AppTheme.accentSwatches
                          .firstWhere((s) => s.color == accent,
                              orElse: () => (label: 'Custom', color: accent))
                          .label,
                      style: theme.textTheme.bodySmall,
                    ),
                    onTap: () => _showAccentColorPicker(context, ref, accent),
                  ),
                );
              }),
              InfoTooltip(
                id: 'settings_clean_names',
                title: 'Clean Up Names',
                body:
                    'Tidies the names your provider sends — removes tags like '
                    '"|EN|", "US|" or "A+ -" and turns ALL-CAPS names into '
                    'normal capitalization. Turn off to see names exactly as '
                    'your provider sends them.',
                child: Consumer(builder: (context, ref, _) {
                  return _ToggleTile(
                    icon: Icons.auto_fix_high_outlined,
                    title: 'Clean Up Names',
                    value: ref.watch(cleanNamesProvider),
                    onChanged: (v) async {
                      final prefs =
                          await ref.read(appPreferencesProvider.future);
                      await setCleanNames(ref, v, prefs);
                    },
                  );
                }),
              ),
              if (isAdmin)
                InfoTooltip(
                  id: 'settings_hidden_cats',
                  title: 'Hidden Categories',
                  body: "Categories you've hidden won't appear in your channel "
                      "list. Your channels are still there — they're just out "
                      "of the way. You can unhide them here at any time.",
                  child: _NavTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: 'Hidden Categories',
                    onTap: () => _showHiddenCategoriesPage(context),
                  ),
                ),
            ]),
            // --------------- ABOUT ---------------
            SettingsGroup(title: 'About', children: [
              InfoTooltip(
                id: 'settings_about',
                title: 'About fire-iptv',
                body: 'Shows the current app version and license information. '
                    'OpenIPTV is open-source under the GPL-3.0 license — '
                    'no ads, no telemetry, no accounts. Ever.',
                child: FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (context, snap) {
                    final version = snap.hasData
                        ? 'Version ${snap.data!.version}'
                        : 'fire-iptv';
                    return _NavTile(
                      leading: const Icon(Icons.info_outline),
                      title: 'About fire-iptv',
                      subtitle: Text(version, style: theme.textTheme.bodySmall),
                      showChevron: false,
                      onTap: () => _showAboutDialog(context, snap.data),
                    );
                  },
                ),
              ),
              InfoTooltip(
                id: 'settings_check_updates',
                title: 'Check for Updates',
                body: 'Looks for a newer version of fire-iptv on GitHub and, if '
                    'there is one, shows what changed and installs it. Only '
                    'the public release page is contacted — nothing about you '
                    'or your device is sent.',
                child: _NavTile(
                  leading: const Icon(Icons.system_update_outlined),
                  title: 'Check for Updates',
                  subtitle: Text('See if a newer version is available',
                      style: theme.textTheme.bodySmall),
                  onTap: () => checkForUpdateManually(context),
                ),
              ),
              InfoTooltip(
                id: 'settings_auto_update',
                title: 'Check Automatically',
                body: 'When on, fire-iptv checks for a new version every time '
                    'it starts, and lets admin profiles know. Turn off to '
                    'only check from this menu.',
                child: Consumer(builder: (context, ref, _) {
                  final prefs = ref.watch(appPreferencesProvider).valueOrNull;
                  return StatefulBuilder(
                    builder: (context, setLocal) => _ToggleTile(
                      icon: Icons.update,
                      title: 'Check Automatically',
                      value: prefs?.autoUpdateCheck ?? true,
                      onChanged: (v) async {
                        await prefs?.setAutoUpdateCheck(v);
                        setLocal(() {});
                      },
                    ),
                  );
                }),
              ),
            ]),
            // --------------- ADVANCED (admin only, last) ---------------
            if (isAdmin)
              SettingsGroup(title: 'Advanced', children: [
                InfoTooltip(
                  id: 'settings_power_tools',
                  title: 'Power User Tools',
                  body: 'Tools for checking and tuning your connection: '
                      'your device and public IP addresses, connection '
                      'type, VPN and DNS — handy when a provider has '
                      'trouble reaching you.',
                  child: _NavTile(
                    leading: const Icon(Icons.tune),
                    title: 'Power User Tools',
                    subtitle: Text('Network info for troubleshooting',
                        style: theme.textTheme.bodySmall),
                    onTap: () => context.push('/settings/power-tools'),
                  ),
                ),
              ]),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _openSourcesPage(BuildContext context) {
    // Sources management: show a simple list with delete + refresh options.
    // Full sources page is a future enhancement; for Phase 1 we show a sheet.
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _SourcesSheet(),
    );
  }

  Future<void> _showSortOrderDialog(
      BuildContext context, WidgetRef ref, String current) async {
    final prefs = await ref.read(appPreferencesProvider.future);
    if (!context.mounted) return;
    unawaited(showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Content Sort Order'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogChoice(
              label: 'Provider order',
              selected: current == 'provider',
              onTap: () async {
                Navigator.of(ctx).pop();
                await setContentSort(ref, 'provider', prefs);
              },
            ),
            _DialogChoice(
              label: 'A–Z',
              selected: current == 'az',
              onTap: () async {
                Navigator.of(ctx).pop();
                await setContentSort(ref, 'az', prefs);
              },
            ),
          ],
        ),
        actions: [
          TvActivatable(
            onTap: () => Navigator.of(ctx).pop(),
            builder: (onTap) =>
                TextButton(onPressed: onTap, child: const Text('Cancel')),
          ),
        ],
      ),
    ));
  }

  String _refreshIntervalLabel(int hours) {
    switch (hours) {
      case 2:
        return 'Every 2 hours';
      case 6:
        return 'Every 6 hours';
      case 12:
        return 'Every 12 hours';
      case 24:
        return 'Every 24 hours';
      default:
        return 'Off';
    }
  }

  Future<void> _showAutoRefreshDialog(
      BuildContext context, WidgetRef ref, int current) async {
    final prefs = await ref.read(appPreferencesProvider.future);
    if (!context.mounted) return;
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-Refresh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [0, 2, 6, 12, 24]
              .map((hours) => _DialogChoice(
                    label: _refreshIntervalLabel(hours),
                    selected: current == hours,
                    onTap: () => Navigator.of(ctx).pop(hours),
                  ))
              .toList(),
        ),
        actions: [
          TvActivatable(
            onTap: () => Navigator.of(ctx).pop(),
            builder: (onTap) =>
                TextButton(onPressed: onTap, child: const Text('Cancel')),
          ),
        ],
      ),
    );
    if (selected == null || selected == current) return;
    if (!context.mounted) return;

    final turningOn = current <= 0 && selected > 0;
    await setRefreshIntervalHours(ref, selected, prefs);

    if (turningOn && context.mounted) {
      await _runAutoRefreshPermissionFlow(context);
    }
  }

  /// One-time rationale + permission chain, shown only when auto-refresh is
  /// turned on from Off. Declining either permission doesn't block enabling
  /// the feature — WorkManager still runs, just less reliably without the
  /// battery exemption, and silently without a visible notification if that
  /// permission is denied.
  Future<void> _runAutoRefreshPermissionFlow(BuildContext context) async {
    final wantsNotifications = await _askPermission(
      context,
      title: 'Stay Informed',
      body: 'Allow notifications so fire-iptv can let you know when a '
          'background refresh finishes or runs into a problem?',
      confirmLabel: 'Allow',
    );
    if (wantsNotifications) {
      await requestNotificationPermission();
    }
    if (!context.mounted) return;

    final wantsBatteryExemption = await _askPermission(
      context,
      title: 'Reliable Background Refresh',
      body: 'Some phones aggressively limit background apps to save '
          'battery, which can delay auto-refresh. Exempting fire-iptv '
          'from battery optimization makes refreshes more reliable.',
      confirmLabel: 'Continue',
    );
    if (wantsBatteryExemption) {
      await requestBatteryOptimizationExemption();
    }
  }

  /// Rationale dialog shown before a system permission prompt: "Not Now" vs
  /// [confirmLabel]. Dismissing it counts as declining.
  Future<bool> _askPermission(
    BuildContext context, {
    required String title,
    required String body,
    required String confirmLabel,
  }) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TvActivatable(
            onTap: () => Navigator.of(ctx).pop(false),
            builder: (onTap) =>
                TextButton(onPressed: onTap, child: const Text('Not Now')),
          ),
          TvActivatable(
            autofocus: true,
            onTap: () => Navigator.of(ctx).pop(true),
            builder: (onTap) =>
                FilledButton(onPressed: onTap, child: Text(confirmLabel)),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  void _showAccentColorPicker(
      BuildContext context, WidgetRef ref, Color current) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('Accent Color',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: AppTheme.accentSwatches.asMap().entries.map((entry) {
                  final i = entry.key;
                  final swatch = entry.value;
                  final selected = swatch.color == current;
                  return TvFocusable(
                    autofocus: i == 0,
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      Navigator.of(ctx).pop();
                      final prefs =
                          await ref.read(appPreferencesProvider.future);
                      await setAccentColor(ref, swatch.color, prefs);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: swatch.color,
                            shape: BoxShape.circle,
                            border: selected
                                ? Border.all(
                                    color: Theme.of(ctx).colorScheme.onSurface,
                                    width: 3)
                                : null,
                          ),
                          child: selected
                              ? const Icon(Icons.check,
                                  color: Colors.white, size: 26)
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(swatch.label,
                            style: Theme.of(ctx).textTheme.bodySmall),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHiddenCategoriesPage(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => const _HiddenCategoriesSheet(),
    );
  }

  void _showAboutDialog(BuildContext context, PackageInfo? info) {
    showAboutDialog(
      context: context,
      applicationName: 'fire-iptv',
      applicationVersion: info != null ? info.version : '',
      applicationLegalese:
          '© 2026 OpenIPTV contributors. Licensed under GPL-3.0.',
      children: [
        const SizedBox(height: 16),
        const Text(
          'An open-source, ad-free, cross-platform IPTV client. '
          'No accounts required. No telemetry. No ads. Ever.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final bool value;
  final void Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    return TvActivatable(
      onTap: () => onChanged(!value),
      builder: (_) => SwitchListTile(
        secondary: IconBadge(icon: icon),
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// A settings row that opens something else — icon, title, optional subtitle,
/// trailing chevron — reachable by both tap and remote OK.
class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.autofocus = false,
    this.showChevron = true,
  });

  final Widget leading;
  final String title;
  final Widget? subtitle;
  final VoidCallback onTap;
  final bool autofocus;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return TvActivatable(
      onTap: onTap,
      autofocus: autofocus,
      builder: (onTap) => ListTile(
        leading: leading is Icon
            ? IconBadge(icon: (leading as Icon).icon!)
            : leading,
        title: Text(title),
        subtitle: subtitle,
        trailing: showChevron ? const Icon(Icons.chevron_right) : null,
        onTap: onTap,
      ),
    );
  }
}

/// A radio-style dialog row: the check mark is tinted on the selected option
/// and transparent (but still occupying its slot) on the others, so the
/// labels stay aligned.
class _DialogChoice extends StatelessWidget {
  const _DialogChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TvActivatable(
      onTap: onTap,
      builder: (onTap) => SimpleDialogOption(
        onPressed: onTap,
        child: Row(children: [
          Icon(Icons.check,
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.transparent),
          const SizedBox(width: 8),
          Text(label),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sources bottom sheet
// ---------------------------------------------------------------------------

class _SourcesSheet extends ConsumerStatefulWidget {
  const _SourcesSheet();

  @override
  ConsumerState<_SourcesSheet> createState() => _SourcesSheetState();
}

class _SourcesSheetState extends ConsumerState<_SourcesSheet> {
  final _refreshingPlaylist = <String>{};
  final _refreshingEpg = <String>{};

  /// The sheet's own messenger: a snackbar sent to the Settings page would
  /// sit behind this modal sheet, where the result can't be read.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  void _showMessage(String text) =>
      _messenger.currentState?.showSnackBar(SnackBar(content: Text(text)));

  Future<void> _refreshPlaylist(String id) async {
    if (_refreshingPlaylist.contains(id) || _refreshingEpg.contains(id)) return;
    setState(() => _refreshingPlaylist.add(id));
    try {
      final sources = await ref.read(allSourcesProvider.future);
      final source = sources.firstWhere((s) => s.id == id);
      await ref.read(sourceManagerProvider).refreshPlaylist(source);
      ref.invalidate(allSourcesProvider);
      if (mounted) {
        _showMessage('"${source.nickname}" playlist refreshed.');
      }
    } catch (e) {
      if (mounted) {
        _showMessage(
            'Playlist refresh failed: ${friendlySourceErrorMessage(e)}');
      }
    } finally {
      if (mounted) setState(() => _refreshingPlaylist.remove(id));
    }
  }

  // Closes this sheet (popped with its own context — see the lessons on
  // root-navigator sheets) and opens the editor above Settings.
  void _editSource(Source s) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => EditPlaylistScreen(source: s),
    ));
  }

  Future<void> _refreshEpg(String id) async {
    if (_refreshingPlaylist.contains(id) || _refreshingEpg.contains(id)) return;
    setState(() => _refreshingEpg.add(id));
    Source? source;
    try {
      final sources = await ref.read(allSourcesProvider.future);
      source = sources.firstWhere((s) => s.id == id);
      await ref.read(sourceManagerProvider).refreshEpgOnly(source);
      if (mounted) {
        _showMessage('"${source.nickname}" TV guide refreshed.');
      }
    } catch (e) {
      if (mounted) {
        _showMessage("${source?.nickname ?? 'This playlist'}'s TV guide "
            "isn't available right now. Try again later.");
      }
    } finally {
      if (mounted) setState(() => _refreshingEpg.remove(id));
    }
  }

  /// [source] null = browse every playlist together.
  Future<void> _switchSource(BuildContext context, Source? source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Switch Playlist?'),
        content: Text(
          source == null
              ? 'Show all playlists together?\n\n'
                  'The channel list, movies, and series will include every playlist.'
              : 'Switch to "${source.nickname}"?\n\n'
                  'The channel list, movies, and series will update to show only this playlist.',
        ),
        actions: [
          TvActivatable(
            onTap: () => Navigator.of(ctx).pop(false),
            builder: (onTap) =>
                TextButton(onPressed: onTap, child: const Text('Cancel')),
          ),
          TvActivatable(
            autofocus: true,
            onTap: () => Navigator.of(ctx).pop(true),
            builder: (onTap) =>
                FilledButton(onPressed: onTap, child: const Text('Switch')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final prefs = await ref.read(appPreferencesProvider.future);
      await setActiveSource(ref, source?.id, prefs);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    String id,
    String nickname,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Playlist?'),
        content: Text('This will remove "$nickname" and all its channels, '
            'movies, and series. This cannot be undone.'),
        actions: [
          TvActivatable(
            autofocus: true,
            onTap: () => Navigator.of(ctx).pop(false),
            builder: (onTap) =>
                TextButton(onPressed: onTap, child: const Text('Cancel')),
          ),
          TvActivatable(
            onTap: () => Navigator.of(ctx).pop(true),
            builder: (onTap) => FilledButton(
              onPressed: onTap,
              style: AppTheme.destructiveButtonStyle(ctx),
              child: const Text('Remove'),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sourceManagerProvider).deleteSource(id);
      // Clear active source if it was the deleted one.
      if (ref.read(activeSourceIdProvider) == id) {
        final prefs = await ref.read(appPreferencesProvider.future);
        await setActiveSource(ref, null, prefs);
      }
      ref.invalidate(allSourcesProvider);
    }
  }

  void _showInfoPanel(BuildContext context, Source source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SourceInfoSheet(source: source),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(allSourcesProvider);
    final activeSourceId = ref.watch(activeSourceIdProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => _withMessenger(Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Playlists',
                    style: Theme.of(context).textTheme.titleLarge),
                TvActivatable(
                  // TV: something in the sheet must hold the remote, or the
                  // first key lands on an off-screen row. This is the one
                  // harmless choice (a row would switch playlists on OK).
                  autofocus: true,
                  onTap: () {
                    // Grab the router before popping — this sheet's context
                    // is torn down by the pop.
                    final router = GoRouter.of(context);
                    Navigator.of(context).pop();
                    router.push('/onboarding');
                  },
                  builder: (onTap) => FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add Playlist'),
                    onPressed: onTap,
                  ),
                ),
              ],
            ),
          ),
          if ((sourcesAsync.valueOrNull?.length ?? 0) > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Choose which playlist to browse, or show them all together.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: sourcesAsync.when(
              loading: () => const LoadingView(),
              error: (_, __) =>
                  const Center(child: Text("Couldn't load playlists.")),
              data: (sources) {
                if (sources.isEmpty) {
                  return const Center(child: Text('No playlists yet.'));
                }
                final multiSource = sources.length > 1;
                // With several playlists, a leading "All playlists" row makes
                // the no-active-playlist state (everything merged) visible
                // and selectable.
                final allOffset = multiSource ? 1 : 0;
                return ListView.builder(
                  controller: controller,
                  itemCount: sources.length + allOffset,
                  itemBuilder: (context, index) {
                    if (index < allOffset) {
                      final allActive = activeSourceId == null;
                      return TvActivatable(
                        onTap: allActive
                            ? null
                            : () => _switchSource(context, null),
                        builder: (onTap) => ListTile(
                          leading: _PlaylistBadge(
                              icon: Icons.library_books_outlined,
                              active: allActive),
                          title: const Text('All playlists'),
                          subtitle: Text(
                            '${sources.length} playlists combined',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          onTap: onTap,
                        ),
                      );
                    }
                    final s = sources[index - allOffset];
                    final isActive = activeSourceId == s.id ||
                        (!multiSource && activeSourceId == null);
                    final isPlaylistRefreshing =
                        _refreshingPlaylist.contains(s.id);
                    final isEpgRefreshing = _refreshingEpg.contains(s.id);
                    final isBusy = isPlaylistRefreshing || isEpgRefreshing;
                    return TvRevealOnFocus(
                      child: TvActivatable(
                        // A busy row stays focusable (doing nothing), or the
                        // remote's focus on its refresh button is lost.
                        onTap: multiSource && !isActive
                            ? (isBusy ? () {} : () => _switchSource(context, s))
                            : null,
                        builder: (onTap) => ListTile(
                          leading: _PlaylistBadge(
                              icon: Icons.playlist_play_rounded,
                              active: isActive),
                          title: Text(s.nickname),
                          subtitle: Text(
                            [
                              s.type == SourceType.xtream
                                  ? 'Xtream Codes'
                                  : LocalPlaylists.isLocal(s.m3uUrl)
                                      ? 'Playlist file'
                                      : 'M3U playlist',
                              if (isActive && multiSource) 'Browsing',
                            ].join(' · '),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          onTap: onTap,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _SourceAction(
                                icon: Icons.sync_rounded,
                                tooltip: 'Refresh Playlist',
                                busy: isBusy,
                                onTap:
                                    isBusy ? null : () => _refreshPlaylist(s.id),
                              ),
                              _SourceMenu(
                                enabled: !isBusy,
                                onEdit: () => _editSource(s),
                                onInfo: () => _showInfoPanel(context, s),
                                onRefreshGuide: () => _refreshEpg(s.id),
                                onRemove: () =>
                                    _confirmDelete(context, s.id, s.nickname),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      )),
    );
  }

  Widget _withMessenger(Widget child) => ScaffoldMessenger(
        key: _messenger,
        child: Scaffold(backgroundColor: Colors.transparent, body: child),
      );
}

/// A playlist's icon in a tinted circle; the one being browsed gets a
/// solid accent circle with a tick.
class _PlaylistBadge extends StatelessWidget {
  const _PlaylistBadge({required this.icon, required this.active});

  final IconData icon;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    if (!active) return IconBadge(icon: icon);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(Icons.check_rounded,
          size: 22, color: Theme.of(context).colorScheme.onPrimary),
    );
  }
}

/// The less-used playlist actions, tucked into a ⋮ menu.
class _SourceMenu extends StatelessWidget {
  const _SourceMenu({
    required this.enabled,
    required this.onEdit,
    required this.onInfo,
    required this.onRefreshGuide,
    required this.onRemove,
  });

  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onInfo;
  final VoidCallback onRefreshGuide;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final menuKey = GlobalKey<PopupMenuButtonState<int>>();
    final error = Theme.of(context).colorScheme.error;
    PopupMenuItem<int> item(int v, IconData icon, String label,
        [Color? color]) {
      final row = Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: color)),
      ]);
      return PopupMenuItem(
        value: v,
        child: v == 3 ? TvInitialFocus(child: row) : row,
      );
    }
    return TvFocusable(
      wrapsGesture: false,
      borderRadius: BorderRadius.circular(20),
      onTap: () => enabled ? menuKey.currentState?.showButtonMenu() : null,
      child: TvMenuTheme(
        child: PopupMenuButton<int>(
          key: menuKey,
          enabled: enabled,
          tooltip: 'More',
          onSelected: (v) => switch (v) {
            3 => onEdit(),
            0 => onInfo(),
            1 => onRefreshGuide(),
            _ => onRemove(),
          },
          itemBuilder: (_) => [
            item(3, Icons.edit_outlined, 'Edit Playlist'),
            item(0, Icons.info_outline, 'Playlist Info'),
            item(1, Icons.event_note_outlined, 'Refresh TV Guide'),
            const PopupMenuDivider(),
            item(2, Icons.delete_outline, 'Remove', error),
          ],
        ),
      ),
    );
  }
}

/// One fixed-size slot in a playlist row's trailing action strip — an icon
/// button, or a spinner in its place while that action is running.
class _SourceAction extends StatelessWidget {
  const _SourceAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      // The same (enabled, no-op) button shows the spinner while busy:
      // swapping it for a bare spinner removed the node the remote's focus
      // was on, and focus jumped back to another playlist's row.
      child: TvActivatable(
        onTap: busy ? () {} : onTap,
        builder: (onTap) => IconButton(
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 20),
          tooltip: tooltip,
          onPressed: onTap,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Source info bottom sheet (#22)
// ---------------------------------------------------------------------------

class _SourceInfoSheet extends StatefulWidget {
  const _SourceInfoSheet({required this.source});

  final Source source;

  @override
  State<_SourceInfoSheet> createState() => _SourceInfoSheetState();
}

class _SourceInfoSheetState extends State<_SourceInfoSheet> {
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _userInfo;
  Map<String, dynamic>? _serverInfo;

  @override
  void initState() {
    super.initState();
    if (widget.source.type == SourceType.xtream) _fetchInfo();
  }

  Future<void> _fetchInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final client = XtreamClient.fromSource(widget.source);
    try {
      final info = await client.getServerInfo();
      if (mounted) {
        setState(() {
          _userInfo = info['user_info'] as Map<String, dynamic>?;
          _serverInfo = info['server_info'] as Map<String, dynamic>?;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not fetch server info.';
          _loading = false;
        });
      }
    } finally {
      client.dispose();
    }
  }

  String _formatEpoch(dynamic value) {
    if (value == null) return '—';
    final epoch = int.tryParse(value.toString());
    if (epoch == null || epoch == 0) return '—';
    final dt = DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    return formatYmd(dt);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = widget.source;
    final lastRefreshed = source.lastRefreshed;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(source.nickname, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              source.type == SourceType.xtream
                  ? 'Xtream Codes'
                  : LocalPlaylists.isLocal(source.m3uUrl)
                      ? 'Playlist file'
                      : 'M3U Playlist',
              style: theme.textTheme.bodySmall,
            ),
            const Divider(height: 28),
            if (source.type == SourceType.m3u) ...[
              LocalPlaylists.isLocal(source.m3uUrl)
                  ? const _InfoRow('Source', 'File saved on this device')
                  : _InfoRow('URL', redactUrl(source.m3uUrl ?? '—')),
              if (source.epgUrl != null) _InfoRow('EPG URL', redactUrl(source.epgUrl!)),
              _InfoRow(
                'Last refreshed',
                lastRefreshed != null ? formatYmd(lastRefreshed) : 'Never',
              ),
            ] else if (_loading) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              ),
            ] else if (_error != null) ...[
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ] else ...[
              _InfoRow('Status', '${_userInfo?['status'] ?? '—'}'),
              _InfoRow('Expires', _formatEpoch(_userInfo?['exp_date'])),
              _InfoRow(
                  'Active connections', '${_userInfo?['active_cons'] ?? '—'}'),
              _InfoRow(
                  'Max connections', '${_userInfo?['max_connections'] ?? '—'}'),
              _InfoRow('Trial', _userInfo?['is_trial'] == '1' ? 'Yes' : 'No'),
              const Divider(height: 24),
              _InfoRow('Server',
                  '${_serverInfo?['url'] ?? source.xtreamHost ?? '—'}'),
              _InfoRow('Timezone', '${_serverInfo?['timezone'] ?? '—'}'),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hidden categories sheet
// ---------------------------------------------------------------------------

class _HiddenCategoriesSheet extends ConsumerWidget {
  const _HiddenCategoriesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final hidden = profile?.hiddenCategories ?? [];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('Hidden Categories',
                style: Theme.of(context).textTheme.titleLarge),
          ),
          const Divider(height: 1),
          Expanded(
            child: hidden.isEmpty
                ? const Center(child: Text('No categories are hidden.'))
                : ListView.builder(
                    controller: controller,
                    itemCount: hidden.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(hidden[i]),
                      trailing: TvActivatable(
                        autofocus: i == 0,
                        onTap: profile == null
                            ? null
                            : () async {
                                await ref
                                    .read(profileServiceProvider)
                                    .unhideCategory(profile.id, hidden[i]);
                                ref.invalidate(activeProfileProvider);
                              },
                        builder: (onTap) => TextButton(
                          onPressed: onTap,
                          child: const Text('Show'),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
