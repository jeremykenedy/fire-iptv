import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'preferences.g.dart';

const _kActiveProfileId = 'active_profile_id';
const _kActiveSourceId = 'active_source_id';
const _kAccentColor = 'accent_color'; // hex string e.g. '0A84FF'
const _kContentSort = 'content_sort'; // 'az' | 'provider'
const _kChannelListDensity = 'channel_list_density'; // 'comfortable' | 'compact'
const _kViewModeLive = 'view_mode_live';       // 'list' | 'grid'
const _kViewModeMovies = 'view_mode_movies';   // 'list' | 'grid'
const _kViewModeSeries = 'view_mode_series';   // 'list' | 'grid'
const _kParentalProtectionEnabled = 'parental_protection_enabled';
const _kParentalLockedCats = 'parental_locked_cats';
const _kParentalScanDone = 'parental_scan_done';
// Device-only (never in backups): fingerprint / face in place of the admin PIN.
const _kAdminBiometricUnlock = 'admin_biometric_unlock';
const _kRefreshIntervalHours = 'refresh_interval_hours'; // 0 = off
const _kLastRegisteredRefreshIntervalHours = 'last_registered_refresh_interval_hours';
const _kRefreshNotificationsEnabled = 'refresh_notifications_enabled';
const _kPipEnabled = 'pip_enabled';
const _kMediaNotificationEnabled = 'media_notification_enabled';
const _kAutoUpdateCheck = 'auto_update_check';
const _kCleanNames = 'clean_names';
const _kRecentSearches = 'recent_searches';
const _kVideoFit = 'video_fit'; // 'fit' | 'fill' | 'zoom'
const _kBufferPreset = 'buffer_preset'; // see BufferPreset ids
const _kVpnRoute = 'vpn_route'; // 'app' | 'device'
const _kVpnAutoConnect = 'vpn_auto_connect';
const _kVpnKind = 'vpn_kind'; // 'wireguard' | 'openvpn' (last connected)
const _kHomeLayoutMovies = 'home_layout_movies'; // 'posters' | 'compact'
const _kHomeLayoutSeries = 'home_layout_series'; // 'posters' | 'compact'
const _kLastUpdateCheckMs = 'last_update_check_ms';
const _kSkippedUpdateVersion = 'skipped_update_version';

@Riverpod(keepAlive: true)
Future<AppPreferences> appPreferences(AppPreferencesRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  return AppPreferences(prefs);
}

class AppPreferences {
  AppPreferences(this._prefs);

  final SharedPreferences _prefs;

  String? get starterCatalogRevision =>
      _prefs.getString('fire_iptv_catalog_revision');
  Future<void> setStarterCatalogRevision(String revision) =>
      _prefs.setString('fire_iptv_catalog_revision', revision);

  String? get activeProfileId => _prefs.getString(_kActiveProfileId);
  Future<void> setActiveProfileId(String id) =>
      _prefs.setString(_kActiveProfileId, id);

  String? get activeSourceId => _prefs.getString(_kActiveSourceId);
  Future<void> setActiveSourceId(String? id) =>
      id != null ? _prefs.setString(_kActiveSourceId, id) : _prefs.remove(_kActiveSourceId);

  String get accentColor => _prefs.getString(_kAccentColor) ?? '0A84FF';
  Future<void> setAccentColor(String hex) =>
      _prefs.setString(_kAccentColor, hex);

  String get contentSort => _prefs.getString(_kContentSort) ?? 'provider';
  Future<void> setContentSort(String sort) =>
      _prefs.setString(_kContentSort, sort);

  String get channelListDensity =>
      _prefs.getString(_kChannelListDensity) ?? 'comfortable';
  Future<void> setChannelListDensity(String density) =>
      _prefs.setString(_kChannelListDensity, density);

  String get viewModeLive => _prefs.getString(_kViewModeLive) ?? 'list';
  Future<void> setViewModeLive(String mode) =>
      _prefs.setString(_kViewModeLive, mode);

  String get viewModeMovies => _prefs.getString(_kViewModeMovies) ?? 'grid';
  Future<void> setViewModeMovies(String mode) =>
      _prefs.setString(_kViewModeMovies, mode);

  String get viewModeSeries => _prefs.getString(_kViewModeSeries) ?? 'grid';
  Future<void> setViewModeSeries(String mode) =>
      _prefs.setString(_kViewModeSeries, mode);

  // Parental controls
  bool get parentalProtectionEnabled =>
      _prefs.getBool(_kParentalProtectionEnabled) ?? false;
  Future<void> setParentalProtectionEnabled(bool v) =>
      _prefs.setBool(_kParentalProtectionEnabled, v);

  List<String> get parentalLockedCategories =>
      _prefs.getStringList(_kParentalLockedCats) ?? [];
  Future<void> setParentalLockedCategories(List<String> cats) =>
      _prefs.setStringList(_kParentalLockedCats, cats);

  /// Fingerprint / face may stand in for the admin PIN on this device
  /// (#47). Turned on under profile → Security with the admin PIN.
  bool get adminBiometricUnlock =>
      _prefs.getBool(_kAdminBiometricUnlock) ?? false;
  Future<void> setAdminBiometricUnlock(bool v) =>
      _prefs.setBool(_kAdminBiometricUnlock, v);

