import 'package:sqflite/sqflite.dart';

class EmotionsRepo {
  final Database db;
  EmotionsRepo(this.db);

  Future<void> insertEmotion({
    required String appBiosignalId,
    double? swipScore,
    double? physSubscore,
    double? emoSubscore,
    required double confidence,
    required String dominantEmotion,
    required String modelId,
  }) async {
    await db.insert('dim_emotions', {
      'app_biosignal_id': appBiosignalId,
      'swip_score': swipScore,
      'phys_subscore': physSubscore,
      'emo_subscore': emoSubscore,
      'confidence': confidence,
      'dominant_emotion': dominantEmotion,
      'model_id': modelId,
    });
  }

  Future<void> updateLatestEmotionWithScore({
    required String appSessionId,
    required double swipScore,
    double? physSubscore,
    double? emoSubscore,
  }) async {
    // Find the latest biosignal for this session
    final biosignalResult = await db.rawQuery('''
      SELECT app_biosignal_id 
      FROM dim_App_biosignals 
      WHERE app_session_id = ? 
      ORDER BY timestamp DESC 
      LIMIT 1
    ''', [appSessionId]);

    if (biosignalResult.isEmpty) return;

    final appBiosignalId = biosignalResult.first['app_biosignal_id'] as String;

    // Update the emotion row for this biosignal
    await db.update(
      'dim_emotions',
      {
        'swip_score': swipScore,
        if (physSubscore != null) 'phys_subscore': physSubscore,
        if (emoSubscore != null) 'emo_subscore': emoSubscore,
      },
      where: 'app_biosignal_id = ?',
      whereArgs: [appBiosignalId],
    );
  }

  /// Get unsynced emotions for a session
  Future<List<Map<String, Object?>>> getUnsyncedForSession(
      String sessionId) async {
    return await db.rawQuery('''
      SELECT e.id, e.app_biosignal_id, e.swip_score, e.phys_subscore, e.emo_subscore,
             e.confidence, e.dominant_emotion, e.model_id
      FROM dim_emotions e
      INNER JOIN dim_App_biosignals b ON e.app_biosignal_id = b.app_biosignal_id
      WHERE b.app_session_id = ? AND (e.synced_to_cloud = 0 OR e.synced_to_cloud IS NULL)
      ORDER BY e.id ASC
    ''', [sessionId]);
  }

  /// Mark emotions as synced
  Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final placeholders = ids.map((_) => '?').join(',');
    await db.rawUpdate(
      '''
      UPDATE dim_emotions
      SET synced_to_cloud = 1, synced_at = ?
      WHERE id IN ($placeholders)
      ''',
      [now, ...ids],
    );
  }
}
