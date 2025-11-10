import 'dart:async';

import 'package:swip/swip.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io' show Platform;
import 'package:uuid/uuid.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'database.dart';
import 'repos/apps_repo.dart';
import 'repos/biosignals_repo.dart';
import 'repos/consents_repo.dart';
import 'repos/devices_repo.dart';
import 'repos/emotions_repo.dart';
import 'repos/sessions_repo.dart';
import 'repos/users_repo.dart';
import 'sync/sync_service.dart';

class StorageService {
  final _uuid = const Uuid();

  String? _currentSessionId;
  StreamSubscription? _emotionSub;
  StreamSubscription? _scoreSub;
  bool _consentEnabled = false;
  bool _cloudSyncConsentEnabled = false;

  SyncService? _syncService;

  Future<void> initUser({required String userId}) async {
    final db = await AppDatabase.instance.database;
    final users = UsersRepo(db);
    await users.upsertUser(
        userId: userId, createdAt: DateTime.now().toUtc().toIso8601String());

    // Check existing consents
    final consents = ConsentsRepo(db);
    final localStatus =
        await consents.getConsentStatus(userId: userId, type: 'local_storage');
    _consentEnabled = localStatus == 'active';

    final cloudStatus =
        await consents.getConsentStatus(userId: userId, type: 'cloud_sync');
    _cloudSyncConsentEnabled = cloudStatus == 'active';

    // Initialize sync service
    _syncService = SyncService(db);
    await _syncService!.initialize();
  }

  Future<void> setConsent(
      {required String userId, required bool enabled}) async {
    _consentEnabled = enabled;
    final db = await AppDatabase.instance.database;
    final consents = ConsentsRepo(db);
    await consents.upsertConsent(
      userId: userId,
      type: 'local_storage',
      status: enabled ? 'active' : 'revoked',
    );
  }

  Future<void> setCloudSyncConsent(
      {required String userId, required bool enabled}) async {
    _cloudSyncConsentEnabled = enabled;
    final db = await AppDatabase.instance.database;
    final consents = ConsentsRepo(db);
    await consents.upsertConsent(
      userId: userId,
      type: 'cloud_sync',
      status: enabled ? 'active' : 'revoked',
    );
  }

  bool get consentEnabled => _consentEnabled;
  bool get cloudSyncConsentEnabled => _cloudSyncConsentEnabled;

  SyncService? get syncService => _syncService;

  Future<void> startSession({
    required String userId,
    required String appId,
    String? deviceId,
    String? deviceSource,
  }) async {
    if (!_consentEnabled) return;

    _currentSessionId = _uuid.v4();
    final db = await AppDatabase.instance.database;

    // Resolve real app id from package name
    final pkg = await PackageInfo.fromPlatform();
    final resolvedAppId = pkg.packageName;

    // Ensure app exists
    final apps = AppsRepo(db);
    await apps.upsertApp(
      appId: resolvedAppId,
      appName: pkg.appName,
      appVersion: pkg.version,
      category: 'Wellness',
    );

    // Ensure phone device exists (track phone OS version, not watch)
    final devices = DevicesRepo(db);
    final phoneInfo = await _getPhoneDeviceInfo();
    final phoneDeviceId =
        'phone_${phoneInfo['platform']}_${phoneInfo['model']}';
    await devices.upsertDevice(
      deviceId: phoneDeviceId,
      platform: phoneInfo['platform'],
      model: phoneInfo['model'],
      osVersion: phoneInfo['osVersion'],
    );

    // Temporary: initialize a default watch device entry
    await devices.upsertDevice(
      deviceId: 'watch_apple_ultra2',
      platform: 'watchOS',
      model: 'Apple Watch Ultra 2',
      osVersion: "IOS 26",
    );

    final sessions = SessionsRepo(db);
    await sessions.insertSession(
      appSessionId: _currentSessionId!,
      userId: userId,
      deviceId: phoneDeviceId,
      startedAt: DateTime.now().toUtc().toIso8601String(),
      appId: resolvedAppId,
    );
  }

  Future<Map<String, String>> _getPhoneDeviceInfo() async {
    final info = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final data = await info.iosInfo;
      final model = data.utsname.machine;
      return {
        'platform': 'iOS',
        'model': model,
        'osVersion': data.systemVersion,
      };
    }
    if (Platform.isAndroid) {
      final data = await info.androidInfo;
      return {
        'platform': 'Android',
        'model': data.model,
        'osVersion': data.version.release,
      };
    }
    return {
      'platform': Platform.operatingSystem,
      'model': 'unknown',
      'osVersion': Platform.operatingSystemVersion,
    };
  }

  Future<void> endSession({double? averageScore}) async {
    if (_currentSessionId == null) return;
    final db = await AppDatabase.instance.database;
    final sessions = SessionsRepo(db);
    await sessions.endSession(
      appSessionId: _currentSessionId!,
      endedAt: DateTime.now().toUtc().toIso8601String(),
      avgSwipScore: averageScore,
    );
    _currentSessionId = null;
  }

  void attachToManager(SwipSdkManager manager) async {
    // Emotions → persist to dim_emotions and a minimal biosignal row
    _emotionSub?.cancel();
    _emotionSub = manager.emotionStream.listen((emotion) async {
      if (_currentSessionId == null || !_consentEnabled) return;
      final db = await AppDatabase.instance.database;
      final bios = BiosignalsRepo(db);
      final emos = EmotionsRepo(db);

      final appBiosignalId = _uuid.v4();
      final ts = emotion.timestamp.toUtc().toIso8601String();

      // Minimal biosignal: heart_rate and HRV from features if available
      final hr = emotion.features['hr_mean'];
      final sdnn = emotion.features['sdnn'];
      final rmssd = emotion.features['rmssd'];
      await bios.insertBiosignal(
        appBiosignalId: appBiosignalId,
        appSessionId: _currentSessionId!,
        timestamp: ts,
        heartRate: hr,
        hrvSdnn: sdnn,
        hrvRmssd: rmssd,
      );

      // Emotion
      await emos.insertEmotion(
        appBiosignalId: appBiosignalId,
        swipScore: null, // will be backfilled when score arrives
        physSubscore: null,
        emoSubscore: null,
        confidence: emotion.confidence,
        dominantEmotion: emotion.emotion,
        modelId: (emotion.model['id'] ?? manager.config.emotionConfig.modelId)
            .toString(),
      );
    });

    // Scores → link to latest emotion row
    _scoreSub?.cancel();
    _scoreSub = manager.scoreStream.listen((score) async {
      if (_currentSessionId == null || !_consentEnabled) return;
      final db = await AppDatabase.instance.database;
      final emos = EmotionsRepo(db);

      // Link score to the most recent emotion for this session
      await emos.updateLatestEmotionWithScore(
        appSessionId: _currentSessionId!,
        swipScore: score.swipScore,
        // Note: physSubscore and emoSubscore not available in SwipScoreResult currently
      );
    });
  }

  Future<void> dispose() async {
    await _emotionSub?.cancel();
    await _scoreSub?.cancel();
  }
}
