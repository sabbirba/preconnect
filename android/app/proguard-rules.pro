# ── Kotlin ──────────────────────────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── Flutter / Dart JNI bridge ────────────────────────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.**

# ── WebView (webview_flutter_android) ───────────────────────────────────────
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-dontwarn android.webkit.**

# ── Mobile Scanner (ML Kit Barcode / ZXing) ──────────────────────────────────
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# ── Image Picker / File Selector ─────────────────────────────────────────────
-keep class androidx.activity.result.** { *; }

# ── Local Auth (BiometricPrompt) ──────────────────────────────────────────────
-keep class androidx.biometric.** { *; }

# ── Share Plus ────────────────────────────────────────────────────────────────
-keep class androidx.core.content.FileProvider { *; }

# ── In-App Update / Review (Play Core) ───────────────────────────────────────
-keep class com.google.android.play.** { *; }
-dontwarn com.google.android.play.**

# ── Open Filex ────────────────────────────────────────────────────────────────
-keep class com.crazecoder.openfile.** { *; }

# ── R8 Aggressive: Strip all Android Log calls from release ──────────────────
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
    public static int wtf(...);
    public static java.lang.String getStackTraceString(java.lang.Throwable);
}

# ── Remove source file names from stack traces (smaller + obfuscated) ────────
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable

# ── Parcelables ───────────────────────────────────────────────────────────────
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator *;
}

# ── Serializable ──────────────────────────────────────────────────────────────
-keepclassmembers class * implements java.io.Serializable {
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ── Enum support ──────────────────────────────────────────────────────────────
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
