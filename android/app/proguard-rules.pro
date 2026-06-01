# ── Kotlin ──────────────────────────────────────────────────────────────────
-dontwarn kotlin.**
-dontwarn kotlinx.**

# ── WebView (webview_flutter_android) ───────────────────────────────────────
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-dontwarn android.webkit.**

# ── Don't warn for other transient packages ──────────────────────────────────
-dontwarn io.flutter.**
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.**

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
