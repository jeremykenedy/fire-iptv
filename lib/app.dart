import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_iptv/core/providers/theme_providers.dart';
import 'package:open_iptv/core/providers/channel_providers.dart';
import 'package:open_iptv/core/services/home_channel_cards.dart';
import 'package:open_iptv/core/services/cast_service.dart';
import 'package:open_iptv/core/services/auto_refresh_service.dart';
import 'package:open_iptv/core/services/pip_service.dart';
import 'package:open_iptv/core/services/playback_service.dart';
import 'package:open_iptv/core/services/vpn_service.dart';
import 'package:open_iptv/core/services/profile_service.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/core/services/tv_text_input.dart';
import 'package:open_iptv/features/live_tv/channel_list_screen.dart';
import 'package:open_iptv/features/movies/movie_detail_screen.dart';
import 'package:open_iptv/features/movies/movies_screen.dart';
import 'package:open_iptv/features/discover/discover_screen.dart';
import 'package:open_iptv/features/live_tv/tv_guide_screen.dart';
import 'package:open_iptv/core/services/starter_catalog.dart';
import 'package:open_iptv/core/services/epg_service.dart';
import 'package:open_iptv/features/onboarding/setup_wizard_screen.dart';
import 'package:open_iptv/features/player/player_screen.dart';
import 'package:open_iptv/features/search/search_screen.dart';
import 'package:open_iptv/features/series/series_detail_screen.dart';
import 'package:open_iptv/features/series/series_screen.dart';
import 'package:open_iptv/features/player/cast_ui.dart';
import 'package:open_iptv/features/updates/update_dialog.dart';
import 'package:open_iptv/features/settings/backup_screen.dart';
import 'package:open_iptv/features/settings/parental_screen.dart';
import 'package:open_iptv/features/settings/power_user_screen.dart';
import 'package:open_iptv/features/settings/profile_picker_screen.dart';
import 'package:open_iptv/features/settings/profile_screen.dart';
import 'package:open_iptv/features/settings/settings_screen.dart';
import 'package:open_iptv/shared/utils/display_name.dart';
import 'package:open_iptv/shared/theme/app_theme.dart';
import 'package:open_iptv/shared/widgets/brand_splash.dart';
import 'package:open_iptv/shared/widgets/info_tooltip.dart';
import 'package:open_iptv/shared/widgets/tv_focusable.dart';
import 'package:open_iptv/shared/widgets/tv_nav_rail_focus.dart';
import 'package:open_iptv/ui/platform_helper.dart';

class OpenIPTVApp extends ConsumerStatefulWidget {
  const OpenIPTVApp({super.key});

  @override
  ConsumerState<OpenIPTVApp> createState() => _OpenIPTVAppState();
}

