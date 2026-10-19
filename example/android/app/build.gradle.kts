plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vox_example"
    compileSdk = flutter.compileSdkVersion

    // Must be >= the NDK Unity built with: r23.1.7779620 for Unity 2022.3,
    // r27.2.12479018 for Unity 6000.0. Flutter's pinned version is already
    // newer than the 2022.3 requirement, so it is left alone deliberately --
    // pinning an older one here would be a downgrade. On Unity 6000.0, set this
    // explicitly to "27.2.12479018" or later.
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.vox_example"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // VoxUnity declares AndroidMinSdkVersion 24 in its ProjectSettings, and
        // the exported unityLibrary carries that into the manifest merge. A
        // lower value here fails with "uses-sdk:minSdkVersion N cannot be
        // smaller than version 24 declared in library [:unityLibrary]".
        // maxOf so Flutter's own floor is never lowered either.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    androidResources {
        // Unity's resources are already compressed during export. Compressing
        // them a second time here measurably slows Unity's load time.
        val unityStreamingAssetsList =
            (project.findProperty("unityStreamingAssets") as? String)
                ?.split(",")
                ?.map { it.trim() }
                ?.filter { it.isNotEmpty() }
                ?: emptyList()

        noCompress += listOf(
            ".unity3d", ".ress", ".resource", ".obb", ".bundle", ".unityexp",
        ) + unityStreamingAssetsList

        ignoreAssetsPattern =
            "!.svn:!.git:!.ds_store:!*.scc:!CVS:!thumbs.db:!picasa.ini:!*~"
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

dependencies {
    // Present only after exporting from Unity; see settings.gradle.kts.
    rootProject.findProject(":unityLibrary")?.let { implementation(it) }
}
