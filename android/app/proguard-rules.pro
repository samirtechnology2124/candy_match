# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Flame
-keep class org.jbox2d.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn org.jbox2d.**
-dontwarn com.google.android.gms.**

# Play Core
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Keep all native methods
-keepclasseswithmembernames class * {
    native <methods>;
}