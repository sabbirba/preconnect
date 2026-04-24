import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")

    id("dev.flutter.flutter-gradle-plugin")
}


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
val androidAdAppId = "ca-app-pub-3940256099942544~1458002511"
val rewardedAdUnitId = envOrProp("REWARDED_AD_UNIT_ID").orEmpty()
val bannerAdUnitId = envOrProp("BANNER_AD_UNIT_ID").orEmpty()
val interstitialAdUnitId = envOrProp("INTERSTITIAL_AD_UNIT_ID").orEmpty()

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
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    buildFeatures {
        buildConfig = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }

    defaultConfig {

        applicationId = "com.sabbirba.preconnect"


        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["adAppId"] = androidAdAppId
        buildConfigField("String", "REWARDED_AD_UNIT_ID", "\"$rewardedAdUnitId\"")
        buildConfigField("String", "BANNER_AD_UNIT_ID", "\"$bannerAdUnitId\"")
        buildConfigField("String", "INTERSTITIAL_AD_UNIT_ID", "\"$interstitialAdUnitId\"")

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
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("com.google.android.play:feature-delivery:2.1.0")
    implementation("com.google.android.play:feature-delivery-ktx:2.1.0")
    implementation("com.google.android.play:app-update:2.1.0")
    implementation("com.google.android.play:app-update-ktx:2.1.0")
    implementation("com.google.android.play:integrity:1.4.0")
    implementation("com.android.installreferrer:installreferrer:2.2")
    implementation("com.google.android.play:core-common:2.0.4")
    implementation("com.google.android.gms:play-services-ads:25.1.0")
}
