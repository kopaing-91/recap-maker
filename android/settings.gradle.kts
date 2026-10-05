pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localProps = file("local.properties")
            if (localProps.exists()) {
                localProps.inputStream().use { properties.load(it) }
            }
            var flutterSdkPath = properties.getProperty("flutter.sdk")
            if (flutterSdkPath == null) {
                flutterSdkPath = System.getenv("FLUTTER_SDK")
            }
            if (flutterSdkPath == null) {
                flutterSdkPath = System.getProperty("user.home") + "/sdks/flutter"
            }
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
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
}

include(":app")
