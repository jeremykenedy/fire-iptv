import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_iptv/core/models/channel.dart';
import 'package:open_iptv/features/discover/discovery.dart';
import 'package:open_iptv/core/models/programme.dart';
import 'package:open_iptv/core/providers/channel_providers.dart';
import 'package:open_iptv/core/providers/theme_providers.dart';
import 'package:open_iptv/core/services/epg_service.dart';
import 'package:open_iptv/core/services/native_video_player.dart';
import 'package:open_iptv/core/services/parental_service.dart';
import 'package:open_iptv/core/services/playback_service.dart';
import 'package:open_iptv/core/services/profile_service.dart';
import 'package:open_iptv/core/storage/preferences.dart';
import 'package:open_iptv/features/live_tv/catchup_launcher.dart';
import 'package:open_iptv/features/live_tv/channel_list_screen.dart';
import 'package:open_iptv/features/live_tv/live_categories.dart';
import 'package:open_iptv/features/player/stream_watchdog.dart';
import 'package:open_iptv/shared/utils/display_name.dart';
import 'package:open_iptv/shared/utils/genre_icons.dart';
import 'package:open_iptv/shared/widgets/error_state_view.dart';
import 'package:open_iptv/shared/widgets/marquee_text.dart';
import 'package:open_iptv/shared/widgets/parental_pin_dialog.dart';
import 'package:open_iptv/shared/widgets/skeleton.dart';
import 'package:open_iptv/shared/widgets/tv_focusable.dart';
import 'package:open_iptv/shared/widgets/tv_nav_rail_focus.dart';
import 'package:open_iptv/shared/widgets/video_surface.dart';

// ---------------------------------------------------------------------------
// Layout
// ---------------------------------------------------------------------------

const _pxPerMinute = 4.0;
// Loaded once per visit: half an hour back, five and a half ahead.
const _windowBefore = Duration(minutes: 30);
const _windowAfter = Duration(hours: 5, minutes: 30);
const _categoryWidth = 200.0;
const _channelWidth = 210.0;
const _paneHeight = 164.0;
const _headerHeight = 30.0;
const _rowHeight = 48.0;

// The column's fixed entries, ahead of the playlist's own categories.
const _favorites = '\u0001favorites';
const _recent = '\u0001recent';
const _all = '\u0001all';

typedef _RowKey = ({String channelId, DateTime start, DateTime end});

// One row's programmes, loaded as the row comes into view.
final _rowProgrammesProvider =
    FutureProvider.autoDispose.family<List<Programme>, _RowKey>((ref, k) async =>
        guideRow(await ref
            .read(epgServiceProvider)
            .getProgrammesForChannelInRange(k.channelId, k.start, k.end)));

/// A row's programmes as the guide shows them: in order, one at a time.
/// Some providers' guides mix two schedules for a channel (e.g. a show
/// listed 12:00–12:30 *and* 12:12–12:48); drawn as they are, the later
/// cells covered the earlier ones and the row looked chopped up. A
/// programme that starts before the one already kept has ended is left
/// out — except for a couple of minutes' overlap, which only trims it.
@visibleForTesting
List<Programme> guideRow(List<Programme> programmes) {
  const slack = Duration(minutes: 2);
  final sorted = [...programmes]..sort((a, b) => a.start.compareTo(b.start));
  final kept = <Programme>[];
  for (final p in sorted) {
    if (kept.isNotEmpty && p.start.isBefore(kept.last.end.subtract(slack))) {
      continue;
    }
    kept.add(p);
  }
  return kept;
}

Programme? _airing(List<Programme> programmes) =>
    programmes.where((p) => p.isLive).firstOrNull;

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Live TV on a TV: categories on the left, the focused programme and a
/// preview of the channel you picked at the top, and a channel × time guide
/// below. Phones keep the Live TV lists.
class TvGuideScreen extends ConsumerStatefulWidget {
  const TvGuideScreen({super.key, this.sportsOnly = false});

  final bool sportsOnly;

  @override
  ConsumerState<TvGuideScreen> createState() => _TvGuideScreenState();
}