  bool get parentalScanDone => _prefs.getBool(_kParentalScanDone) ?? false;
  Future<void> setParentalScanDone(bool v) =>
      _prefs.setBool(_kParentalScanDone, v);

  // Background auto-refresh
  int get refreshIntervalHours =>
      _prefs.getInt(_kRefreshIntervalHours) ?? 0;
  Future<void> setRefreshIntervalHours(int hours) =>
      _prefs.setInt(_kRefreshIntervalHours, hours);

  /// Bookkeeping only — the interval WorkManager was last registered with.
  /// Used to decide whether the periodic task needs re-registering, since
  /// WorkManager has no API to read back a task's currently-set interval.
  int get lastRegisteredRefreshIntervalHours =>
      _prefs.getInt(_kLastRegisteredRefreshIntervalHours) ?? 0;
  Future<void> setLastRegisteredRefreshIntervalHours(int hours) =>
      _prefs.setInt(_kLastRegisteredRefreshIntervalHours, hours);

  bool get refreshNotificationsEnabled =>
      _prefs.getBool(_kRefreshNotificationsEnabled) ?? true;
  Future<void> setRefreshNotificationsEnabled(bool v) =>
      _prefs.setBool(_kRefreshNotificationsEnabled, v);

  // Picture-in-Picture
  bool get pipEnabled => _prefs.getBool(_kPipEnabled) ?? false;
  Future<void> setPipEnabled(bool v) => _prefs.setBool(_kPipEnabled, v);

  // Now Playing / media notification
  bool get mediaNotificationEnabled =>
      _prefs.getBool(_kMediaNotificationEnabled) ?? true;
  Future<void> setMediaNotificationEnabled(bool v) =>
      _prefs.setBool(_kMediaNotificationEnabled, v);

  // Tidy provider names for display (display_name.dart).
  // Player: how the picture fits the screen.
  String get videoFit => _prefs.getString(_kVideoFit) ?? 'fit';
  Future<void> setVideoFit(String v) => _prefs.setString(_kVideoFit, v);

  /// Player buffer size (Power User Tools); null = the default.
  String? get bufferPreset => _prefs.getString(_kBufferPreset);
  Future<void> setBufferPreset(String v) =>
      _prefs.setString(_kBufferPreset, v);

  /// Built-in VPN: send only OpenIPTV ('app', default) or the whole device
  /// ('device') through the tunnel; and whether to connect on app start.
  String get vpnRoute => _prefs.getString(_kVpnRoute) ?? 'app';
  Future<void> setVpnRoute(String v) => _prefs.setString(_kVpnRoute, v);
  bool get vpnAutoConnect => _prefs.getBool(_kVpnAutoConnect) ?? false;
  Future<void> setVpnAutoConnect(bool v) =>
      _prefs.setBool(_kVpnAutoConnect, v);
  String get vpnKind => _prefs.getString(_kVpnKind) ?? 'wireguard';
  Future<void> setVpnKind(String v) => _prefs.setString(_kVpnKind, v);

  // Search: the last few queries that led somewhere, newest first.
  List<String> get recentSearches =>
      _prefs.getStringList(_kRecentSearches) ?? const [];
  Future<void> setRecentSearches(List<String> v) =>
      _prefs.setStringList(_kRecentSearches, v);

  bool get cleanNames => _prefs.getBool(_kCleanNames) ?? true;
  Future<void> setCleanNames(bool v) => _prefs.setBool(_kCleanNames, v);

  // Movies / Series home: genre poster rails or the compact genre list.
  String get homeLayoutMovies =>
      _prefs.getString(_kHomeLayoutMovies) ?? 'posters';
  Future<void> setHomeLayoutMovies(String v) =>
      _prefs.setString(_kHomeLayoutMovies, v);

  String get homeLayoutSeries =>
      _prefs.getString(_kHomeLayoutSeries) ?? 'posters';
  Future<void> setHomeLayoutSeries(String v) =>
      _prefs.setString(_kHomeLayoutSeries, v);

  // Sideload self-updater (see update_service.dart)
  bool get autoUpdateCheck => _prefs.getBool(_kAutoUpdateCheck) ?? true;
  Future<void> setAutoUpdateCheck(bool v) =>
      _prefs.setBool(_kAutoUpdateCheck, v);

  DateTime? get lastUpdateCheck {
    final ms = _prefs.getInt(_kLastUpdateCheckMs);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastUpdateCheck(DateTime t) =>
      _prefs.setInt(_kLastUpdateCheckMs, t.millisecondsSinceEpoch);

  /// A release the user chose "Skip this version" for — not offered again
  /// automatically (a manual check still shows it).
  String? get skippedUpdateVersion => _prefs.getString(_kSkippedUpdateVersion);
  Future<void> setSkippedUpdateVersion(String? v) => v == null
      ? _prefs.remove(_kSkippedUpdateVersion)
      : _prefs.setString(_kSkippedUpdateVersion, v);
}
