/// Response from SWIP API
class SyncResponse {
  final bool ok;
  final int? swipScore;
  final String? error;

  SyncResponse({
    required this.ok,
    this.swipScore,
    this.error,
  });

  factory SyncResponse.fromJson(Map<String, dynamic> json) {
    return SyncResponse(
      ok: json['ok'] as bool? ?? false,
      swipScore: json['swip_score'] as int?,
      error: json['error'] as String?,
    );
  }
}

/// Sync status for a session
class SessionSyncStatus {
  final String sessionId;
  final bool synced;
  final int attempts;
  final DateTime? lastAttempt;
  final String? lastError;
  final DateTime? syncedAt;

  SessionSyncStatus({
    required this.sessionId,
    required this.synced,
    required this.attempts,
    this.lastAttempt,
    this.lastError,
    this.syncedAt,
  });
}
