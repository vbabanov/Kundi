plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val kundiHomeRealtimeAvatarEnabled =
    providers.gradleProperty("ENABLE_KUNDI_HOME_REALTIME_AVATAR")
        .orElse(providers.environmentVariable("ENABLE_KUNDI_HOME_REALTIME_AVATAR"))
        .map { it.equals("true", ignoreCase = true) }
        .orElse(false)
        .get()
val kundiVoiceInputEnabled =
    providers.gradleProperty("ENABLE_KUNDI_VOICE_INPUT")
        .orElse(providers.environmentVariable("ENABLE_KUNDI_VOICE_INPUT"))
        .map { it.equals("true", ignoreCase = true) }
        .orElse(false)
        .get()
val kundiHomeAvatarGracePeriodMillis =
    providers.gradleProperty("KUNDI_HOME_AVATAR_GRACE_PERIOD_MS")
        .orElse(providers.environmentVariable("KUNDI_HOME_AVATAR_GRACE_PERIOD_MS"))
        .orElse("30000")
        .get()
        .toLongOrNull()
        ?: error("KUNDI_HOME_AVATAR_GRACE_PERIOD_MS must be an integer")
check(kundiHomeAvatarGracePeriodMillis in 0L..120_000L) {
    "KUNDI_HOME_AVATAR_GRACE_PERIOD_MS must be between 0 and 120000"
}
val kundiHomeAvatarSourceFile =
    layout.projectDirectory.file("../../assets/models/kundi/kundi_home_mobile.glb")
val generatedKundiHomeAvatarAssets =
    layout.buildDirectory.dir("generated/kundiHomeRealtimeAvatar/assets")
val prepareKundiHomeAvatarAsset =
    tasks.register<Copy>("prepareKundiHomeAvatarAsset") {
        onlyIf { kundiHomeRealtimeAvatarEnabled }
        from(kundiHomeAvatarSourceFile)
        into(generatedKundiHomeAvatarAssets.map { it.dir("kundi") })
        rename { "kundi_home_mobile.glb" }
    }

android {
    namespace = "com.kundi.kundi_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kundi.kundi_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField(
            "boolean",
            "KUNDI_HOME_REALTIME_AVATAR_ENABLED",
            kundiHomeRealtimeAvatarEnabled.toString(),
        )
        buildConfigField(
            "long",
            "KUNDI_HOME_AVATAR_GRACE_PERIOD_MS",
            "${kundiHomeAvatarGracePeriodMillis}L",
        )
        buildConfigField(
            "boolean",
            "KUNDI_VOICE_INPUT_ENABLED",
            kundiVoiceInputEnabled.toString(),
        )
        manifestPlaceholders["kundiRecordAudioPermission"] =
            if (kundiVoiceInputEnabled) {
                "android.permission.RECORD_AUDIO"
            } else {
                "android.permission.INTERNET"
            }
        manifestPlaceholders["kundiRecognitionServiceAction"] =
            if (kundiVoiceInputEnabled) {
                "android.speech.RecognitionService"
            } else {
                "com.kundi.kundi_mobile.DISABLED_VOICE_INPUT"
            }
        if (kundiHomeRealtimeAvatarEnabled) {
            ndk {
                abiFilters += "arm64-v8a"
            }
        }
    }

    if (kundiHomeRealtimeAvatarEnabled) {
        sourceSets.getByName("main").java.srcDir("src/nativeAvatar/kotlin")
        sourceSets.getByName("main").assets.srcDir(generatedKundiHomeAvatarAssets)
        sourceSets.getByName("test").java.srcDir("src/nativeAvatarTest/kotlin")
        packaging {
            jniLibs {
                excludes +=
                    setOf(
                        "lib/armeabi-v7a/**",
                        "lib/x86_64/**",
                    )
            }
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

if (kundiHomeRealtimeAvatarEnabled) {
    tasks.configureEach {
        if (name.startsWith("merge") && name.endsWith("Assets")) {
            dependsOn(prepareKundiHomeAvatarAsset)
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    if (kundiHomeRealtimeAvatarEnabled) {
        implementation("com.google.android.filament:filament-android:1.74.0")
        implementation("com.google.android.filament:gltfio-android:1.74.0")
    }
}
