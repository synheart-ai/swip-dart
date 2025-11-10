import 'package:sqflite/sqflite.dart';

class BiosignalsRepo {
  final Database db;
  BiosignalsRepo(this.db);

  Future<void> insertBiosignal({
    required String appBiosignalId,
    required String appSessionId,
    required String timestamp,
    double? heartRate,
    double? hrvSdnn,
    double? hrvRmssd,
    double? ibi,
  }) async {
    await db.insert('dim_App_biosignals', {
      'app_biosignal_id': appBiosignalId,
      'app_session_id': appSessionId,
      'timestamp': timestamp,
      'heart_rate': heartRate,
      'hrv_sdnn': hrvSdnn,
      'hrv_rmssd': hrvRmssd,
      'ibi': ibi,
    });
  }

  /// Get all unsynced biosignals for a session, ordered by timestamp
  Future<List<Map<String, Object?>>> getUnsyncedBiosignalsForSession(
      String sessionId) async {
    return await db.query(
      'dim_App_biosignals',
      where: 'app_session_id = ? AND synced_to_cloud = 0',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  /// Mark biosignals as synced
  Future<void> markBiosignalsSynced(List<String> biosignalIds) async {
    if (biosignalIds.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final placeholders = biosignalIds.map((_) => '?').join(',');
    await db.rawUpdate(
      '''
      UPDATE dim_App_biosignals
      SET synced_to_cloud = 1, synced_at = ?
      WHERE app_biosignal_id IN ($placeholders)
      ''',
      [now, ...biosignalIds],
    );
  }
}
