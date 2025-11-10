import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../repos/sessions_repo.dart';
import '../repos/devices_repo.dart';
import '../repos/biosignals_repo.dart';
import '../repos/emotions_repo.dart';
import 'api_client.dart';
import 'api_key_storage.dart';
import 'data_transformer.dart';
import 'rate_limiter.dart';
import 'logging.dart';
import 'models/device_payload.dart';
import 'models/emotion_record.dart';

class SyncService {
  final Database db;
  final ApiKeyStorage _apiKeyStorage;
  final RateLimiter _rateLimiter;
  SwipApiClient? _apiClient;

  // Expose for UI access
  ApiKeyStorage get apiKeyStorage => _apiKeyStorage;

  SyncService(this.db)
      : _apiKeyStorage = ApiKeyStorage(),
        _rateLimiter = RateLimiter();

  /// Initialize API client with stored key
  Future<void> initialize() async {
    logSync('info', 'Initializing SyncService');
    final apiKey = await _apiKeyStorage.getApiKey();
    if (apiKey != null) {
      _apiClient = SwipApiClient(apiKey: apiKey);
      logSync('debug', 'API client initialized from stored key');
    } else {
      logSync('warn', 'No API key configured');
    }
  }

  /// Set API key and initialize client
  Future<void> setApiKey(String apiKey) async {
    await _apiKeyStorage.setApiKey(apiKey);
    _apiClient = SwipApiClient(apiKey: apiKey);
    logSync('info', 'API key set and client initialized');
  }

  /// Check if API key is configured
  Future<bool> hasApiKey() async {
    return await _apiKeyStorage.hasApiKey();
  }

  /// Sync a single session
  Future<SyncResult> syncSession(String sessionId) async {
    if (_apiClient == null) {
      logSync('error', 'Sync aborted: API key not configured',
          extra: {'sessionId': sessionId});
      return SyncResult(
        success: false,
        error: 'API key not configured',
        isRetryable: false,
      );
    }

    final sessionsRepo = SessionsRepo(db);
    final transformer = DataTransformer(db);

    try {
      // Build app session record
      final record = await transformer.buildSessionRecord(sessionId);
      if (record == null) {
        logSync('warn', 'No session record produced',
            extra: {'sessionId': sessionId});
        return SyncResult(
            success: false, error: 'Session not found', isRetryable: false);
      }
      logSync('debug', 'Prepared app session record', extra: {
        'sessionId': record.appSessionId,
        'userId': record.userId,
        'deviceId': record.deviceId,
        'startedAt': record.startedAt,
        'endedAt': record.endedAt,
      });

      // Check rate limit
      final wait = _rateLimiter.timeUntilNextRequest();
      if (wait != null && wait.inMilliseconds > 0) {
        logSync('info', 'Rate limit wait', extra: {'ms': wait.inMilliseconds});
      }
      await _rateLimiter.waitIfNeeded();

      // Submit app session to API
      await _apiClient!.submitAppSession(record);
      _rateLimiter.recordRequest();
      logSync('info', 'App session submitted', extra: {
        'sessionId': sessionId,
      });

      // Sync biosignals then emotions for this session
      await _syncBiosignalsForSession(sessionId);
      await _syncEmotionsForSession(sessionId);

      {
        // Mark as synced
        final now = DateTime.now().toUtc().toIso8601String();
        await sessionsRepo.markSynced(
          appSessionId: sessionId,
          syncedAt: now,
        );

        return SyncResult(
          success: true,
          swipScore: null,
        );
      }
    } on ApiException catch (e) {
      // Update sync attempt
      final now = DateTime.now().toUtc().toIso8601String();
      await sessionsRepo.updateSyncAttempt(
        appSessionId: sessionId,
        lastSyncAttempt: now,
        error: e.message,
      );
      logSync('error', 'API exception during sync', extra: {
        'sessionId': sessionId,
        'status': e.statusCode,
        'retryable': e.isRetryable,
        'retryAfterMs': e.retryAfter?.inMilliseconds,
        'message': e.message,
      });

      return SyncResult(
        success: false,
        error: e.message,
        isRetryable: e.isRetryable,
        retryAfter: e.retryAfter,
      );
    } catch (e) {
      // Update sync attempt
      final now = DateTime.now().toUtc().toIso8601String();
      await sessionsRepo.updateSyncAttempt(
        appSessionId: sessionId,
        lastSyncAttempt: now,
        error: e.toString(),
      );
      logSync('error', 'Unexpected error during sync', extra: {
        'sessionId': sessionId,
        'error': e.toString(),
      });

      return SyncResult(
        success: false,
        error: e.toString(),
        isRetryable: true, // Assume retryable for unknown errors
      );
    }
  }

