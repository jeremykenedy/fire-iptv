import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Official releases receive signing credentials through the environment.
// Contributors can build with a debug key; build-release.py requires the
// stable private release key and never writes passwords into this checkout.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
    mapOf(
        "storeFile" to "FIRE_IPTV_KEYSTORE",
        "storePassword" to "FIRE_IPTV_STORE_PASSWORD",
        "keyAlias" to "FIRE_IPTV_KEY_ALIAS",
        "keyPassword" to "FIRE_IPTV_KEY_PASSWORD",
    ).forEach { (property, variable) ->
        System.getenv(variable)?.let { setProperty(property, it) }
    }
}
val hasReleaseKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "com.openiptv.app"
    compileSdk = 36
    // Pinned: the OpenVPN native build is tested with this NDK.
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time APIs).
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.jeremykenedy.fireiptv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Built-in OpenVPN (Power User Tools, #41): OpenVPN 3 core + mbed TLS,
        // compiled from pinned sources fetched by android/openvpn-deps.sh.
        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DOVPN_DEPS=${rootProject.file(".ovpn-deps").absolutePath}",
                    "-DANDROID_STL=c++_static",
                )
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
            // Resource shrinking (on by default for release) strips drawables that
            // are only referenced dynamically (platform-channel strings, adaptive-icon
            // XML) — it dropped the notification/monochrome icons entirely, causing
            // an uncaught PlatformException(invalid_icon) during main() that hung the
            // app at the splash screen. Not worth the APK-size tradeoff for this app.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

// Fetch the OpenVPN sources (once; the script exits early when ready)
// before CMake configures.
val fetchOpenVpnDeps by tasks.registering(Exec::class) {
    commandLine("bash", rootProject.file("openvpn-deps.sh").absolutePath)
    outputs.file(rootProject.file(".ovpn-deps/.ready"))
}
tasks.matching { it.name.startsWith("configureCMake") || it.name.startsWith("buildCMake") }
    .configureEach { dependsOn(fetchOpenVpnDeps) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Custom native video engine (see NativeVideoPlayer.kt) replacing
    // media_kit/mpv — ExoPlayer's hardware-decoder handling is far more
    // battle-tested across the fragmented Android device landscape.
    implementation("androidx.media3:media3-exoplayer:1.11.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.11.1")
    implementation("androidx.media3:media3-extractor:1.11.1")
    // Casting to Chromecast / Google TV (CastController.kt): Google Cast
    // framework + MediaRouter for device discovery.
    implementation("com.google.android.gms:play-services-cast-framework:22.3.1")
    implementation("androidx.mediarouter:mediarouter:1.8.1")
    // Built-in WireGuard VPN (VpnController.kt, Power User Tools #41).
    // Official userspace tunnel library, Apache-2.0.
    implementation("com.wireguard.android:tunnel:1.0.20260102")
}
