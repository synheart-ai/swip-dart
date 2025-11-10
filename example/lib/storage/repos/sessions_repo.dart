import 'package:sqflite/sqflite.dart';

class SessionsRepo {
  final Database db;
  SessionsRepo(this.db);

  Future<void> insertSession({
    required String appSessionId,
    required String userId,
    String? deviceId,
    required String startedAt,
    required String appId,
    bool dataOnCloud = false,
  }) async {
    await db.insert('dim_App_Session', {
      'app_session_id': appSessionId,
      'user_id': userId,
      'device_id': deviceId,
      'started_at': startedAt,
      'app_id': appId,
      'data_on_cloud': dataOnCloud ? 1 : 0,
    });
  }

  Future<void> endSession({
    required String appSessionId,
    required String endedAt,
    double? avgSwipScore,
  }) async {
    await db.update(
      'dim_App_Session',
      {
        'ended_at': endedAt,
        if (avgSwipScore != null) 'avg_swip_score': avgSwipScore,
      },
      where: 'app_session_id = ?',
      whereArgs: [appSessionId],
    );
  }

  /// Get all unsynced sessions, ordered by start time
  Future<List<Map<String, dynamic>>> getUnsyncedSessions() async {
    return await db.query(
      'dim_App_Session',
      where: 'synced_to_cloud = 0 AND ended_at IS NOT NULL',
      orderBy: 'started_at ASC',
    );
  }

  /// Mark session as synced
  Future<void> markSynced({
    required String appSessionId,
    required String syncedAt,
  }) async {
    await db.update(
      'dim_App_Session',
      {
        'synced_to_cloud': 1,
        'synced_at': syncedAt,
        'last_sync_attempt': syncedAt,
        'last_sync_error': null,
      },
      where: 'app_session_id = ?',
      whereArgs: [appSessionId],
    );
  }

  /// Update sync attempt (for failures)
  Future<void> updateSyncAttempt({
    required String appSessionId,
    required String lastSyncAttempt,
    String? error,
  }) async {
    // Get current attempts count
    final current = await db.query(
      'dim_App_Session',
      columns: ['sync_attempts'],
      where: 'app_session_id = ?',
      whereArgs: [appSessionId],
      limit: 1,
    );

    final currentAttempts = (current.first['sync_attempts'] as int?) ?? 0;

    await db.update(
      'dim_App_Session',
      {
        'last_sync_attempt': lastSyncAttempt,
        'last_sync_error': error,
        'sync_attempts': currentAttempts + 1,
      },
      where: 'app_session_id = ?',
      whereArgs: [appSessionId],
    );
  }

  /// Get sync statistics
  Future<Map<String, dynamic>> getSyncStats() async {
    final total = await db.rawQuery('''
      SELECT COUNT(*) as count FROM dim_App_Session WHERE ended_at IS NOT NULL
    ''');
    final synced = await db.rawQuery('''
      SELECT COUNT(*) as count FROM dim_App_Session 
      WHERE synced_to_cloud = 1 AND ended_at IS NOT NULL
    ''');
    final unsynced = await db.rawQuery('''
      SELECT COUNT(*) as count FROM dim_App_Session 
      WHERE synced_to_cloud = 0 AND ended_at IS NOT NULL
    ''');

    return {
      'total': total.first['count'] as int? ?? 0,
      'synced': synced.first['count'] as int? ?? 0,
      'unsynced': unsynced.first['count'] as int? ?? 0,
    };
  }

  /// Get sessions that have unsynced biosignals (even if session is synced)
  Future<List<String>> getSessionsWithUnsyncedBiosignals() async {
    final result = await db.rawQuery('''
      SELECT DISTINCT s.app_session_id
      FROM dim_App_Session s
      INNER JOIN dim_App_biosignals b ON s.app_session_id = b.app_session_id
      WHERE s.ended_at IS NOT NULL
        AND b.synced_to_cloud = 0
      ORDER BY s.started_at ASC
    ''');
    return result.map((row) => row['app_session_id'] as String).toList();
  }

  /// Get sessions that have unsynced emotions
  Future<List<String>> getSessionsWithUnsyncedEmotions() async {
    final result = await db.rawQuery('''
      SELECT DISTINCT s.app_session_id
      FROM dim_App_Session s
      INNER JOIN dim_App_biosignals b ON s.app_session_id = b.app_session_id
      INNER JOIN dim_emotions e ON e.app_biosignal_id = b.app_biosignal_id
      WHERE s.ended_at IS NOT NULL
        AND (e.synced_to_cloud = 0 OR e.synced_to_cloud IS NULL)
      ORDER BY s.started_at ASC
    ''');
    return result.map((row) => row['app_session_id'] as String).toList();
  }
}