class _TvGuideScreenState extends ConsumerState<TvGuideScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // The category you were in, for the next visit (this run of the app).
  static String? _rememberedCategory;

  late final DateTime _rangeStart;
  late final DateTime _rangeEnd;
  // How far the timeline is scrolled, in pixels; every row follows it.
  late final AnimationController _time;
  double _timelineWidth = 0;
  Timer? _nowTicker;

  String? _focusedCategory;
  String? _shownCategory;
  Timer? _categoryDebounce;
  final Map<String, FocusNode> _categoryNodes = {};
  final _columnNode = FocusNode(
      debugLabel: 'GuideCategories', canRequestFocus: false, skipTraversal: true);
  final _gridNode = FocusNode(
      debugLabel: 'GuideGrid', canRequestFocus: false, skipTraversal: true);
  // The first row's way in: what's on now (or its "No guide" cell).
  final _firstRowNode = FocusNode(debugLabel: 'GuideFirstRow');
  FocusNode? _lastGridFocus;
  // On a cell with nothing to its left in the row ("No guide"): Left goes
  // straight to the categories.
  bool _exitsLeft = false;

  late final _pane = _PaneModel(ref.read(playbackServiceProvider));

  _RowKey _rowKey(Channel c) =>
      (channelId: c.id, start: _rangeStart, end: _rangeEnd);

  @override
  void initState() {
    super.initState();
    ref.listenManual<int>(homeLeaveProvider, (_, __) => _pane.stopPreview());
    final now = DateTime.now();
    // Snapped to the half hour, so the times read 2:30 / 3:00, and opened
    // with that half hour at the left edge.
    final slot = DateTime(
        now.year, now.month, now.day, now.hour, now.minute < 30 ? 0 : 30);
    _rangeStart = slot.subtract(_windowBefore);
    _rangeEnd = slot.add(_windowAfter);
    _time = AnimationController.unbounded(
        vsync: this, value: _windowBefore.inMinutes * _pxPerMinute);
    _nowTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nowTicker?.cancel();
    _categoryDebounce?.cancel();
    _time.dispose();
    _pane.dispose();
    for (final n in _categoryNodes.values) {
      n.dispose();
    }
    _columnNode.dispose();
    _gridNode.dispose();
    _firstRowNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The preview's stream is let go while the app is out of sight.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pane.stopPreview();
    }
  }

  // ---- Timeline ----------------------------------------------------------

  double get _maxOffset => math.max(
      0,
      _rangeEnd.difference(_rangeStart).inMinutes * _pxPerMinute -
          _timelineWidth);

  void _scrollTimeTo(double x) => _time.animateTo(x.clamp(0.0, _maxOffset),
      duration: const Duration(milliseconds: 200), curve: Curves.easeOut);

  // A programme cell came into focus: bring its start into view if it isn't.
  void _revealTime(double x) {
    final offset = _time.value;
    if (x >= offset && x <= offset + _timelineWidth - 120) return;
    _scrollTimeTo(x);
  }

  // ---- Categories --------------------------------------------------------

  FocusNode _categoryNode(String key) => _categoryNodes.putIfAbsent(
      key, () => FocusNode(debugLabel: 'GuideCategory'));

  void _onCategoryFocused(String key) {
    _focusedCategory = key;
    // Scrolling through the list doesn't reload the guide on every step.
    _categoryDebounce?.cancel();
    if (key == _shownCategory) return;
    _categoryDebounce =
        Timer(const Duration(milliseconds: 300), () => _showCategory(key));
  }

  void _showCategory(String key) {
    _categoryDebounce?.cancel();
    if (!mounted || key == _shownCategory) return;
    setState(() {
      _shownCategory = key;
      _rememberedCategory = key;
      _lastGridFocus = null;
    });
  }

  Future<void> _openCategory(String key) async {
    if (_isRealCategory(key) &&
        !await ensureCategoryUnlocked(context, ref, key)) {
      return;
    }
    if (!mounted) return;
    _showCategory(key);
    _enterGrid();
  }

  // Right from the column (or OK on a category): into the guide, back to
  // the channel you left there.
  void _enterGrid() {
    void focusGrid() {
      if (!mounted) return;
      final last = _lastGridFocus;
      if (last != null && last.context != null && last.canRequestFocus) {
        last.requestFocus();
      } else if (_firstRowNode.context != null) {
        _firstRowNode.requestFocus();
      }
    }

    final key = _focusedCategory;
    if (key == null || key == _shownCategory) return focusGrid();
    // The guide changes first; its rows exist after the next frame.
    _showCategory(key);
    WidgetsBinding.instance.addPostFrameCallback((_) => focusGrid());
  }

  // Left out of the guide: to the category it's showing.
  void _exitToCategories() {
    // The guide's own moves keep the column out of the search for a moment.
    _columnNode.descendantsAreFocusable = true;
    final key = _shownCategory;
    if (key != null) _categoryNode(key).requestFocus();
  }

  static bool _isRealCategory(String key) =>
      key != _favorites && key != _recent && key != _all;

  // ---- Grid --------------------------------------------------------------

  void _onCellFocused(Channel channel, Programme? programme,
      {required bool exitsLeft}) {
    _exitsLeft = exitsLeft;
    // In the guide: no category switch still to come (entering the guide
    // shows the focused category straight away).
    _categoryDebounce?.cancel();
    _lastGridFocus = FocusManager.instance.primaryFocus;
    _pane.show(channel, programme);
  }

  Future<void> _activate(Channel channel, Programme? programme) async {
    // An earlier programme plays from catch-up where the channel has it;
    // anything else (on now, later, no catch-up) plays the channel live.
    final now = DateTime.now();
    if (programme != null &&
        !programme.end.isAfter(now) &&
        channel.hasCatchup) {
      await _playCatchup(channel, programme);
      return;
    }
    if (_pane.playingId == channel.id) {
      // Already playing in the pane: full screen carries on with the same
      // stream, and Back hands it back here.
      unawaited(context.push('/player', extra: {
        'streamUrl': channel.streamUrl,
        'title': channel.name,
        'contentType': 'live',
        'contentId': channel.id,
        'continuePlaying': true,
        'handBackTo': _pane,
      }));
    } else {
      _pane.startPreview(channel);
    }
  }

  Future<void> _playCatchup(Channel channel, Programme programme) async {
    final source =
        await ref.read(appDatabaseProvider).getSourceById(channel.sourceId);
    if (source == null || !mounted) return;
    _pane.stopPreview();
    await launchCatchup(
      context: context,
      ref: ref,
      channel: channel,
      source: source,
      programme: programme,
      replace: false,
    );
  }

  // ---- Build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(allChannelsProvider);
    return Scaffold(
      body: channelsAsync.when(
        loading: () => const SkeletonList(leadingSize: 28),
        error: (e, _) => ErrorStateView(
          message: "Couldn't load channels. Check your internet connection.",
          onRetry: () => ref.invalidate(allChannelsProvider),
        ),
        data: (channels) => _buildGuide(widget.sportsOnly
            ? channels.where(isSportsChannel).toList() : channels),
      ),
    );
  }

  Widget _buildGuide(List<Channel> all) {
    _pane.channels = all;
    final profile = ref.watch(activeProfileProvider).valueOrNull;
    final prefs = ref.watch(appPreferencesProvider).valueOrNull;
    final unlocked = ref.watch(parentalSessionUnlockedProvider);
    final az = ref.watch(contentSortProvider) == 'az';
    final isKid = profile?.isKidsProfile ?? false;
    final favIds = (profile?.favoriteChannelIds ?? const <String>[]).toSet();
    bool allowed(Channel c) => !isKid || !c.categories.any(isAdultCategory);

    final favorites = [
      for (final c in all)
        if (favIds.contains(c.id) && allowed(c)) c
    ];
    final recent = [
      for (final c in ref.watch(recentChannelsProvider).valueOrNull ??
          const <Channel>[])
        if (allowed(c) && (!widget.sportsOnly || isSportsChannel(c))) c
    ];
    final categories = [
      if (favorites.isNotEmpty) _favorites,
      if (recent.isNotEmpty) _recent,
      _all,
      ...liveCategories(all,
          hidden: (profile?.hiddenCategories ?? const []).toSet(),
          isKid: isKid,
          az: az),
    ];
    if (_shownCategory == null || !categories.contains(_shownCategory)) {
      _shownCategory = categories.contains(_rememberedCategory)
          ? _rememberedCategory
          : categories.first;
      _focusedCategory = _shownCategory;
    }
    final shown = _shownCategory!;
    bool locked(String key) =>
        _isRealCategory(key) &&
        prefs != null &&
        isCategoryLocked(key, prefs, unlocked);

    List<Channel> sorted(Iterable<Channel> list) {
      final out = list.toList();
      if (az) out.sort((a, b) => a.name.compareTo(b.name));
      return out;
    }

    final channels = switch (shown) {
      _favorites => sorted(favorites),
      _recent => recent,
      _all => sorted(all.where(allowed)),
      _ => sorted(all.where((c) => c.categories.contains(shown))),
    };

    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ---- Category column ----
        Container(
          width: _categoryWidth,
          color: theme.colorScheme.surfaceContainerLow,
          child: Focus(
            focusNode: _columnNode,
            canRequestFocus: false,
            skipTraversal: true,
            child: Actions(
              actions: {
                DirectionalFocusIntent: _ColumnDirectionalAction(
                  columnNode: _columnNode,
                  onRight: _enterGrid,
                  onLeft: () =>
                      TvNavRailFocus.maybeOf(context)?.requestFocus(),
                ),
              },
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 12),
                itemCount: categories.length,
                itemBuilder: (context, i) {
                  final key = categories[i];
                  return _CategoryItem(
                    focusNode: _categoryNode(key),
                    icon: switch (key) {
                      _favorites => Icons.star_rounded,
                      _recent => Icons.history_rounded,
                      _all => Icons.live_tv_outlined,
                      _ => genreIcon(key, fallback: Icons.folder_outlined),
                    },
                    label: switch (key) {
                      _favorites => 'Favorites',
                      _recent => 'Recently Watched',
                      _all => widget.sportsOnly ? 'All Sports' : 'All Channels',
                      _ => context.displayName(key),
                    },
                    selected: key == shown,
                    locked: locked(key),
                    onFocus: () => _onCategoryFocused(key),
                    onTap: () => _openCategory(key),
                    onLongPress: _isRealCategory(key) && profile != null
                        ? () => showCategoryOptions(
                            context, ref, profile.id, key)
                        : null,
                  );
                },
              ),
            ),
          ),
        ),
        // ---- Programme pane + guide ----
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _paneHeight,
                child: _TopPane(
                  model: _pane,
                  rowKey: _rowKey,
                ),
              ),
              _TimeHeader(
                rangeStart: _rangeStart,
                rangeEnd: _rangeEnd,
                time: _time,
              ),
              Expanded(
                child: locked(shown)
                    ? const _GuideMessage(
                        icon: Icons.lock_outline_rounded,
                        text: 'This category is locked. Press OK on it to '
                            'unlock it.',
                      )
                    : channels.isEmpty
                        ? const _GuideMessage(
                            icon: Icons.live_tv_outlined,
                            text: 'No channels here yet.',
                          )
                        : _buildGrid(channels, favIds, profile?.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(
      List<Channel> channels, Set<String> favIds, String? profileId) {
    return LayoutBuilder(builder: (context, box) {
      _timelineWidth = math.max(0, box.maxWidth - _channelWidth);
      return Focus(
        focusNode: _gridNode,
        canRequestFocus: false,
        skipTraversal: true,
        child: Actions(
          actions: {
            DirectionalFocusIntent: _GridDirectionalAction(
              gridNode: _gridNode,
              columnNode: _columnNode,
              exitsLeft: () => _exitsLeft,
              scrollTimeBy: (dx) => _scrollTimeTo(_time.value + dx),
              canScrollBack: () => _time.value > 0.5,
              onExitLeft: _exitToCategories,
              nowX: () =>
                  DateTime.now().difference(_rangeStart).inSeconds /
                      60 *
                      _pxPerMinute -
                  _time.value,
            ),
          },
          child: Stack(
            children: [
              ListView.builder(
                key: ValueKey(_shownCategory),
                itemCount: channels.length,
                itemExtent: _rowHeight,
                itemBuilder: (context, i) {
                  final channel = channels[i];
                  return _GuideRow(
                    channel: channel,
                    rowKey: _rowKey(channel),
                    time: _time,
                    entryNode: i == 0 ? _firstRowNode : null,
                    autofocus: i == 0,
                    onCellFocused: _onCellFocused,
                    onRevealTime: _revealTime,
                    onActivate: _activate,
                    onLongPress: profileId == null
                        ? null
                        : () => showChannelOptions(context, ref, channel,
                            profileId, favIds.contains(channel.id),
                            recent: _shownCategory == _recent),
                  );
                },
              ),
              _NowLine(rangeStart: _rangeStart, time: _time),
            ],
          ),
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// What the top pane shows: the focused channel and programme, and the
// preview of the channel you picked.
// ---------------------------------------------------------------------------

/// The preview is the app's main player: going full screen carries on with
/// the same stream (no restart), and the player hands it back here on Back
/// (it owns the stream meanwhile). This model is the owner while the pane
/// plays.
class _PaneModel extends ChangeNotifier {
  _PaneModel(this.service) {
    service.nowPlaying.addListener(_onNowPlaying);
    _stateSub = service.stateStream.listen((st) {
      if (st.hasVideo != _hasVideo) {
        _hasVideo = st.hasVideo;
        if (!_disposed) notifyListeners();
      }
      _check();
    });
    _errorSub = service.errorStream.listen(_onError);
  }

  final PlaybackService service;
  Channel? channel;
  Programme? programme;
  bool _disposed = false;

  // The preview's own freeze check, like the full-screen player's: a stuck
  // or refused stream reconnects, and a dead one says so instead of
  // staying black.
  StreamWatchdog? _dog;
  Timer? _timer;
  late final StreamSubscription<NativeVideoPlayerState> _stateSub;
  late final StreamSubscription<NativePlaybackError> _errorSub;
  bool _wasPreviewing = false;
  bool _hasVideo = false;

  /// The new stream's first frame is in: until then the texture still holds
  /// the last frame of whatever played before.
  bool get showPicture => previewing && _hasVideo;

  /// The preview that couldn't play, and why.
  ({String channelId, String text})? failed;

  /// The preview is (re)connecting.
  bool get loading => previewing && (_dog?.loading ?? true);

  void _onNowPlaying() {
    final now = previewing;
    // Started here, or handed back by the full-screen player: watch it
    // afresh.
    if (now && !_wasPreviewing) _watch();
    if (!now) {
      _timer?.cancel();
      _timer = null;
    }
    _wasPreviewing = now;
    notifyListeners();
  }

  void _watch() {
    final preset = service.bufferPreset;
    _dog = StreamWatchdog(
        freezeLimit: preset.freezeLimit, connectLimit: preset.connectLimit);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _check());
  }

  void _check() {
    final dog = _dog;
    if (!previewing || dog == null) return;
    final wasLoading = dog.loading;
    _act(dog.check(service.lastState,
        now: DateTime.now(), openCount: service.openCount, live: true));
    if (wasLoading != dog.loading && !_disposed) notifyListeners();
  }

  void _onError(NativePlaybackError e) {
    final dog = _dog;
    if (!previewing || dog == null) return;
    if (e.isPermanent) {
      _fail(e.httpStatus == 401 || e.httpStatus == 403
          ? "Your provider didn't allow this stream."
          : "This channel isn't available right now.");
    } else {
      _act(dog.onError(DateTime.now()));
    }
  }

  void _act(WatchdogAction action) {
    final url = service.nowPlaying.value?.url;
    switch (action) {
      case WatchdogAction.reconnect:
        if (url != null) unawaited(service.play(url, owner: this));
      case WatchdogAction.giveUp:
        _fail("This channel isn't available right now.");
      case WatchdogAction.none:
        break;
    }
  }

  void _fail(String text) {
    final id = playingId;
    if (id != null) failed = (channelId: id, text: text);
    stopPreview();
  }

  Map<String, Channel> _byUrl = const {};
  List<Channel>? _channels;

  /// The channels the playing stream is looked up in.
  set channels(List<Channel> all) {
    if (identical(all, _channels)) return;
    _channels = all;
    _byUrl = {for (final c in all) c.streamUrl: c};
  }

  bool get previewing => service.nowPlaying.value?.owner == this;

  /// The channel playing in the pane (full screen may have switched it).
  Channel? get playing =>
      previewing ? _byUrl[service.nowPlaying.value!.url] : null;
  String? get playingId => playing?.id;

  void show(Channel c, Programme? p) {
    if (c.id == channel?.id && p == programme) return;
    channel = c;
    programme = p;
    notifyListeners();
  }

  void startPreview(Channel c) {
    failed = null;
    // The texture exists once the player has opened.
    service.play(c.streamUrl, owner: this).then((_) {
      if (!_disposed) notifyListeners();
    });
  }

  void stopPreview() {
    if (previewing) unawaited(service.stop());
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_stateSub.cancel());
    unawaited(_errorSub.cancel());
    service.nowPlaying.removeListener(_onNowPlaying);
    stopPreview();
    super.dispose();
  }
}

class _TopPane extends ConsumerWidget {
  const _TopPane({
    required this.model,
    required this.rowKey,
  });

  final _PaneModel model;
  final _RowKey Function(Channel) rowKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final channel = model.channel;
        // The channel itself is focused: what's on it now.
        final programme = model.programme ??
            (channel == null
                ? null
                : _airing(ref.watch(_rowProgrammesProvider(rowKey(channel)))
                        .valueOrNull ??
                    const []));
        final service = model.service;
        final previewing = model.previewing && service.hasTexture;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ColoredBox(
                    color: Colors.black,
                    child: previewing
                        ? Stack(fit: StackFit.expand, children: [
                            if (model.showPicture)
                              VideoSurface(
                                textureId: service.textureId,
                                stateStream: service.stateStream,
                                initialAspectRatio:
                                    service.lastState.aspectRatio,
                              )
                            else
                              _PreviewPlaceholder(channel: model.playing),
                            if (model.loading || !model.showPicture)
                              const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white70),
                                ),
                              ),
                          ])
                        : _PreviewPlaceholder(
                            channel: channel,
                            hint: channel == null
                                ? null
                                : model.failed?.channelId == channel.id
                                    ? model.failed!.text
                                    : 'Press OK to preview',
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: channel == null
                    ? const SizedBox.shrink()
                    : _ProgrammeInfo(channel: channel, programme: programme),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PreviewPlaceholder extends StatelessWidget {
  const _PreviewPlaceholder({required this.channel, this.hint});

  final Channel? channel;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: channel == null
              ? const Icon(Icons.live_tv_rounded,
                  color: Colors.white38, size: 40)
              : LogoTile(url: channel!.logoUrl, width: 120),
        ),
        if (hint != null) _PreviewLabel(text: hint!),
      ],
    );
  }
}

class _PreviewLabel extends StatelessWidget {
  const _PreviewLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 6),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC000000), Color(0x00000000)],
          ),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .labelMedium!
              .copyWith(color: Colors.white),
        ),
      ),
    );
  }
}