class _OpenIPTVAppState extends ConsumerState<OpenIPTVApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  final _tooltipController = InfoTooltipController();
  bool _dbReady = false;
  String? _startupError;
  bool _skipStarter = false;
  // True while multiple profiles exist and the user hasn't picked one yet
  // this session.
  bool _needsProfilePick = false;
  Timer? _homeCardTimer;
  int _homeCardRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = _buildRouter();
    _router.routeInformationProvider.addListener(_scheduleHomeCards);
    if (PlatformHelper.isTVDevice) {
      HomeChannelCards.channel.setMethodCallHandler((call) async {
        if (call.method == 'linkAvailable') await _openHomeChannel();
      });
    }
    _openDb();
  }

  Future<void> _openDb() async {
    if (mounted && _startupError != null) {
      setState(() => _startupError = null);
    }
    const maxAttempts = 5;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        await ref.read(appDatabaseProvider).customSelect('SELECT 1').get();
        break;
      } catch (e) {
        if (attempt == maxAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    final db = ref.read(appDatabaseProvider);
    final prefs = await ref.read(appPreferencesProvider.future);

    if (!_skipStarter) {
      try {
        final installed = await StarterCatalog(
          db: db,
          preferences: prefs,
        ).install();
        final guide = ref.read(epgServiceProvider);
        unawaited(() async {
          for (final source in installed) {
            try {
              await guide.refreshEpg(source);
            } catch (_) {
              // Live TV remains available when a guide feed is offline.
            }
          }
        }());
      } catch (_) {
        if (mounted) {
          setState(
            () => _startupError =
                'The starter library could not be prepared. Try again, or add your own playlist.',
          );
        }
        return;
      }
    }

    // Re-sync the background auto-refresh registration against the
    // persisted interval — WorkManager can drop periodic registrations
    // across OS updates or force-stops, so this must run on every launch,
    // not just when the user changes the setting.
    unawaited(syncAutoRefreshRegistration(prefs));

    // Power User Tools: bring the built-in VPN up if asked to. Never
    // prompts and never blocks start-up.
    unawaited(VpnService().autoConnect(prefs));

    // Initialise accent + sort state from persisted preferences.
    syncSettingsProviders(ref, prefs);
    ref.read(activeSourceIdProvider.notifier).state = prefs.activeSourceId;
    // Diagnostics: the active playlist has twice been seen reset to another
    // playlist across app updates, with no code path found that writes it.
    debugPrint('[OTV-source] startup active=${prefs.activeSourceId}');

    initPipChannel(
      onPipModeChanged: (isInPip) =>
          ref.read(pipActiveProvider.notifier).state = isInPip,
      // The PiP window was closed: stop what was playing in it.
      onPipDismissed: () => ref.read(homeLeaveProvider.notifier).state++,
      onUserLeft: () {
        // Picture-in-Picture off: Home stops playback. (With it on, native
        // enters PiP and never reports this.) Casting keeps going — the
        // phone is only the remote.
        if (ref.read(pipEnabledProvider)) return;
        if (!ref.read(playbackServiceProvider).lastState.playWhenReady) return;
        if (ref.read(castServiceProvider).status.connected) return;
        ref.read(homeLeaveProvider.notifier).state++;
      },
    );
    void pushPipAvailability() {
      final playing = ref.read(playbackServiceProvider).lastState.playWhenReady;
      updatePipAvailability(ref.read(pipEnabledProvider) && playing);
    }

    pushPipAvailability();
    ref
        .read(playbackServiceProvider)
        .stateStream
        .listen((_) => pushPipAvailability());

    // Profile setup.
    final profiles = await db.getAllProfiles();
    if (profiles.length == 1) {
      // Auto-select single profile (no picker needed).
      await prefs.setActiveProfileId(profiles.first.id);
    }

    final needsPick = profiles.length > 1;

    if (mounted) {
      setState(() {
        _dbReady = true;
        _needsProfilePick = needsPick;
      });
      _scheduleHomeCards();
      WidgetsBinding.instance.addPostFrameCallback((_) => _openHomeChannel());
    }
  }

  void _scheduleHomeCards() {
    if (!PlatformHelper.isTVDevice || !_dbReady || !mounted) return;
    final revision = ++_homeCardRevision;
    _homeCardTimer?.cancel();
    _homeCardTimer = Timer(const Duration(milliseconds: 250), () async {
      try {
        final prefs = await ref.read(appPreferencesProvider.future);
        final profile = await ref.read(activeProfileProvider.future);
        final channels = await ref
            .read(appDatabaseProvider)
            .getAllChannels(profileId: profile?.id);
        if (!mounted || revision != _homeCardRevision) return;
        await HomeChannelCards.sync(_needsProfilePick
            ? const []
            : homeChannelCards(channels, profile, prefs));
      } catch (error) {
        debugPrint('Home cards refresh unavailable: ${error.runtimeType}');
      }
    });
  }

  Future<void> _openHomeChannel() async {
    if (!mounted || !_dbReady || _needsProfilePick) return;
    final link = await HomeChannelCards.takePendingLink();
    final id = homeChannelId(link);
    if (id == null || !mounted) return;
    final prefs = await ref.read(appPreferencesProvider.future);
    final profile = await ref.read(activeProfileProvider.future);
    final channel = await ref.read(appDatabaseProvider).getChannelById(id);
    if (!mounted) return;
    if (channel == null || !canOpenHomeChannel(channel, profile, prefs)) {
      _router.go('/live');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _rootNavigatorKey.currentContext;
        if (context != null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('This channel is no longer available in this profile.'),
          ));
        }
      });
      return;
    }
    final extra = <String, dynamic>{
      'streamUrl': channel.streamUrl,
      'title': channel.name,
      'contentId': channel.id,
      'contentType': 'channel',
    };
    if (_router.routeInformationProvider.value.uri.path == '/player') {
      ref.read(playbackServiceProvider).markTransitioning();
      unawaited(_router.pushReplacement('/player', extra: extra));
    } else {
      unawaited(_router.push('/player', extra: extra));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleHomeCards();
      unawaited(_openHomeChannel());
    } else if (state == AppLifecycleState.inactive) {
      _scheduleHomeCards();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _homeCardTimer?.cancel();
    _router.routeInformationProvider.removeListener(_scheduleHomeCards);
    if (PlatformHelper.isTVDevice) {
      HomeChannelCards.channel.setMethodCallHandler(null);
    }
    _tooltipController.dispose();
    super.dispose();
  }

  GoRouter _buildRouter() {
    return GoRouter(
      navigatorKey: _rootNavigatorKey,
      initialLocation: '/discover',
      redirect: (context, state) async {
        final path = state.fullPath ?? '';
        if (path.startsWith('/setup') || path.startsWith('/onboarding')) {
          return null;
        }
        final db = ref.read(appDatabaseProvider);
        final profiles = await db.getAllProfiles();
        final sources = await db.getAllSources();
        if (profiles.isEmpty && sources.isEmpty) return '/setup';
        if (sources.isEmpty) return '/onboarding';

        if (path.startsWith('/settings/parental') ||
            path.startsWith('/settings/backup')) {
          final activeProfile = await ref.read(activeProfileProvider.future);
          if (activeProfile == null || !activeProfile.isAdmin) {
            return '/settings';
          }
        }
        return null;
      },
      routes: [
        GoRoute(
          path: '/setup',
          builder: (_, __) => const SetupWizardScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (_, __) => const SetupWizardScreen(addPlaylistOnly: true),
        ),
        ShellRoute(
          navigatorKey: _shellNavigatorKey,
          builder: (context, state, child) => _Shell(child: child),
          routes: [
            GoRoute(
              path: '/discover',
              builder: (_, __) => const DiscoverScreen(),
            ),
            GoRoute(
              path: '/sports',
              builder: (_, __) => const TvGuideScreen(sportsOnly: true),
            ),
            GoRoute(
              path: '/live',
              builder: (_, __) => const ChannelListScreen(),
              routes: [
                GoRoute(
                  path: 'category/:cat',
                  builder: (_, state) => LiveCategoryScreen(
                    category: state.pathParameters['cat']!,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/movies',
              builder: (_, __) => const MoviesScreen(),
              routes: [
                GoRoute(
                  path: 'genre/:genre',
                  builder: (_, state) => MovieGenreScreen(
                    genre: state.pathParameters['genre']!,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/series',
              builder: (_, __) => const SeriesScreen(),
              routes: [
                GoRoute(
                  path: 'genre/:genre',
                  builder: (_, state) => SeriesGenreScreen(
                    genre: state.pathParameters['genre']!,
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/search',
              builder: (_, __) => const SearchScreen(),
            ),
            // A tab since 0.12.1 (the gear in the top corner confused
            // people); its pages stay inside the shell, under the nav.
            GoRoute(
              path: '/settings',
              builder: (_, __) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'profiles',
                  builder: (_, __) => const ProfileScreen(),
                ),
                GoRoute(
                  path: 'backup',
                  builder: (_, __) => const BackupScreen(),
                ),
                GoRoute(
                  path: 'parental',
                  builder: (_, __) => const ParentalScreen(),
                ),
                GoRoute(
                  path: 'power-tools',
                  builder: (_, __) => const PowerUserScreen(),
                ),
              ],
            ),
          ],
        ),
        // Detail pages on the root navigator, outside the shell (same as
        // the player).
        GoRoute(
          path: '/movies/:id',
          builder: (_, state) => MovieDetailScreen(
            movieId: state.pathParameters['id']!,
            // The tapped poster's Hero tag, when opened from a poster.
            heroTag: state.extra is String ? state.extra as String : null,
          ),
        ),
        GoRoute(
          path: '/series/:id',
          builder: (_, state) => SeriesDetailScreen(
            seriesId: state.pathParameters['id']!,
            heroTag: state.extra is String ? state.extra as String : null,
          ),
        ),
        GoRoute(
          path: '/player',
          builder: (_, state) {
            final extra = state.extra as Map<String, dynamic>;
            return PlayerScreen(
              streamUrl: extra['streamUrl'] as String,
              title: extra['title'] as String,
              contentId: extra['contentId'] as String?,
              contentType: extra['contentType'] as String?,
              resumePosition: extra['resumePosition'] as Duration?,
              confirmResume: extra['confirmResume'] as bool? ?? true,
              seriesId: extra['seriesId'] as String?,
              continuePlaying: extra['continuePlaying'] as bool? ?? false,
              handBackTo: extra['handBackTo'],
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accent = ref.watch(accentColorProvider);
    ref.listen(allChannelsProvider, (_, __) => _scheduleHomeCards());
    ref.listen(activeProfileProvider, (_, __) => _scheduleHomeCards());
    ref.listen(activeSourceIdProvider, (_, __) => _scheduleHomeCards());

    if (!_dbReady) {
      if (_startupError != null) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.dark(accent),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_startupError!, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    FilledButton(
                      autofocus: true,
                      onPressed: _openDb,
                      child: const Text('Try again'),
                    ),
                    TextButton(
                      onPressed: () {
                        _skipStarter = true;
                        unawaited(_openDb());
                      },
                      child: const Text('Add my playlist'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: BrandSplash(),
      );
    }

    // Show profile picker before mounting the router when multiple
    // profiles exist and the user hasn't selected one this session.
    if (_needsProfilePick) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        shortcuts: appShortcuts,
        theme: AppTheme.dark(accent),
        darkTheme: AppTheme.dark(accent),
        themeMode: ThemeMode.dark,
        home: ProfilePickerScreen(
          onPicked: () {
            setState(() => _needsProfilePick = false);
            _scheduleHomeCards();
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _openHomeChannel());
          },
        ),
      );
    }

    return InfoTooltipScope(
      controller: _tooltipController,
      child: MaterialApp.router(
        title: 'fire-iptv',
        theme: AppTheme.dark(accent),
        darkTheme: AppTheme.dark(accent),
        themeMode: ThemeMode.dark,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
        shortcuts: appShortcuts,
        builder: (context, child) => DisplayNames(
          enabled: ref.watch(cleanNamesProvider),
          child: TvKeyboardInset(
            child: TvTextFieldEscape(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}

// Held so the native Back handler can see what's stacked above a root tab.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _shellNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'shell');

class _Shell extends StatefulWidget {
  const _Shell({required this.child});

  final Widget child;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  // When the first Back on the home tab asked "press again to exit".
  DateTime? _exitArmedAt;
  static const _exitWindow = Duration(seconds: 2);

  // Root-tab back handling is done via a native MethodChannel rather than
  // Flutter's PopScope/OnBackInvokedCallback: empirically, a PopScope
  // wrapping this shell's content never actually stopped the system from
  // closing the Activity here, even hard-coded to canPop:false (verified via
  // an on-screen counter — its onPopInvokedWithResult callback never fired
  // before the app closed). Handling Back directly in MainActivity.kt
  // sidesteps whatever that mismatch was: Dart tells native whether a root
  // tab is showing (nothing left to pop, otherwise closing the app instead
  // of doing nothing), and native either lets the press through normally
  // (sub-routes like /movies/genre/action keep popping exactly as before)
  // or calls back into Dart to decide what "Back" should do here.
  static const _backChannel = MethodChannel('openiptv/back');
  bool? _lastReportedBlocked;

  // One node per rail item, each bound to its item for good. (A single
  // "active item" node handed from item to item on every tab change lost
  // focus in the hand-over and left the old item's glow lit — #39.) The
  // active tab's node is refocused explicitly when arrow-left has nowhere
  // left to go within the content pane (EdgeAwareDirectionalFocusAction)
  // and by Back, rather than relying on Flutter's directional traversal to
  // jump from a scrollable page across into this separate column.
  final List<FocusNode> _railNodes = [
    for (final d in _kNavDestinations)
      FocusNode(debugLabel: 'NavRail ${d.label}'),
  ];
  FocusNode get _activeRailNode => _railNodes[_navIndexForLocation(context)];

  // Set when Back sends the remote to the rail. Until the user leaves the
  // rail themselves (Right into the page, or picking a tab), focus that
  // the shell's pages take on their own — a route being pushed, a first
  // item autofocusing once its data loads — is handed back to the rail.
  bool _holdRail = false;
  FocusNode? _lastRailFocus;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_trackContentFocus);
    // Sideloaded installs have no store to update them — offer new GitHub
    // releases. Runs once the main UI is up (i.e. after setup and the
    // profile picker); throttled and admin-only inside.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
    // …and again when the app is brought back from the background (Android
    // usually keeps it running, so that isn't a fresh launch).
    WidgetsBinding.instance.addObserver(this);
    _backChannel.setMethodCallHandler((call) async {
      if (call.method == 'backPressed') _handleNativeBackPressed();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  void _checkForUpdate() {
    if (!mounted) return;
    unawaited(maybePromptForUpdate(
      context,
      // Never over a video that's playing.
      busy: () => PlayerScreen.openCount > 0,
    ));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_trackContentFocus);
    _backChannel.setMethodCallHandler(null);
    for (final n in _railNodes) {
      n.dispose();
    }
    super.dispose();
  }

  // The last thing focused in the content pane (never a rail item). Pages
  // pushed or popped in the shell move focus themselves, so this always
  // belongs to the visible page — unlike directional search from the rail,
  // which can reach items of a page covered by the one on top.
  FocusNode? _lastContentFocus;

  void _trackContentFocus() {
    final f = FocusManager.instance.primaryFocus;
    if (f == null) return;
    if (f.context?.findAncestorWidgetOfExactType<_TvNavRail>() != null) {
      _lastRailFocus = f;
      return;
    }
    if (f is! FocusScopeNode) _lastContentFocus = f;
    if (_holdRail && _inShellPage(f)) {
      // Still remembered above: what the page focused first is where Right
      // from the rail goes.
      scheduleMicrotask(() {
        if (mounted && _holdRail) {
          (_lastRailFocus ?? _activeRailNode).requestFocus();
        }
      });
    }
  }

  // In one of the tab pages (not a dialog, sheet or page on the root
  // navigator above them).
  bool _inShellPage(FocusNode f) {
    final c = f.context;
    return c != null && Navigator.maybeOf(c) == _shellNavigatorKey.currentState;
  }

  bool _focusContent() {
    _holdRail = false;
    final f = _lastContentFocus;
    if (f == null || f.context == null || !f.canRequestFocus) return false;
    f.requestFocus();
    return true;
  }

  // Back on a tab root, the same on phones and TVs (#39):
  //  1. anything stacked on top (page, sheet, dialog, menu) closes;
  //  2. TV: focus inside the page moves to the side menu first;
  //  3. Movies, Series or Search go to the home tab (Live TV);
  //  4. on Live TV the first press asks "press again to exit", and a
  //     second press within two seconds leaves the app.
  void _handleNativeBackPressed() {
    if (!mounted) return;
    // Native blocks Back based on the shell's own location, which stays on
    // the tab root while a page (/settings, /player, detail screens) or a
    // dialog/bottom sheet sits above it. Anything stacked on top owns Back.
    for (final nav in [
      _rootNavigatorKey.currentState,
      _shellNavigatorKey.currentState,
    ]) {
      if (nav != null && nav.canPop()) {
        unawaited(nav.maybePop());
        return;
      }
    }
    final tv = PlatformHelper.isTV(context);
    if (tv && !_railHasFocus()) {
      _exitArmedAt = null;
      _holdRail = true;
      _activeRailNode.requestFocus();
      return;
    }
    if (_navIndexForLocation(context) != 0) {
      _exitArmedAt = null;
      context.go(_kNavDestinations.first.path);
      if (tv) {
        // The rail keeps the remote, on Live TV's item.
        _holdRail = true;
        _railNodes.first.requestFocus();
      }
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final armed = _exitArmedAt;
    if (armed != null && DateTime.now().difference(armed) < _exitWindow) {
      _exitArmedAt = null;
      messenger.hideCurrentSnackBar();
      // Like Android's own Back on a launcher activity: to the background,
      // state kept (not finished — the shared audio_service engine
      // outlives the activity anyway).
      unawaited(_backChannel.invokeMethod('moveToBack'));
      return;
    }
    _exitArmedAt = DateTime.now();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press Back again to exit'),
          duration: _exitWindow,
        ),
      );
  }

  bool _railHasFocus() =>
      FocusManager.instance.primaryFocus?.context
          ?.findAncestorWidgetOfExactType<_TvNavRail>() !=
      null;

  @override
  Widget build(BuildContext context) {
    // True only when sitting exactly at one of the tab roots (not a pushed
    // sub-route like /movies/genre/action, which the shell's own nested
    // Navigator still pops normally — native only intervenes when told to).
    final location = GoRouterState.of(context).uri.path;
    final isRootTab = _kNavDestinations.any((d) => d.path == location);
    if (_lastReportedBlocked != isRootTab) {
      _lastReportedBlocked = isRootTab;
      unawaited(_backChannel.invokeMethod('setBlocked', isRootTab));
    }

    if (PlatformHelper.isTV(context)) {
      return Scaffold(
        // The TV keyboard floats over the middle of the screen, never over
        // the rail: the rail keeps its full height (it used to shrink to
        // the space above the keyboard — icons jumped up and its background
        // stopped halfway). Pages inside still make room for the keyboard
        // with their own Scaffolds.
        resizeToAvoidBottomInset: false,
        body: Actions(
          actions: {
            DirectionalFocusIntent: EdgeAwareDirectionalFocusAction(
              directions: {TraversalDirection.left},
              onNoMove: () => _activeRailNode.requestFocus(),
            ),
          },
          child: Row(
            children: [
              _TvNavRail(
                nodes: _railNodes,
                onEnterContent: _focusContent,
                onSelect: () => _holdRail = false,
              ),
              Expanded(
                child: TvNavRailFocus(
                  focusNode: _activeRailNode,
                  child: widget.child,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // "Now casting" bar while something plays on a cast device.
          CastMiniBar(),
          _BottomNav(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared tab destinations — one source of truth for phone bottom nav and TV
// side rail, so the two chrome styles can't drift out of sync.
// ---------------------------------------------------------------------------

class _NavDestination {
  const _NavDestination(this.icon, this.label, this.path, {this.selectedIcon});
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final String path;
}

const _kNavDestinations = [
  _NavDestination(Icons.explore_outlined, 'Discover', '/discover',
      selectedIcon: Icons.explore),
  _NavDestination(Icons.live_tv_outlined, 'Live TV', '/live',
      selectedIcon: Icons.live_tv),
  _NavDestination(Icons.sports_outlined, 'Sports', '/sports',
      selectedIcon: Icons.sports),
  _NavDestination(Icons.movie_outlined, 'Movies', '/movies',
      selectedIcon: Icons.movie),
  _NavDestination(Icons.video_library_outlined, 'Series', '/series',
      selectedIcon: Icons.video_library),
  _NavDestination(Icons.search, 'Search', '/search',
      selectedIcon: Icons.search),
  _NavDestination(Icons.settings_outlined, 'Settings', '/settings',
      selectedIcon: Icons.settings),
];

int _navIndexForLocation(BuildContext context) {
  final location = GoRouterState.of(context).fullPath ?? '/live';
  for (var i = _kNavDestinations.length - 1; i >= 0; i--) {
    if (location.startsWith(_kNavDestinations[i].path)) return i;
  }
  return 0;
}

class _BottomNav extends StatelessWidget {
  const _BottomNav();

  @override
  Widget build(BuildContext context) {
    final index = _navIndexForLocation(context);

    // Material 3 navigation bar: pill indicator behind the active tab,
    // filled icon when selected.
    return NavigationBar(
      selectedIndex: index,
      onDestinationSelected: (i) => context.go(_kNavDestinations[i].path),
      destinations: [
        for (final d in _kNavDestinations)
          NavigationDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon ?? d.icon),
            label: d.label,
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// TV side rail — replaces the bottom bar on Android TV. Hand-built (not
// Flutter's NavigationRail) so each destination is a chunky, obviously
// focusable TvFocusable target rather than NavigationRail's denser default
// touch-target sizing.
// ---------------------------------------------------------------------------

class _TvNavRail extends StatefulWidget {
  const _TvNavRail({
    required this.nodes,
    required this.onEnterContent,
    required this.onSelect,
  });

  // Moves focus back into the content pane; false if there's nowhere known.
  final bool Function() onEnterContent;

  // Called when a destination is picked, before navigating.
  final VoidCallback onSelect;

  // The shell's node for each destination, in _kNavDestinations order.
  final List<FocusNode> nodes;

  @override
  State<_TvNavRail> createState() => _TvNavRailState();
}

class _TvNavRailState extends State<_TvNavRail> {
  // Up/Down move between rail items only. Left to Flutter's directional
  // search, Down from an item could land in a *covered* page of the shell
  // navigator (e.g. the Live TV home under a category page) — invisible
  // focus, and OK then opened a category the user couldn't see.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      // Back into the *visible* page, where focus last was. Directional
      // search could otherwise pick a card in a page covered by it.
      return widget.onEnterContent()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    final delta = key == LogicalKeyboardKey.arrowDown
        ? 1
        : key == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (delta == 0) return KeyEventResult.ignored;
    final current = widget.nodes.indexWhere((n) => n.hasPrimaryFocus);
    if (current < 0) return KeyEventResult.ignored;
    final target = (current + delta).clamp(0, widget.nodes.length - 1);
    widget.nodes[target].requestFocus();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = _navIndexForLocation(context);

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Container(
        width: 96,
        color: theme.colorScheme.surface,
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _kNavDestinations.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: _TvNavRailItem(
                    icon: _kNavDestinations[i].icon,
                    label: _kNavDestinations[i].label,
                    active: i == index,
                    // Only the very first item auto-claims focus, and only on
                    // the rail's initial mount (cold app start, landing on
                    // Live TV) — NOT `i == index`, which would re-fire
                    // autofocus on every navigation.
                    autofocus: i == 0,
                    focusNode: widget.nodes[i],
                    onTap: () {
                      // Picking a tab hands the remote to that page: drop
                      // focus so its first item's autofocus takes it.
                      widget.onSelect();
                      FocusManager.instance.primaryFocus?.unfocus();
                      context.go(_kNavDestinations[i].path);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// A soft glowing pill (rather than TvFocusable's default hard-edged border
// box) with a subtle scale pop on focus — reads as more deliberate/"designed"
// for a rail the user dwells on and arrows up/down through, vs. the generic
// ring used for one-off targets elsewhere in the app. Active-route coloring
// (icon/label tinted `colorScheme.primary` when this is the current screen)
// is untouched — that's driven entirely by `active`, independent of focus.
class _TvNavRailItem extends StatefulWidget {
  const _TvNavRailItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.autofocus = false,
    this.focusNode,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool autofocus;
  final FocusNode? focusNode;

  @override
  State<_TvNavRailItem> createState() => _TvNavRailItemState();
}

class _TvNavRailItemState extends State<_TvNavRailItem> {
  bool _focused = false;

  static const _duration = Duration(milliseconds: 200);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final color = widget.active ? accent : theme.colorScheme.onSurfaceVariant;

    return TvFocusable(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      onTap: widget.onTap,
      showFocusRing: false,
      onFocusChange: (focused) => setState(() => _focused = focused),
      child: AnimatedScale(
        scale: _focused ? 1.08 : 1.0,
        duration: _duration,
        curve: _curve,
        child: AnimatedContainer(
          duration: _duration,
          curve: _curve,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          decoration: BoxDecoration(
            color:
                _focused ? accent.withValues(alpha: 0.16) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 18,
                    ),
                  ]
                : const [],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 28, color: color),
              const SizedBox(height: 4),
              Text(
                widget.label,
                style: theme.textTheme.labelSmall!.copyWith(color: color),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
