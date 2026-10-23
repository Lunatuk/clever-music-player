plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Android-only source kit. Direct rootBundle loads use Flutter's normal asset
// prefix; desktop bundles do not acquire a duplicate FFmpeg source archive.
val mediaAssets = layout.buildDirectory.dir("generated/cmp-media-assets")
val prepareMediaAssets = tasks.register<Copy>("prepareCmpMediaAssets") {
    into(mediaAssets)
    into("flutter_assets/third_party/cmp_android_media/vendor") {
        from(file("../../third_party/cmp_android_media/vendor"))
        include("NOTICE.txt", "COPYING.LGPLv2.1", "source-kit.zip")
    }
}

android {
    namespace = "dev.lunatuk.clever_music_player"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Separate sandbox and installation from the eventual production app.
        applicationId = "dev.lunatuk.clever_music_player.preview"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild { cmake { abiFilters += listOf("arm64-v8a") } }
    }

    buildTypes {
        release {
            // Local prototype only; production signing is a separate release step.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    externalNativeBuild {
        cmake {
            path = file("../../third_party/cmp_android_media/CMakeLists.txt")
            version = "3.22.1"
        }
    }
    sourceSets.getByName("main").assets.srcDir(mediaAssets)
}

tasks.named("preBuild").configure { dependsOn(prepareMediaAssets) }

flutter {
    source = "../.."
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
