import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_iptv/core/services/auto_refresh_service.dart';
import 'package:open_iptv/core/services/now_playing_service.dart';
import 'package:open_iptv/core/services/pip_service.dart';
import 'package:open_iptv/core/services/playback_service.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/shared/theme/app_theme.dart';

// Session-level providers — initialized in app.dart after prefs load.
// Use notifier.state = x to update; app reads reactively via ref.watch.

final accentColorProvider =
    StateProvider<Color>((ref) => AppTheme.defaultAccent);

final contentSortProvider = StateProvider<String>((ref) => 'provider');

// View mode per content type — defaults match Option C smart defaults.
final viewModeLiveProvider = StateProvider<String>((ref) => 'list');
final viewModeMoviesProvider = StateProvider<String>((ref) => 'grid');
final viewModeSeriesProvider = StateProvider<String>((ref) => 'grid');

// Active source — null means show all sources' content combined.
// Initialized from prefs in app.dart after DB is ready.
final activeSourceIdProvider = StateProvider<String?>((ref) => null);

// Background auto-refresh — 0 means off.
final refreshIntervalHoursProvider = StateProvider<int>((ref) => 0);
final refreshNotificationsEnabledProvider = StateProvider<bool>((ref) => true);

// Picture-in-Picture — pipActiveProvider is runtime-only (not persisted),
// updated live by MainActivity via the platform channel in pip_service.dart.
final pipEnabledProvider = StateProvider<bool>((ref) => false);
// Bumped when Home is pressed and Picture-in-Picture isn't going to take
// over: whatever is playing (player, guide preview, multi-view) stops.
final homeLeaveProvider = StateProvider<int>((ref) => 0);
final pipActiveProvider = StateProvider<bool>((ref) => false);

// Now Playing / media notification.
final mediaNotificationEnabledProvider = StateProvider<bool>((ref) => true);

// Tidy provider names for display (see display_name.dart).
final cleanNamesProvider = StateProvider<bool>((ref) => true);

/// Player picture fit: 'fit' (whole picture, letterboxed — the default),
/// 'fill' (crop to fill the screen) or 'zoom' (in between).
final videoFitProvider = StateProvider<String>((ref) => 'fit');

Future<void> setVideoFit(
    WidgetRef ref, String fit, AppPreferences prefs) async {
  ref.read(videoFitProvider.notifier).state = fit;
  await prefs.setVideoFit(fit);
}

// Movies / Series home layout: 'posters' (a rail per genre) or 'compact'
// (the plain genre list).
final homeLayoutMoviesProvider = StateProvider<String>((ref) => 'posters');
final homeLayoutSeriesProvider = StateProvider<String>((ref) => 'posters');

Future<void> setHomeLayoutMovies(
    WidgetRef ref, String layout, AppPreferences prefs) async {
  ref.read(homeLayoutMoviesProvider.notifier).state = layout;
  await prefs.setHomeLayoutMovies(layout);
}

Future<void> setHomeLayoutSeries(
    WidgetRef ref, String layout, AppPreferences prefs) async {
  ref.read(homeLayoutSeriesProvider.notifier).state = layout;
  await prefs.setHomeLayoutSeries(layout);
}

Future<void> setCleanNames(
    WidgetRef ref, bool enabled, AppPreferences prefs) async {
  ref.read(cleanNamesProvider.notifier).state = enabled;
  await prefs.setCleanNames(enabled);
}

// Helpers called from Settings to update prefs + provider in one shot.
Future<void> setAccentColor(
    WidgetRef ref, Color color, AppPreferences prefs) async {
  ref.read(accentColorProvider.notifier).state = color;
  await prefs.setAccentColor(AppTheme.hexFromAccent(color));
}

Future<void> setContentSort(
    WidgetRef ref, String sort, AppPreferences prefs) async {
  ref.read(contentSortProvider.notifier).state = sort;
  await prefs.setContentSort(sort);
}

