plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val internalKeystorePath = providers.environmentVariable("KUNDI_INTERNAL_ANDROID_KEYSTORE_PATH").orNull?.trim().orEmpty()
val internalKeystorePassword = providers.environmentVariable("KUNDI_INTERNAL_ANDROID_KEYSTORE_PASSWORD").orNull.orEmpty()
val internalKeyAlias = providers.environmentVariable("KUNDI_INTERNAL_ANDROID_KEY_ALIAS").orNull?.trim().orEmpty()
val internalKeyPassword = providers.environmentVariable("KUNDI_INTERNAL_ANDROID_KEY_PASSWORD").orNull.orEmpty()
val internalSigningValues = listOf(
    internalKeystorePath,
    internalKeystorePassword,
    internalKeyAlias,
    internalKeyPassword,
)
val internalSigningConfigured = internalSigningValues.all { it.isNotEmpty() }
check(internalSigningValues.none { it.isNotEmpty() } || internalSigningConfigured) {
    "Android internal signing configuration is incomplete; provide all KUNDI_INTERNAL_ANDROID_* signing variables"
}
if (internalSigningConfigured) {
    check(file(internalKeystorePath).isFile) {
        "KUNDI_INTERNAL_ANDROID_KEYSTORE_PATH does not identify a readable file"
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
        if (internalSigningConfigured) {
            create("internalDistribution") {
                storeFile = file(internalKeystorePath)
                storePassword = internalKeystorePassword
                keyAlias = internalKeyAlias
                keyPassword = internalKeyPassword
            }
        }
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("internal") {
            dimension = "distribution"
            applicationId = "com.kundi.kundi_mobile.internal"
            if (internalSigningConfigured) {
                signingConfig = signingConfigs.getByName("internalDistribution")
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
    description = "Confirms that the future Play Store identity is intentionally not configured."
    dependsOn(verifyReleaseSigningPolicy)
    doLast {
        error("Production/store signing identity is intentionally not configured")
    }
}

tasks.register("verifyInternalReleaseConfiguration") {
    group = "verification"
    description = "Requires the stable external identity for private internal releases."
    dependsOn(verifyReleaseSigningPolicy)
    doLast {
        check(internalSigningConfigured) {
            "Internal distribution signing identity is not configured"
        }
        val internalFlavor = android.productFlavors.getByName("internal")
        check(internalFlavor.applicationId == "com.kundi.kundi_mobile.internal") {
            "Internal applicationId changed unexpectedly"
        }
        check(internalFlavor.signingConfig?.name == "internalDistribution") {
            "Internal release is not bound to the internal distribution signing identity"
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
    implementation("androidx.core:core-ktx:1.18.0")
    if (kundiTtsEnabled) {
        implementation("com.microsoft.cognitiveservices.speech:client-sdk:1.51.1")
    }
    testImplementation("junit:junit:4.13.2")
    if (kundiHomeRealtimeAvatarEnabled) {
        implementation("com.google.android.filament:filament-android:1.74.0")
        implementation("com.google.android.filament:gltfio-android:1.74.0")
    }
}
