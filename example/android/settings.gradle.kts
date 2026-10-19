pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // AGP 8.11.1 / Kotlin 2.2.20, not 9.x / 2.3.x: see the note in
    // gradle-wrapper.properties. These are Flutter 3.44's warning-free floor
    // (it errors below AGP 8.6 / KGP 2.0) and match the versions
    // flutter_embed_unity_2022_3_android is itself built with (AGP 8.7).
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")

// The exported Unity project is a build artifact and is not checked in, so
// include it only once it exists. Without this guard the example would not
// build at all until you have run Flutter Embed -> Export.
//
// Export target: <this folder>/unityLibrary
if (file("unityLibrary").exists()) {
    include(":unityLibrary")

    // Unity emits this extra module for XR projects. VoxUnity uses AR
    // Foundation, so the export will contain it and the build fails without it.
    if (file("unityLibrary/xrmanifest.androidlib").exists()) {
        include(":unityLibrary:xrmanifest.androidlib")
    }
}