class _ProgrammeInfo extends StatelessWidget {
  const _ProgrammeInfo({required this.channel, required this.programme});

  final Channel channel;
  final Programme? programme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = programme;
    final name = context.displayName(channel.name);
    final description = p?.description?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MarqueeText(
          p?.title ?? name,
          style: theme.textTheme.titleLarge!
              .copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        MarqueeText(
          p == null
              ? 'No guide information'
              : '${_hm(context, p.start)} – ${_hm(context, p.end)}  ·  $name',
          style: theme.textTheme.bodyMedium!
              .copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (p != null && p.isLive) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: p.progressAt(DateTime.now()).clamp(0.0, 1.0),
                minHeight: 3,
              ),
            ),
          ),
        ],
        if (description != null && description.isNotEmpty) ...[
          const SizedBox(height: 8),
          Expanded(
            child: Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ],
    );
  }
}

String _hm(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

class _GuideMessage extends StatelessWidget {
  const _GuideMessage({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center, style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category column
// ---------------------------------------------------------------------------

class _CategoryItem extends StatelessWidget {
  const _CategoryItem({
    required this.focusNode,
    required this.icon,
    required this.label,
    required this.selected,
    required this.locked,
    required this.onFocus,
    required this.onTap,
    this.onLongPress,
  });

  final FocusNode focusNode;
  final IconData icon;
  final String label;
  final bool selected;
  final bool locked;
  final VoidCallback onFocus;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color =
        selected ? theme.colorScheme.primary : theme.colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: TvFocusable(
        focusNode: focusNode,
        ensureVisibleOnFocus: true,
        borderRadius: BorderRadius.circular(10),
        onFocusChange: (f) {
          if (f) onFocus();
        },
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.primary.withValues(alpha: 0.14)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: color,
                    fontWeight: selected ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (locked)
                Icon(Icons.lock_outline_rounded,
                    size: 16, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// D-pad in the category column: Up/Down stay in the column, Right goes
/// into the guide, Left to the side menu.
class _ColumnDirectionalAction extends Action<DirectionalFocusIntent> {
  _ColumnDirectionalAction({
    required this.columnNode,
    required this.onRight,
    required this.onLeft,
  });

  final FocusNode columnNode;
  final VoidCallback onRight;
  final VoidCallback onLeft;

  @override
  Object? invoke(DirectionalFocusIntent intent) {
    switch (intent.direction) {
      case TraversalDirection.right:
        onRight();
      case TraversalDirection.left:
        onLeft();
      case TraversalDirection.up:
      case TraversalDirection.down:
        final before = primaryFocus;
        if (before == null || !before.focusInDirection(intent.direction)) {
          break;
        }
        scheduleMicrotask(() {
          if (!columnNode.hasFocus) before.requestFocus();
        });
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Time header and "now" line
// ---------------------------------------------------------------------------

class _TimeHeader extends StatelessWidget {
  const _TimeHeader({
    required this.rangeStart,
    required this.rangeEnd,
    required this.time,
  });

  final DateTime rangeStart;
  final DateTime rangeEnd;
  final Animation<double> time;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium!
        .copyWith(color: theme.colorScheme.onSurfaceVariant);
    final minutes = rangeEnd.difference(rangeStart).inMinutes;
    final now = DateTime.now();
    final loc = MaterialLocalizations.of(context);
    return SizedBox(
      height: _headerHeight,
      child: Row(
        children: [
          SizedBox(
            width: _channelWidth,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${loc.formatMediumDate(now)}, ${_hm(context, now)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style,
                ),
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: AnimatedBuilder(
                animation: time,
                builder: (context, _) => Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var m = 0; m <= minutes; m += 30)
                      Positioned(
                        left: m * _pxPerMinute - time.value,
                        top: 0,
                        bottom: 0,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _hm(context, rangeStart.add(Duration(minutes: m))),
                            style: style,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The current time across the guide. A direct Stack child (it's a
/// Positioned — wrapping it throws in release).
class _NowLine extends StatelessWidget {
  const _NowLine({required this.rangeStart, required this.time});

  final DateTime rangeStart;
  final Animation<double> time;

  @override
  Widget build(BuildContext context) {
    final x = DateTime.now().difference(rangeStart).inSeconds /
        60 *
        _pxPerMinute;
    final color = Theme.of(context).colorScheme.primary;
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: time,
          builder: (context, _) {
            final left = _channelWidth + x - time.value;
            if (left < _channelWidth) return const SizedBox.shrink();
            return Stack(children: [
              Positioned(
                left: left,
                top: 0,
                bottom: 0,
                width: 2,
                child: ColoredBox(color: color),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// One channel's row: logo and name, then its programmes
// ---------------------------------------------------------------------------

class _GuideRow extends ConsumerWidget {
  const _GuideRow({
    required this.channel,
    required this.rowKey,
    required this.time,
    required this.onCellFocused,
    required this.onRevealTime,
    required this.onActivate,
    this.onLongPress,
    this.entryNode,
    this.autofocus = false,
  });

  final Channel channel;
  final _RowKey rowKey;
  final Animation<double> time;
  final void Function(Channel, Programme?, {required bool exitsLeft})
      onCellFocused;
  final void Function(double x) onRevealTime;
  final void Function(Channel, Programme?) onActivate;
  final VoidCallback? onLongPress;
  // The cell Right from the categories lands on in this row.
  final FocusNode? entryNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final loaded = ref.watch(_rowProgrammesProvider(rowKey));
    final programmes = loaded.valueOrNull ?? const <Programme>[];
    final totalMinutes = rowKey.end.difference(rowKey.start).inMinutes;
    double xOf(DateTime t) => (t.difference(rowKey.start).inSeconds / 60 *
            _pxPerMinute)
        .clamp(0.0, totalMinutes * _pxPerMinute);

    return _RowFocus(
      builder: (context, rowFocused) => Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- The channel ----
          SizedBox(
            width: _channelWidth,
            // A label, not a stop for the remote: the programmes are.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 3, 8, 3),
              child: Row(
                children: [
                  LogoTile(url: channel.logoUrl, width: 48),
                  const SizedBox(width: 8),
                  // Long names get a second line rather than being cut.
                  Expanded(
                    child: MarqueeText(
                      context.displayName(channel.name),
                      maxLines: 2,
                      active: rowFocused,
                      style: theme.textTheme.bodyMedium!
                          .copyWith(fontSize: 13, height: 1.15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ---- Its programmes ----
          Expanded(
            child: loaded.hasValue && programmes.isEmpty
                // No guide data: one cell, so the channel can still be
                // reached and played from here.
                ? _ProgrammeCell(
                    title: 'No guide information',
                    muted: true,
                    focusNode: entryNode,
                    autofocus: autofocus,
                    onFocus: () =>
                        onCellFocused(channel, null, exitsLeft: true),
                    onTap: () => onActivate(channel, null),
                    onLongPress: onLongPress,
                  )
                : ClipRect(
                    child: AnimatedBuilder(
                      animation: time,
                      builder: (context, _) {
                        final offset = time.value;
                        final entry = _entry(programmes);
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final p in programmes)
                              _positioned(context, p, xOf(p.start),
                                  xOf(p.end), offset,
                                  entry: identical(p, entry)),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    ));
  }

  // Where the remote enters the row: what's on now, else what's next.
  static Programme? _entry(List<Programme> programmes) {
    final now = DateTime.now();
    return _airing(programmes) ??
        programmes.where((p) => p.end.isAfter(now)).firstOrNull ??
        programmes.lastOrNull;
  }

  Widget _positioned(BuildContext context, Programme p, double start,
      double end, double offset, {required bool entry}) {
    final now = DateTime.now();
    return Positioned(
      key: ValueKey(p.start),
      left: start - offset,
      width: math.max(end - start, 6),
      top: 0,
      bottom: 0,
      child: _ProgrammeCell(
        title: p.title,
        live: p.isLive,
        muted: !p.end.isAfter(now),
        catchup: channel.hasCatchup && !p.end.isAfter(now),
        // Keeps the title in view while the programme's start is scrolled
        // past the left edge.
        textInset: math.max(0, offset - start),
        focusNode: entry ? entryNode : null,
        autofocus: entry && autofocus,
        onFocus: () {
          onCellFocused(channel, p, exitsLeft: false);
          onRevealTime(start);
        },
        onTap: () => onActivate(channel, p),
        onLongPress: onLongPress,
      ),
    );
  }
}

/// Tells its builder whether anything inside it has focus.
class _RowFocus extends StatefulWidget {
  const _RowFocus({required this.builder});

  final Widget Function(BuildContext context, bool focused) builder;

  @override
  State<_RowFocus> createState() => _RowFocusState();
}

class _RowFocusState extends State<_RowFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: widget.builder(context, _focused),
    );
  }
}

class _ProgrammeCell extends StatefulWidget {
  const _ProgrammeCell({
    required this.title,
    required this.onFocus,
    required this.onTap,
    this.live = false,
    this.muted = false,
    this.catchup = false,
    this.textInset = 0,
    this.focusNode,
    this.autofocus = false,
    this.onLongPress,
  });

  final String title;
  final bool live;
  final bool muted;
  final bool catchup;
  final double textInset;
  final VoidCallback onFocus;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final bool autofocus;
  // Hold OK: the channel's options.
  final VoidCallback? onLongPress;

  @override
  State<_ProgrammeCell> createState() => _ProgrammeCellState();
}

class _ProgrammeCellState extends State<_ProgrammeCell> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.title;
    final live = widget.live;
    final muted = widget.muted;
    final catchup = widget.catchup;
    final textInset = widget.textInset;
    return Padding(
      padding: const EdgeInsets.fromLTRB(1, 3, 1, 3),
      child: TvFocusable(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(6),
        onFocusChange: (f) {
          setState(() => _focused = f);
          if (f) widget.onFocus();
        },
        onTap: widget.onTap,
        child: Container(
          decoration: BoxDecoration(
            color: live
                ? theme.colorScheme.primary.withValues(alpha: 0.20)
                : theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: EdgeInsets.only(left: 10 + textInset, right: 8),
          alignment: Alignment.centerLeft,
          child: Row(
            children: [
              Expanded(
                child: MarqueeText(
                  title,
                  active: _focused,
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: muted
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.onSurface,
                    fontWeight: live ? FontWeight.w600 : null,
                  ),
                ),
              ),
              if (catchup)
                Icon(Icons.replay_rounded,
                    size: 14, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// D-pad in the guide
// ---------------------------------------------------------------------------

/// Left/Right move along the row; with nothing further that way the
/// timeline moves by half an hour instead (Flutter's own search would jump
/// diagonally into another row). Left from a "No guide" cell, or at the
/// start of the timeline, goes to the categories. Up/Down move between rows and
/// never leave the guide.
class _GridDirectionalAction extends Action<DirectionalFocusIntent> {
  _GridDirectionalAction({
    required this.gridNode,
    required this.columnNode,
    required this.exitsLeft,
    required this.scrollTimeBy,
    required this.canScrollBack,
    required this.onExitLeft,
    required this.nowX,
  });

  /// Where now is, from the timeline's left edge (as scrolled).
  final double Function() nowX;
  final FocusNode gridNode;
  final FocusNode columnNode;
  final bool Function() exitsLeft;
  final void Function(double dx) scrollTimeBy;
  final bool Function() canScrollBack;
  final VoidCallback onExitLeft;

  static const _step = 30 * _pxPerMinute;

  // Up/Down: the cell in the next row at the same time — now, if the cell
  // you're on is airing, else the start of its visible part. Flutter's own
  // search went by the middle of the cell, so from a wide "No guide" cell
  // it landed on a programme hours ahead.
  FocusNode? _rowNeighbour(FocusNode from, {required bool down}) {
    final timelineLeft = gridNode.rect.left + _channelWidth;
    final now = timelineLeft + nowX();
    final x = from.rect.left <= now && now < from.rect.right
        ? now
        : math.max(from.rect.left, timelineLeft) + 1;
    final y = from.rect.center.dy + (down ? _rowHeight : -_rowHeight);
    FocusNode? best;
    var bestGap = double.infinity;
    for (final n in gridNode.traversalDescendants) {
      if (identical(n, from) || !n.canRequestFocus) continue;
      final r = n.rect;
      if ((r.center.dy - y).abs() > _rowHeight / 2) continue;
      final gap = x < r.left
          ? r.left - x
          : x >= r.right
              ? x - r.right
              : 0.0;
      if (gap < bestGap) {
        best = n;
        bestGap = gap;
      }
    }
    return best;
  }

  // Flutter's search for the next stop, with the categories left out: it
  // used to land on whichever category sat nearest — only for a moment,
  // but enough to switch the guide to it.
  bool _search(FocusNode from, TraversalDirection dir) {
    columnNode.descendantsAreFocusable = false;
    try {
      return from.focusInDirection(dir);
    } finally {
      // After the focus change has been applied.
      scheduleMicrotask(() => columnNode.descendantsAreFocusable = true);
    }
  }

  @override
  Object? invoke(DirectionalFocusIntent intent) {
    final dir = intent.direction;
    final before = primaryFocus;
    if (before == null) return true;

    if (dir == TraversalDirection.up || dir == TraversalDirection.down) {
      final next = _rowNeighbour(before, down: dir == TraversalDirection.down);
      if (next != null) {
        next.requestFocus();
        final c = next.context;
        if (c != null) {
          Scrollable.ensureVisible(c,
              duration: const Duration(milliseconds: 120),
              alignmentPolicy: dir == TraversalDirection.down
                  ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
                  : ScrollPositionAlignmentPolicy.keepVisibleAtStart);
        }
      }
      return true;
    }

    final left = dir == TraversalDirection.left;
    if (left && exitsLeft()) {
      onExitLeft();
      return true;
    }
    final from = before.rect;
    void cannotMove() {
      if (left && !canScrollBack()) {
        onExitLeft();
      } else {
        scrollTimeBy(left ? -_step : _step);
      }
    }

    if (!_search(before, dir)) {
      cannotMove();
      return true;
    }
    // Focus changes apply a moment later — judge where it actually landed.
    scheduleMicrotask(() {
      final after = primaryFocus;
      if (after == null) return;
      if (identical(after, before)) {
        cannotMove();
        return;
      }
      final sameRow =
          (after.rect.center.dy - from.center.dy).abs() < from.height / 2;
      if (sameRow && gridNode.hasFocus) return;
      // Out of the guide or into another row: stay, move through time.
      before.requestFocus();
      cannotMove();
    });
    return true;
  }
}