  /// Sync all unsynced sessions
  Future<SyncSummary> syncAllSessions({
    int maxRetries = 3,
    Function(String sessionId, SyncResult result)? onSessionComplete,
  }) async {
    if (_apiClient == null) {
      return SyncSummary(
        total: 0,
        successful: 0,
        failed: 0,
        error: 'API key not configured',
      );
    }

    // 1) Register devices first; abort if any fail
    final devicesOk = await _registerDevices();
    if (!devicesOk) {
      logSync('error', 'Aborting session sync: device registration failed');
      return SyncSummary(
        total: 0,
        successful: 0,
        failed: 0,
        error: 'Device registration failed',
      );
    }

    final sessionsRepo = SessionsRepo(db);
    final unsynced = await sessionsRepo.getUnsyncedSessions();
    logSync('info', 'Starting batch sync', extra: {'count': unsynced.length});

    int successful = 0;
    int failed = 0;
    final errors = <String>[];

    for (final session in unsynced) {
      final sessionId = session['app_session_id'] as String;
      // final attempts = session['sync_attempts'] as int? ?? 0;

      // // Skip if too many attempts
      // if (attempts >= maxRetries) {
      //   failed++;
      //   logSync('warn', 'Skipping session due to max retries reached', extra: {
      //     'sessionId': sessionId,
      //     'attempts': attempts,
      //     'maxRetries': maxRetries,
      //   });
      //   continue;
      // }

      final result = await syncSession(sessionId);
      logSync(result.success ? 'info' : 'error', 'Session sync result', extra: {
        'sessionId': sessionId,
        'success': result.success,
        'error': result.error,
        'retryable': result.isRetryable,
        'retryAfterMs': result.retryAfter?.inMilliseconds,
      });

      if (result.success) {
        successful++;
      } else {
        failed++;
        if (result.error != null) {
          errors.add('$sessionId: ${result.error}');
        }
      }

      // Callback for progress
      onSessionComplete?.call(sessionId, result);

      // Handle rate limiting or retry delays
      if (result.retryAfter != null) {
        await Future.delayed(result.retryAfter!);
      }
    }

    // 2) Sync biosignals for sessions that have unsynced biosignals
    await _syncPendingBiosignals();

    // 3) Sync emotions for sessions that have unsynced emotions
    await _syncPendingEmotions();

    final summary = SyncSummary(
      total: unsynced.length,
      successful: successful,
      failed: failed,
      errors: errors.isEmpty ? null : errors,
    );
    logSync('info', 'Batch sync complete', extra: {
      'total': summary.total,
      'successful': summary.successful,
      'failed': summary.failed,
      if (summary.errors != null) 'errors': summary.errors,
    });
    return summary;
  }

  /// Get sync statistics
  Future<Map<String, dynamic>> getSyncStats() async {
    final sessionsRepo = SessionsRepo(db);
    return await sessionsRepo.getSyncStats();
  }

  /// Register any unregistered devices from the local DB
  Future<bool> _registerDevices() async {
    if (_apiClient == null) return false;
    final devicesRepo = DevicesRepo(db);
    final devices = await devicesRepo.getUnregisteredDevices();
    if (devices.isEmpty) return true;

    logSync('info', 'Registering devices', extra: {'count': devices.length});

    var allOk = true;
    for (final d in devices) {
      final deviceId = (d['device_id'] as String);
      final platform = (d['platform'] as String?) ?? 'unknown';
      final model = d['model'] as String?;
      final osVersion = (d['os_version'] as String?) ?? 'unknown';

      // Prepare payload - phone device provides platform/osVersion, watch model if known
      final payload = DevicePayload(
        deviceId: deviceId,
        platform: platform,
        mobileOsVersion: osVersion,
        watchModel: model?.contains('Apple Watch') == true ? model : null,
      );

      try {
        await _apiClient!.registerDevice(payload);
        await devicesRepo.markDeviceRegistered(deviceId: deviceId);
        logSync('info', 'Device registered', extra: {'deviceId': deviceId});
      } catch (e) {
        await devicesRepo.recordRegisterFailure(
          deviceId: deviceId,
          error: e.toString(),
        );
        logSync('error', 'Device registration failed',
            extra: {'deviceId': deviceId, 'error': e.toString()});
        allOk = false;
      }
    }
    return allOk;
  }

  /// Sync biosignals for a session
  Future<void> _syncBiosignalsForSession(String sessionId) async {
    if (_apiClient == null) return;

    final transformer = DataTransformer(db);
    final biosignalsRepo = BiosignalsRepo(db);

    // Build biosignal records
    final biosignals = await transformer.buildBiosignalRecords(sessionId);
    if (biosignals.isEmpty) {
      logSync('debug', 'No biosignals to sync for session',
          extra: {'sessionId': sessionId});
      return;
    }

    logSync('info', 'Syncing biosignals', extra: {
      'sessionId': sessionId,
      'count': biosignals.length,
    });

    try {
      // Check rate limit
      await _rateLimiter.waitIfNeeded();

      // Submit biosignals
      await _apiClient!.submitBiosignals(biosignals);
      _rateLimiter.recordRequest();

      // Mark as synced
      final biosignalIds = biosignals.map((b) => b.appBiosignalId).toList();
      await biosignalsRepo.markBiosignalsSynced(biosignalIds);

      logSync('info', 'Biosignals synced successfully', extra: {
        'sessionId': sessionId,
        'count': biosignals.length,
      });

      // After biosignals, sync emotions for this session
      await _syncEmotionsForSession(sessionId);
    } catch (e) {
      logSync('error', 'Biosignal sync failed', extra: {
        'sessionId': sessionId,
        'error': e.toString(),
      });
      // Don't throw - biosignal sync failure shouldn't fail session sync
    }
  }

