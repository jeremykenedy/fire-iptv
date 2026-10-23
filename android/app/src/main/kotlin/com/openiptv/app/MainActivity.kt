package com.openiptv.app

import android.app.PictureInPictureParams
import android.os.Handler
import android.os.Looper
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Log
import android.util.Rational
import android.view.WindowManager
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

// Extends AudioServiceActivity (not FlutterActivity) so the Flutter engine is
// shared with the background audio_service, keeping the Now Playing
// notification in sync with the same media_kit Player instance.
class MainActivity : AudioServiceActivity() {
    private var pipChannel: MethodChannel? = null
    private var backChannel: MethodChannel? = null
    private var updatesChannel: MethodChannel? = null
    private var castController: CastController? = null
    private var vpnController: VpnController? = null
    private var homeCardsChannel: MethodChannel? = null
    private var pendingHomeChannelLink: String? = null
    private val homeCardWorker = Executors.newSingleThreadExecutor()

    // Updated proactively by Dart via pip_service.dart's updatePipAvailability()
    // whenever "PiP enabled AND actively playing" changes. Read synchronously
    // in onUserLeaveHint() — there's no time for a Dart round-trip at that
    // point, since the activity is paused immediately afterward.
    @Volatile
    private var pipAvailable = false

    // Updated proactively by Dart (app.dart's _ShellState) whenever it's
    // sitting on a root tab with nothing of its own left to pop — Flutter's
    // PopScope/OnBackInvokedCallback plumbing was empirically unreliable
    // here (a PopScope with canPop:false, wrapping the ShellRoute's content,
    // never actually stopped the system from closing the Activity — verified
    // by hard-coding canPop:false and watching the app still exit). Handling
    // Back directly at the Activity level sidesteps that entirely: read
    // synchronously here, so there's no round-trip race with the physical
    // key press.
    @Volatile
    private var backBlocked = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val publisher = HomeChannelPublisher(applicationContext)
        homeCardsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fireiptv/home-cards")
        homeCardsChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "sync" -> {
                    val entries = call.arguments as? List<*>
                    if (entries == null || entries.size > 12 || homeCardWorker.isShutdown) {
                        result.error("invalid_cards", "Could not refresh home cards", null)
                    } else {
                        val cards = entries.mapNotNull { item ->
                            val fields = item as? Map<*, *> ?: return@mapNotNull null
                            val values = listOf("id", "title", "artUri", "intentUri")
                            if (values.any { fields[it] !is String }) null
                            else values.associateWith { fields[it] as String }
                        }
                        if (cards.size != entries.size) {
                            result.error("invalid_cards", "Could not refresh home cards", null)
                        } else homeCardWorker.execute {
                            val state = publisher.sync(cards)
                            runOnUiThread { result.success(state) }
                        }
                    }
                }
                "takePendingLink" -> {
                    val link = pendingHomeChannelLink ?: intent?.dataString
                    pendingHomeChannelLink = null
                    intent?.data = null
                    result.success(link)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "fireiptv/streaming-apps")
            .setMethodCallHandler { call, result ->
                if (call.method != "open") {
                    result.notImplemented()
                } else {
                    val target = when (call.arguments as? String) {
                        "tubi" -> "com.tubitv.ott"
                        "plex" -> "com.plexapp.android"
                        else -> null
                    }
                    if (target == null) {
                        result.error("unknown_app", "Unknown streaming app", null)
                    } else {
                        try {
                            val launch = packageManager.getLeanbackLaunchIntentForPackage(target)
                                ?: packageManager.getLaunchIntentForPackage(target)
                                ?: Intent(Intent.ACTION_VIEW,
                                    android.net.Uri.parse("amzn://apps/android?p=$target"))
                            startActivity(launch)
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("launch_failed", "Could not open streaming app", null)
                        }
                    }
                }
            }
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openiptv/pip")
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setPipAvailable" -> {
                    pipAvailable = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        backChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openiptv/back")
        backChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "setBlocked" -> {
                    backBlocked = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                // Second Back on the home tab: leave the app the way Android
                // does for a launcher activity — to the background, not
                // finished.
                "moveToBack" -> {
                    moveTaskToBack(true)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        updatesChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openiptv/updates")
        updatesChannel?.setMethodCallHandler(AppUpdater(this))
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openiptv/files")
            .setMethodCallHandler(FileSaver(this))
        // Fingerprint / face in place of the admin PIN (#47).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openiptv/biometric")
            .setMethodCallHandler(AdminBiometric(this))
        // Built-in WireGuard VPN (Power User Tools, #41).
        vpnController = VpnController(this).also {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "openiptv/vpn")
                .setMethodCallHandler(it)
        }

        // The video player and device channels are registered on every
        // engine by EngineChannels (so Android Auto can play with the app
        // closed); this window only keeps the screen on while playing.
        EngineChannels.onAnyPlayingChanged = { anyPlaying -> setKeepScreenOn(anyPlaying) }

        // TV text entry goes through a native EditText (see TvTextInput).
        if (isTelevision()) {
            TvTextInput(this, flutterEngine.dartExecutor.binaryMessenger)
        }

        // Casting is phone / tablet only: a TV, Fire TV or Android TV box is
        // the screen itself, so the Cast framework isn't even started there.
        if (!isTelevision()) {
            castController = CastController(
                applicationContext,
                flutterEngine.dartExecutor.binaryMessenger,
            )
        }
    }

