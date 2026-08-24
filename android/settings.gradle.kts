pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localPropertiesFile = file("local.properties")
            val localPropertiesSdkPath =
                if (localPropertiesFile.exists()) {
                    localPropertiesFile.inputStream().use { properties.load(it) }
                    properties.getProperty("flutter.sdk")
                } else {
                    null
                }

            System.getenv("FLUTTER_ROOT")
                ?: localPropertiesSdkPath
                ?: error("Flutter SDK path not found. Set FLUTTER_ROOT or flutter.sdk in android/local.properties.")
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
    id("com.android.application") version "9.3.2" apply false
    id("com.google.gms.google-services") version ("4.5.0") apply false
    id("org.jetbrains.kotlin.android") version "2.4.10" apply false
}

include(":app")
