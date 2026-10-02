/// ============================================
/// Session Manager — ShopPOS
/// ============================================
/// Manages user session lifecycle with inactivity
/// timeout and auto-logout functionality.
/// ============================================
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'package:shop_pos/features/auth/providers/auth_provider.dart';

// ── Session Configuration ────────────────────────────────────────

/// Session timeout duration: 15 minutes of inactivity
const kSessionTimeoutDuration = Duration(minutes: 15);

/// Inactivity check interval: check every minute
const kSessionCheckInterval = Duration(minutes: 1);

// ── Provider ─────────────────────────────────────────────────────

final sessionManagerProvider = Provider((ref) {
  return SessionManager(ref);
});

// ── Session Manager ──────────────────────────────────────────────

class SessionManager {
  final Ref ref;
  
  Timer? _inactivityTimer;
  DateTime _lastActivityTime = DateTime.now();
  
  // Track session start time and total login duration
  DateTime? _sessionStartTime;
  
  SessionManager(this.ref);

  /// Start session tracking. Call this after successful login.
  void startSession() {
    _sessionStartTime = DateTime.now();
    _lastActivityTime = DateTime.now();
    _resetInactivityTimer();
    
    debugPrint(
      '[SessionManager] Session started at ${_sessionStartTime?.toIso8601String()}',
    );
  }

  /// Record user activity. Called for every pointer-down anywhere in the
  /// app (see ShopPOSApp), so any interaction keeps the session alive.
  void recordActivity() {
    // Taps on the login screens must not start a timer for nobody.
    if (_sessionStartTime == null) return;
    // A reset password/PIN or a deactivation ends the session at once.
    ref.read(currentUserProvider.notifier).checkSessionStillValid();
    if (_sessionStartTime == null) return;
    _lastActivityTime = DateTime.now();
    _resetInactivityTimer();
  }

  /// End session and cleanup. Call this on logout.
  void endSession() {
    _inactivityTimer?.cancel();
    _sessionStartTime = null;
    debugPrint('[SessionManager] Session ended');
  }

  /// Get elapsed session duration.
  Duration? getSessionDuration() {
    if (_sessionStartTime == null) return null;
    return DateTime.now().difference(_sessionStartTime!);
  }

  /// Get last activity time.
  DateTime get lastActivityTime => _lastActivityTime;

  /// Get time remaining before auto-logout.
  Duration get timeUntilTimeout {
    final elapsed = DateTime.now().difference(_lastActivityTime);
    return kSessionTimeoutDuration.compareTo(elapsed) > 0
        ? kSessionTimeoutDuration - elapsed
        : Duration.zero;
  }

  /// Check if session is active.
  bool get isSessionActive {
    if (_sessionStartTime == null) return false;
    return DateTime.now().difference(_lastActivityTime) < kSessionTimeoutDuration;
  }

  /// Reset the inactivity timer.
  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    
    _inactivityTimer = Timer(kSessionTimeoutDuration, () async {
      debugPrint('[SessionManager] Session timeout due to inactivity');
      await _handleSessionTimeout();
    });
  }

  /// Handle session timeout by logging out the user.
  Future<void> _handleSessionTimeout() async {
    debugPrint('[SessionManager] Logging out due to inactivity');
    
    // Logs the timeout to the activity log; ShopPOSApp then returns to
    // the role picker.
    ref.read(currentUserProvider.notifier).logout(timedOut: true);
  }

  /// Clean up resources.
  void dispose() {
    _inactivityTimer?.cancel();
  }
}
