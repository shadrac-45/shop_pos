# This file exists to support the release buildType's isMinifyEnabled = true.
# Without it, the build fails because android/app/build.gradle.kts references
# "proguard-rules.pro" via proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro").
#
# Rules below keep classes that are reflectively accessed by Flutter, its plugins,
# and the native libraries used by this app. Package prefixes were verified against
# android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java.

# Flutter embedding and platform code
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Play Core / deferred components (referenced by flutter embedding)
-dontwarn com.google.android.play.core.**

# Kotlin stdlib and kotlinx
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }

# Isar (native-backed DB) - reflectively accessed
-keep class dev.isar.** { *; }
-keep class isar.** { *; }
-keepclassmembers class * extends dev.isar.** { *; }

# flutter_local_notifications (com.dexterous.flutterlocalnotifications) uses Gson/reflection on receivers and channels
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# mobile_scanner (dev.steenbakker.mobile_scanner) - ML Kit barcode scanning
-keep class dev.steenbakker.** { *; }
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# file_picker (com.mr.flutter.plugin.filepicker)
-keep class com.mr.flutter.** { *; }

# connectivity_plus (dev.fluttercommunity.plus.connectivity)
-keep class dev.fluttercommunity.** { *; }

# jni / jni_flutter (com.github.dart_lang.jni, com.github.dart_lang.jni_flutter)
-keep class com.github.dart_lang.** { *; }

# shared_preferences (io.flutter.plugins.sharedpreferences) - already covered by io.flutter.plugins.**

# JNI native methods must survive minification
-keepclassmembers class * {
    native <methods>;
}
