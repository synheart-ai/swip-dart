import 'package:sqflite/sqflite.dart';

import 'models/sync_payload.dart';
import 'logging.dart';
import 'models/session_record.dart';
import 'models/biosignal_record.dart';

class DataTransformer {
  final Database db;

  DataTransformer(this.db);

  /// Build a session record from DB matching the API format
  Future<SessionRecord?> buildSessionRecord(String sessionId) async {
    final rows = await db.query(
      'dim_App_Session',
      where: 'app_session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) {
      logSync('warn', 'Session not found for record build', extra: {'sessionId': sessionId});
      return null;
    }
    final r = rows.first;
    return SessionRecord(
      appSessionId: r['app_session_id'] as String,
      userId: r['user_id'] as String,
      deviceId: (r['device_id'] as String?) ?? '',
      startedAt: r['started_at'] as String,
      endedAt: r['ended_at'] as String?,
      appId: r['app_id'] as String,
      dataOnCloud: (r['data_on_cloud'] as int?) ?? 0,
      avgSwipScore: (r['avg_swip_score'] as num?)?.toDouble(),
    );
  }

  /// Transform a session from local DB to API payload format
  Future<SyncPayload?> transformSession(String sessionId) async {
    logSync('debug', 'Transforming session to payload', extra: {'sessionId': sessionId});
    // Get session data
    final sessionResult = await db.query(
      'dim_App_Session',
      where: 'app_session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );

    if (sessionResult.isEmpty) {
      logSync('warn', 'Session not found during transform', extra: {'sessionId': sessionId});
      return null;
    }

    final session = sessionResult.first;
    final appId = session['app_id'] as String;
    final startedAt = session['started_at'] as String;

    // Get all biosignals for this session, ordered by timestamp
    final biosignalsResult = await db.query(
      'dim_App_biosignals',
      where: 'app_session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    // Aggregate HR values
    final hrValues = <double>[];
    final rrValues = <double>[];
    double? avgSdnn;
    double? avgRmssd;
    double sdnnSum = 0.0;
    double rmssdSum = 0.0;
    int hrvCount = 0;

    for (final biosignal in biosignalsResult) {
      final hr = biosignal['heart_rate'] as num?;
      if (hr != null) {
        hrValues.add(hr.toDouble());
      }

      final rr = biosignal['respiratory_rate'] as num?;
      if (rr != null) {
        rrValues.add(rr.toDouble());
      }

      final sdnn = biosignal['hrv_sdnn'] as num?;
      final rmssd = biosignal['hrv_rmssd'] as num?;

      if (sdnn != null) {
        sdnnSum += sdnn.toDouble();
        hrvCount++;
      }

      if (rmssd != null) {
        rmssdSum += rmssd.toDouble();
      }
    }

    // Calculate average HRV metrics
    if (hrvCount > 0) {
      avgSdnn = sdnnSum / hrvCount;
      if (rmssdSum > 0) {
        avgRmssd = rmssdSum / hrvCount;
      }
    }

    // Get latest emotion for this session
    String? latestEmotion;
    final emotionResult = await db.rawQuery('''
      SELECT e.dominant_emotion
      FROM dim_emotions e
      INNER JOIN dim_App_biosignals b ON e.app_biosignal_id = b.app_biosignal_id
      WHERE b.app_session_id = ?
      ORDER BY e.id DESC
      LIMIT 1
    ''', [sessionId]);

    if (emotionResult.isNotEmpty) {
      latestEmotion = emotionResult.first['dominant_emotion'] as String?;
    }

    // Build HRV metrics
    HrvMetrics? hrv;
    if (avgSdnn != null || avgRmssd != null) {
      hrv = HrvMetrics(
        sdnn: avgSdnn,
        rmssd: avgRmssd,
      );
    }

    // Build metrics
    final metrics = SessionMetrics(
      hr: hrValues.isNotEmpty ? hrValues : null,
      rr: rrValues.isNotEmpty ? rrValues : null,
      hrv: hrv,
      emotion: latestEmotion,
      timestamp: startedAt,
    );

    final payload = SyncPayload(
      appId: appId,
      sessionId: sessionId,
      metrics: metrics,
    );
    logSync('debug', 'Transform complete', extra: {
      'sessionId': sessionId,
      'hrCount': hrValues.length,
      'rrCount': rrValues.length,
      'hasHRV': hrv != null,
      'emotion': latestEmotion,
    });
    return payload;
  }

  /// Build biosignal records for a session
  Future<List<BiosignalRecord>> buildBiosignalRecords(String sessionId) async {
    final rows = await db.query(
      'dim_App_biosignals',
      where: 'app_session_id = ? AND synced_to_cloud = 0',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    return rows.map((row) {
      // Handle gyro - if stored as single value, convert to array [value, 0, 0]
      // If it's already an array or null, handle accordingly
      List<double>? gyro;
      final gyroValue = row['gyro'] as num?;
      if (gyroValue != null) {
        // For now, assume single value and convert to array
        gyro = [gyroValue.toDouble(), 0.0, 0.0];
      }

      return BiosignalRecord(
        appBiosignalId: row['app_biosignal_id'] as String,
        appSessionId: row['app_session_id'] as String,
        timestamp: row['timestamp'] as String,
        respiratoryRate: (row['respiratory_rate'] as num?)?.toDouble(),
        hrvSdnn: (row['hrv_sdnn'] as num?)?.toDouble(),
        heartRate: (row['heart_rate'] as num?)?.toDouble(),
        accelerometer: (row['accelerometer'] as num?)?.toDouble(),
        temperature: (row['temperature'] as num?)?.toDouble(),
        bloodOxygenSaturation:
            (row['blood_oxygen_saturation'] as num?)?.toDouble(),
        ecg: (row['ecg'] as num?)?.toDouble(),
        emg: (row['emg'] as num?)?.toDouble(),
        eda: (row['eda'] as num?)?.toDouble(),
        gyro: gyro,
        ppg: (row['ppg'] as num?)?.toDouble(),
        ibi: (row['ibi'] as num?)?.toDouble(),
      );
    }).toList();
  }
}
