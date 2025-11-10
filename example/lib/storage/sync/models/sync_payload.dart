/// Payload format for SWIP API ingestion
class SyncPayload {
  final String appId;
  final String sessionId;
  final SessionMetrics metrics;

  SyncPayload({
    required this.appId,
    required this.sessionId,
    required this.metrics,
  });

  Map<String, dynamic> toJson() {
    return {
      'app_id': appId,
      'session_id': sessionId,
      'metrics': metrics.toJson(),
    };
  }
}

class SessionMetrics {
  final List<double>? hr;
  final List<double>? rr;
  final HrvMetrics? hrv;
  final String? emotion;
  final String timestamp;

  SessionMetrics({
    this.hr,
    this.rr,
    this.hrv,
    this.emotion,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'timestamp': timestamp,
    };

    if (hr != null && hr!.isNotEmpty) {
      json['hr'] = hr;
    }

    if (rr != null && rr!.isNotEmpty) {
      json['rr'] = rr;
    }

    if (hrv != null) {
      json['hrv'] = hrv!.toJson();
    }

    if (emotion != null) {
      json['emotion'] = emotion!.toLowerCase();
    }

    return json;
  }
}

class HrvMetrics {
  final double? sdnn;
  final double? rmssd;

  HrvMetrics({this.sdnn, this.rmssd});

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (sdnn != null) json['sdnn'] = sdnn;
    if (rmssd != null) json['rmssd'] = rmssd;
    return json;
  }
}
