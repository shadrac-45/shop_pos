# ShopPOS ProGuard Rules
# Keep Isar native libraries
-keep class io.isar.** { *; }
-keep class dev.isar.** { *; }
-dontwarn io.isar.**

# Keep Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Keep crypto
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**