    private fun isTelevision(): Boolean = EngineChannels.isTelevision(this)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingHomeChannelLink = intent.dataString
        homeCardsChannel?.invokeMethod("linkAvailable", null)
    }

    override fun onDestroy() {
        homeCardWorker.shutdown()
        super.onDestroy()
    }

    // Issue #28: the system's normal screen-timeout/screensaver rules apply
    // during playback because nothing was telling Android the device is in
    // active use. FLAG_KEEP_SCREEN_ON is the standard fix for this (what
    // ExoPlayer's own PlayerView does internally) — unlike a PowerManager
    // WakeLock it needs no permission and is scoped to this Window, so it's
    // released automatically if the Activity is destroyed while playing.
    private fun setKeepScreenOn(keepOn: Boolean) {
        runOnUiThread {
            if (keepOn) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    @Suppress("DEPRECATION", "MissingSuperCall")
    override fun onBackPressed() {
        if (backBlocked) {
            backChannel?.invokeMethod("backPressed", null)
        } else {
            super.onBackPressed()
        }
    }

    // Fired when the user presses Home (or otherwise leaves the activity)
    // while it's in the foreground.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && pipAvailable) {
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .build()
            val entered = enterPictureInPictureMode(params)
            Log.d("OTV-pip", "enterPictureInPictureMode returned=$entered")
        } else {
            // Not going to Picture-in-Picture: Dart decides whether to stop
            // what's playing (it does when the PiP setting is off).
            pipChannel?.invokeMethod("userLeft", null)
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        pipChannel?.invokeMethod("onPipModeChanged", isInPictureInPictureMode)
        // Left PiP: expanded (the activity comes back to the front) or
        // closed (X / swiped away). The lifecycle settles a moment after
        // this callback, so look again shortly.
        if (!isInPictureInPictureMode) {
            Handler(Looper.getMainLooper()).postDelayed({
                val back = lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.STARTED)
                Log.d("OTV-pip", "left PiP, activityVisible=$back")
                if (!back) {
                    // Kill the streams here, not only via Dart: nothing may
                    // play on after the PiP window is closed.
                    NativeVideoPlayerManager.stopAll()
                    pipChannel?.invokeMethod("pipDismissed", null)
                }
            }, 400)
        }
    }

    @Deprecated("Activity result for the VPN permission prompt")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VpnController.PERMISSION_REQUEST) {
            vpnController?.onPermissionResult(resultCode == RESULT_OK)
        }
    }
}