  /// Sync biosignals for all sessions that have unsynced biosignals
  Future<void> _syncPendingBiosignals() async {
    if (_apiClient == null) return;

    final sessionsRepo = SessionsRepo(db);
    final sessionsWithUnsyncedBiosignals =
        await sessionsRepo.getSessionsWithUnsyncedBiosignals();

    if (sessionsWithUnsyncedBiosignals.isEmpty) {
      logSync('debug', 'No sessions with unsynced biosignals');
      return;
    }

    logSync('info', 'Syncing pending biosignals',
        extra: {'sessionCount': sessionsWithUnsyncedBiosignals.length});

    for (final sessionId in sessionsWithUnsyncedBiosignals) {
      await _syncBiosignalsForSession(sessionId);
      await _syncEmotionsForSession(sessionId);
    }

    logSync('info', 'Pending biosignals sync complete');
  }

  /// Sync emotions for a given session
  Future<void> _syncEmotionsForSession(String sessionId) async {
    if (_apiClient == null) return;

    final emotionsRepo = EmotionsRepo(db);
    final rows = await emotionsRepo.getUnsyncedForSession(sessionId);
    if (rows.isEmpty) {
      logSync('debug', 'No emotions to sync for session',
          extra: {'sessionId': sessionId});
      return;
    }

    // Filter out emotions without swip_score (API requires it)
    final rowsWithScores = rows.where((r) => r['swip_score'] != null).toList();
    
    if (rowsWithScores.isEmpty) {
      logSync('debug', 'No emotions with scores to sync for session',
          extra: {
            'sessionId': sessionId,
            'totalEmotions': rows.length,
          });
      return;
    }

    if (rowsWithScores.length < rows.length) {
      logSync('debug', 'Filtered out emotions without scores',
          extra: {
            'sessionId': sessionId,
            'totalEmotions': rows.length,
            'emotionsWithScores': rowsWithScores.length,
            'filteredOut': rows.length - rowsWithScores.length,
          });
    }

    final records = rowsWithScores.map((r) {
      logSync('debug', 'Prepared emotion record', extra: {
        'id': r['id'],
        'appBiosignalId': r['app_biosignal_id'],
        'swipScore': r['swip_score'],
        'physSubscore': r['phys_subscore'],
        'emoSubscore': r['emo_subscore'],
        'confidence': r['confidence'],
        'dominantEmotion': r['dominant_emotion'],
        'modelId': r['model_id'],
      });
      return EmotionRecord(
        id: r['id'] as int,
        appBiosignalId: r['app_biosignal_id'] as String,
        swipScore: (r['swip_score'] as num?)?.toDouble(),
        physSubscore: (r['phys_subscore'] as num?)?.toDouble(),
        emoSubscore: (r['emo_subscore'] as num?)?.toDouble(),
        confidence: (r['confidence'] as num).toDouble(),
        dominantEmotion: r['dominant_emotion'] as String,
        modelId: r['model_id'] as String,
      );
    }).toList();

    logSync('info', 'Syncing emotions', extra: {
      'sessionId': sessionId,
      'count': records.length,
    });

    try {
      await _rateLimiter.waitIfNeeded();
      await _apiClient!.submitEmotions(records);
      _rateLimiter.recordRequest();

      await emotionsRepo.markSynced(records.map((e) => e.id).toList());
      logSync('info', 'Emotions synced successfully', extra: {
        'sessionId': sessionId,
        'count': records.length,
      });
    } catch (e) {
      logSync('error', 'Emotion sync failed', extra: {
        'sessionId': sessionId,
        'error': e.toString(),
      });
    }
  }

  /// Sync emotions across all sessions with pending emotions
  Future<void> _syncPendingEmotions() async {
    if (_apiClient == null) return;

    final sessionsRepo = SessionsRepo(db);
    final sessions = await sessionsRepo.getSessionsWithUnsyncedEmotions();
    if (sessions.isEmpty) {
      logSync('debug', 'No sessions with unsynced emotions');
      return;
    }

    logSync('info', 'Syncing pending emotions', extra: {
      'sessionCount': sessions.length,
    });

    for (final sessionId in sessions) {
      await _syncEmotionsForSession(sessionId);
    }

    logSync('info', 'Pending emotions sync complete');
  }
}

/// Result of a sync operation
class SyncResult {
  final bool success;
  final int? swipScore;
  final String? error;
  final bool isRetryable;
  final Duration? retryAfter;

  SyncResult({
    required this.success,
    this.swipScore,
    this.error,
    this.isRetryable = false,
    this.retryAfter,
  });
}

/// Summary of a batch sync operation
class SyncSummary {
  final int total;
  final int successful;
  final int failed;
  final List<String>? errors;
  final String? error;

  SyncSummary({
    required this.total,
    required this.successful,
    required this.failed,
    this.errors,
    this.error,
  });
}