Future<void> setViewModeLive(
    WidgetRef ref, String mode, AppPreferences prefs) async {
  ref.read(viewModeLiveProvider.notifier).state = mode;
  await prefs.setViewModeLive(mode);
}

Future<void> setViewModeMovies(
    WidgetRef ref, String mode, AppPreferences prefs) async {
  ref.read(viewModeMoviesProvider.notifier).state = mode;
  await prefs.setViewModeMovies(mode);
}

Future<void> setViewModeSeries(
    WidgetRef ref, String mode, AppPreferences prefs) async {
  ref.read(viewModeSeriesProvider.notifier).state = mode;
  await prefs.setViewModeSeries(mode);
}

Future<void> setActiveSource(
    WidgetRef ref, String? id, AppPreferences prefs) async {
  ref.read(activeSourceIdProvider.notifier).state = id;
  await prefs.setActiveSourceId(id);
  debugPrint('[OTV-source] set active=$id');
}

Future<void> setRefreshIntervalHours(
    WidgetRef ref, int hours, AppPreferences prefs) async {
  ref.read(refreshIntervalHoursProvider.notifier).state = hours;
  await prefs.setRefreshIntervalHours(hours);
  await syncAutoRefreshRegistration(prefs);
}

Future<void> setRefreshNotificationsEnabled(
    WidgetRef ref, bool enabled, AppPreferences prefs) async {
  ref.read(refreshNotificationsEnabledProvider.notifier).state = enabled;
  await prefs.setRefreshNotificationsEnabled(enabled);
}

Future<void> setPipEnabled(
    WidgetRef ref, bool enabled, AppPreferences prefs) async {
  ref.read(pipEnabledProvider.notifier).state = enabled;
  await prefs.setPipEnabled(enabled);
  final playing = ref.read(playbackServiceProvider).lastState.playWhenReady;
  await updatePipAvailability(enabled && playing);
}

Future<void> setMediaNotificationEnabled(
    WidgetRef ref, bool enabled, AppPreferences prefs) async {
  ref.read(mediaNotificationEnabledProvider.notifier).state = enabled;
  await prefs.setMediaNotificationEnabled(enabled);
  nowPlayingHandler.setEnabled(enabled);
}

/// Pushes every persisted setting into its runtime StateProvider. These
/// providers are plain state (not derived from [AppPreferences] reactively),
/// so anything that writes prefs out-of-band — app startup, or restoring a
/// backup — must call this afterward or the UI keeps showing stale values
/// until the app restarts.
void syncSettingsProviders(WidgetRef ref, AppPreferences prefs) {
  ref.read(accentColorProvider.notifier).state =
      AppTheme.accentFromHex(prefs.accentColor);
  ref.read(contentSortProvider.notifier).state = prefs.contentSort;
  ref.read(viewModeLiveProvider.notifier).state = prefs.viewModeLive;
  ref.read(viewModeMoviesProvider.notifier).state = prefs.viewModeMovies;
  ref.read(viewModeSeriesProvider.notifier).state = prefs.viewModeSeries;
  ref.read(refreshIntervalHoursProvider.notifier).state =
      prefs.refreshIntervalHours;
  ref.read(refreshNotificationsEnabledProvider.notifier).state =
      prefs.refreshNotificationsEnabled;
  ref.read(pipEnabledProvider.notifier).state = prefs.pipEnabled;
  ref.read(mediaNotificationEnabledProvider.notifier).state =
      prefs.mediaNotificationEnabled;
  nowPlayingHandler.setEnabled(prefs.mediaNotificationEnabled);
  ref.read(cleanNamesProvider.notifier).state = prefs.cleanNames;
  ref.read(videoFitProvider.notifier).state = prefs.videoFit;
  ref.read(homeLayoutMoviesProvider.notifier).state = prefs.homeLayoutMovies;
  ref.read(homeLayoutSeriesProvider.notifier).state = prefs.homeLayoutSeries;
}
