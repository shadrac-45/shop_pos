/// ============================================
/// Notification Service & Provider — ShopPOS
/// ============================================
/// Handles local notifications for expiry alerts.
/// ============================================
library;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService();
});

class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Initialize the plugin
  Future<void> init() async {
    if (_initialized) return;

    // Android initialization settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // Define initialization settings
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification tap
      },
    );

    _initialized = true;
  }

  /// Show a stock alert (expiring and/or low-stock products).
  /// [title] defaults to "N Products Expiring Soon".
  Future<void> showExpiryAlert({
    required int expiringCount,
    required String body,
    String? title,
  }) async {
    if (!_initialized) await init();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'expiry_alerts_channel',
      'Expiry Alerts',
      channelDescription: 'Products expiring soon or running low on stock',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      color: Color(0xFFF85149), // AppColors.danger
    );

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    await _flutterLocalNotificationsPlugin.show(
      0, // Notification ID
      title ?? '$expiringCount Products Need Attention',
      body,
      platformChannelSpecifics,
      payload: 'expiry_alert',
    );
  }
}
