import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("dev.flutter.flutter-gradle-plugin")
}

val projectNdkVersion = "28.2.13676358"

fun envOrProp(name: String): String? =
    envFromDotEnv(name)
        ?: (findProperty(name) as String?)
        ?: (rootProject.findProperty(name) as String?)
        ?: System.getenv(name)

fun envFromDotEnv(name: String): String? {
    val envFile = rootProject.file("../.env")
    if (!envFile.exists()) return null
    for (line in envFile.readLines()) {
        val trimmed = line.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("#") || !trimmed.contains("=")) continue
        val idx = trimmed.indexOf('=')
        val key = trimmed.substring(0, idx).trim()
        if (key == name) {
            return trimmed.substring(idx + 1).trim()
        }
    }
    return null
}

android {
    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")

    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    fun keystoreValue(key: String): String? =
        keystoreProperties.getProperty(key) ?: envOrProp(key)

    val releaseKeystorePath = keystoreValue("storeFile")?.trim().orEmpty()
    val releaseKeystoreFile = if (releaseKeystorePath.isNotEmpty()) {
        rootProject.file(releaseKeystorePath)
    } else {
        null
    }
    val hasReleaseSigningConfig = listOf(
        "storeFile",
        "storePassword",
        "keyAlias",
        "keyPassword",
    ).all { !keystoreValue(it).isNullOrBlank() } && releaseKeystoreFile?.exists() == true

    namespace = "com.sabbirba.preconnect"
    compileSdk = 36
    ndkVersion = projectNdkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    buildFeatures {
        buildConfig = false
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
        disable += setOf("EasterEgg", "StopShip")
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {

        applicationId = "com.sabbirba.preconnect"


        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resConfigs("en")

    }


    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                if (releaseKeystoreFile != null) {
                    storeFile = releaseKeystoreFile
                }
                storePassword = keystoreValue("storePassword")
                keyAlias = keystoreValue("keyAlias")
                keyPassword = keystoreValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            isDebuggable = false
            isPseudoLocalesEnabled = false
            isMinifyEnabled = true
            isShrinkResources = true
            isCrunchPngs = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            ndk {
                debugSymbolLevel = "SYMBOL_TABLE"
            }
        }
    }

    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    implementation("com.google.android.gms:play-services-location:21.4.0")
}

configurations.all {
    resolutionStrategy {
        force("com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1")
        force("com.google.firebase:firebase-messaging:25.1.1")
    }
}


