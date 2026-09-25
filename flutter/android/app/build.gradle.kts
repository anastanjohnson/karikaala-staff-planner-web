import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val appProperties = Properties().apply {
    val source = rootProject.file("release.properties")
    if (source.exists()) source.inputStream().use { load(it) }
}
val keyProperties = Properties().apply {
    val source = rootProject.file("key.properties")
    if (source.exists()) source.inputStream().use { load(it) }
}
val signingReady = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
    .all { !keyProperties.getProperty(it).isNullOrBlank() }
val requestedRelease = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
if (requestedRelease && !signingReady) {
    throw GradleException("Release signing is not configured. See release/GOOGLE_PLAY_HANDOFF.md. Debug keys are never used for release.")
}

android {
    namespace = "com.example.onboarding_flutter"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = appProperties.getProperty("applicationId", "com.example.onboarding_flutter")
        manifestPlaceholders["appLabel"] = appProperties.getProperty("appName", "Onboarding Preview")
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (signingReady) {
            create("release") {
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
            }
        }
    }
    buildTypes {
        release {
            if (signingReady) signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
