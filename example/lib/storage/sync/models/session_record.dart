class SessionRecord {
  final String appSessionId;
  final String userId;
  final String deviceId;
  final String startedAt;
  final String? endedAt;
  final String appId;
  final int dataOnCloud;
  final double? avgSwipScore;

  SessionRecord({
    required this.appSessionId,
    required this.userId,
    required this.deviceId,
    required this.startedAt,
    required this.endedAt,
    required this.appId,
    required this.dataOnCloud,
    required this.avgSwipScore,
  });

  Map<String, dynamic> toJson() {
    return {
      'app_session_id': appSessionId,
      'user_id': userId,
      'device_id': deviceId,
      'started_at': startedAt,
      'ended_at': endedAt,
      'app_id': appId,
      'data_on_cloud': dataOnCloud,
      'avg_swip_score': avgSwipScore,
    };
  }
}
