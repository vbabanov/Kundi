plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = providers.environmentVariable("KUNDI_ANDROID_KEYSTORE_PATH").orNull?.trim().orEmpty()
val releaseKeystorePassword = providers.environmentVariable("KUNDI_ANDROID_KEYSTORE_PASSWORD").orNull.orEmpty()
val releaseKeyAlias = providers.environmentVariable("KUNDI_ANDROID_KEY_ALIAS").orNull?.trim().orEmpty()
val releaseKeyPassword = providers.environmentVariable("KUNDI_ANDROID_KEY_PASSWORD").orNull.orEmpty()
val releaseSigningValues = listOf(
    releaseKeystorePath,
    releaseKeystorePassword,
    releaseKeyAlias,
    releaseKeyPassword,
)
val productionSigningConfigured = releaseSigningValues.all { it.isNotEmpty() }
check(releaseSigningValues.none { it.isNotEmpty() } || productionSigningConfigured) {
    "Android release signing configuration is incomplete; provide all KUNDI_ANDROID_* signing variables"
}
if (productionSigningConfigured) {
    check(file(releaseKeystorePath).isFile) {
        "KUNDI_ANDROID_KEYSTORE_PATH does not identify a readable file"
    }
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
val kundiTtsEnabled = providers.gradleProperty("ENABLE_KUNDI_TTS")
    .orElse(providers.environmentVariable("ENABLE_KUNDI_TTS"))
    .map { it.equals("true", ignoreCase = true) }.orElse(false).get()
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
    sourceSets.getByName("main").java.srcDir(if (kundiTtsEnabled) "src/tts/kotlin" else "src/ttsOff/kotlin")
    if (kundiTtsEnabled) sourceSets.getByName("test").java.srcDir("src/ttsTest/kotlin")
    if (kundiTtsEnabled) {
        // JAR indexes are unused on Android; preserve Netty version metadata.
        packaging.resources.excludes += "META-INF/INDEX.LIST"
        packaging.resources.merges += "META-INF/io.netty.versions.properties"
        packaging.jniLibs.excludes += setOf(
            "**/libMicrosoft.CognitiveServices.Speech.extension.kws*.so",
            "**/libMicrosoft.CognitiveServices.Speech.extension.silk_codec.so",
        )
    }
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (productionSigningConfigured) {
            create("production") {
                storeFile = file(releaseKeystorePath)
                storePassword = releaseKeystorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
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
        // SDK 1.51.1's Azure-core/Netty use MethodHandle APIs (Android O).
        minSdk = if (kundiTtsEnabled) maxOf(26, flutter.minSdkVersion) else flutter.minSdkVersion
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
        // Flutter filters its own binaries; the SDK AAR also needs the requested ABI.
        if (kundiHomeRealtimeAvatarEnabled || (kundiTtsEnabled &&
            providers.gradleProperty("target-platform").orElse("").get() == "android-arm64")) {
            ndk {
                abiFilters.clear()
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
            if (kundiTtsEnabled) proguardFiles("tts-proguard-rules.pro")
            signingConfig =
                if (productionSigningConfigured) {
                    signingConfigs.getByName("production")
                } else {
                    null
                }
        }
    }
}

val verifyReleaseSigningPolicy =
    tasks.register("verifyReleaseSigningPolicy") {
        group = "verification"
        description = "Rejects accidental debug signing of Android release artifacts."
        doLast {
            val signingName = android.buildTypes.getByName("release").signingConfig?.name
            check(signingName != "debug") {
                "Release artifacts must never use the debug signing identity"
            }
        }
    }

tasks.register("verifyProductionSigningConfiguration") {
    group = "verification"
    description = "Requires an approved external Android release identity."
    dependsOn(verifyReleaseSigningPolicy)
    doLast {
        check(productionSigningConfigured) {
            "Production signing identity is not configured; publishing is blocked"
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(verifyReleaseSigningPolicy)
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
    if (kundiTtsEnabled) {
        implementation("com.microsoft.cognitiveservices.speech:client-sdk:1.51.1")
    }
    testImplementation("junit:junit:4.13.2")
    if (kundiHomeRealtimeAvatarEnabled) {
        implementation("com.google.android.filament:filament-android:1.74.0")
        implementation("com.google.android.filament:gltfio-android:1.74.0")
    }
}
