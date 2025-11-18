import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:swip/swip.dart';
import 'screens/diagnostics_screen.dart';
import 'storage/database.dart';
import 'storage/storage_service.dart';

void main() {
  // Catch and log Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    if (kDebugMode) {
      print('Flutter Error: ${details.exception}');
      print('Stack trace: ${details.stack}');
    }
  };

  // Catch async errors
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kDebugMode) {
      print('Platform Error: $error');
      print('Stack trace: $stack');
    }
    return true;
  };

  runApp(const SWIPExampleApp());
}

class SWIPExampleApp extends StatelessWidget {
  const SWIPExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SWIP Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const SWIPExampleHomePage(),
    );
  }
}

class SWIPExampleHomePage extends StatefulWidget {
  const SWIPExampleHomePage({super.key});

  @override
  State<SWIPExampleHomePage> createState() => _SWIPExampleHomePageState();
}

class _SWIPExampleHomePageState extends State<SWIPExampleHomePage> {
  late final SwipSdkManager _swipManager;
  final StorageService _storage = StorageService();
  final String _userId = 'example_user';
  bool _isInitialized = false;
  bool _isSessionActive = false;
  String? _activeSessionId;
  SwipSessionResults? _lastResults;
  String _status = 'Not initialized';

  // Emotion recognition
  EmotionPrediction? _currentEmotion;
  StreamSubscription<EmotionResult>? _emotionSubscription;

  // SWIP scores
  SwipScoreResult? _currentScore;
  StreamSubscription<SwipScoreResult>? _scoreSubscription;

  // Model information
  Map<String, dynamic>? _modelInfo;
  Map<String, dynamic>? _performanceMetrics;

  @override
  void initState() {
    super.initState();
    // Initialize SwipSdkManager with configuration
    _swipManager = SwipSdkManager(
      config: SwipSdkConfig(
        enableLogging: true,
      ),
    );
    _storage.attachToManager(_swipManager);
    // Warm up DB and ensure user exists - wrap in try-catch to prevent crashes
    try {
      AppDatabase.instance.database;
      _storage.initUser(userId: _userId);
    } catch (e) {
      setState(() {
        _status = 'Database initialization error: $e';
      });
    }
    // Initialize SWIP asynchronously
    _initializeSWIP();
  }

  @override
  void dispose() {
    _emotionSubscription?.cancel();
    _scoreSubscription?.cancel();
    _swipManager.dispose();
    super.dispose();
  }

  Future<void> _initializeSWIP() async {
    try {
      setState(() {
        _status = 'Initializing...';
      });

      // Add a small delay to ensure UI is ready
      await Future.delayed(const Duration(milliseconds: 100));

      await _swipManager.initialize();

      // Set up emotion recognition stream
      _emotionSubscription = _swipManager.emotionStream.listen((emotionResult) {
        setState(() {
          // Convert EmotionResult to EmotionPrediction for UI compatibility
          _currentEmotion = EmotionPrediction.fromEmotionResult(emotionResult);
        });
      });

      // Set up SWIP score stream
      _scoreSubscription = _swipManager.scoreStream.listen((scoreResult) {
        setState(() {
          _currentScore = scoreResult;
        });
      });

      // Model information is managed internally by synheart-emotion package
      _modelInfo = {
        'modelId': 'extratrees_wrist_all_v1_0',
        'version': '1.0',
        'type': 'ONNX',
      };
      _performanceMetrics = {
        'accuracy': 0.78,
        'f1_score': 0.75,
        'dataset': 'WESAD',
      };

      setState(() {
        _isInitialized = true;
        _status = 'Ready';
      });
    } catch (e) {
      setState(() {
        _status = 'Initialization failed: $e';
      });
    }
  }

  Future<void> _startSession() async {
    if (!_isInitialized) return;

    try {
      setState(() {
        _status = 'Starting session...';
      });

      _activeSessionId = await _swipManager.startSession(
        appId: 'swip_example_app',
        metadata: {
          'duration_minutes': 5,
          'type': 'baseline',
          'platform': 'flutter',
          'environment': 'indoor',
        },
      );
      // Device info will be captured from metrics streams
      await _storage.startSession(
        userId: _userId,
        appId: 'swip_example_app',
        deviceId: null,
        deviceSource: null,
      );

      // Real-time data is automatically collected from synheart_wear
      // No simulation needed - the SDK reads from actual wearable devices

      setState(() {
        _isSessionActive = true;
        _status = 'Session active: $_activeSessionId';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to start session: $e';
      });
    }
  }

  Future<void> _endSession() async {
    if (!_isSessionActive || _activeSessionId == null) return;

    try {
      setState(() {
        _status = 'Ending session...';
      });

      final results = await _swipManager.stopSession();
      final avg = results.scores.isNotEmpty
          ? results.scores.map((e) => e.swipScore).reduce((a, b) => a + b) /
              results.scores.length
          : null;
      await _storage.endSession(averageScore: avg);

      setState(() {
        _isSessionActive = false;
        _activeSessionId = null;
        _lastResults = results;
        _status = 'Session completed';
      });
    } catch (e) {
      setState(() {
        _status = 'Failed to end session: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SWIP Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.storage_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      DiagnosticsScreen(storageService: _storage),
                ),
              );
            },
            tooltip: 'Database Diagnostics',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Status',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 8,
                            color:
                                _isInitialized ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _status,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(
                          _isInitialized
                              ? Icons.check_circle_rounded
                              : Icons.cancel_rounded,
                          color: _isInitialized ? Colors.green : Colors.grey,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isInitialized ? 'System Ready' : 'Not Initialized',
                          style: TextStyle(
                            color: _isInitialized
                                ? Colors.green[700]
                                : Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    if (_isSessionActive) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green[200]!),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.play_circle_rounded,
                                color: Colors.green[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Session Active',
                                style: TextStyle(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.privacy_tip_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Data Storage',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Local Storage',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _storage.consentEnabled
                                    ? 'Data is being saved locally'
                                    : 'No data is being saved',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _storage.consentEnabled,
                          onChanged: (value) async {
                            await _storage.setConsent(
                              userId: _userId,
                              enabled: value,
                            );
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.cloud_sync_rounded,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Cloud Sync',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Sync to Cloud',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _storage.cloudSyncConsentEnabled
                                            ? 'Data will be synced to cloud'
                                            : 'Data will not be synced',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: _storage.cloudSyncConsentEnabled,
                                  onChanged: (value) async {
                                    await _storage.setCloudSyncConsent(
                                      userId: _userId,
                                      enabled: value,
                                    );
                                    setState(() {});
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.control_camera_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Session Controls',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isInitialized && !_isSessionActive
                                ? _startSession
                                : null,
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Start Session'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isSessionActive ? _endSession : null,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('End Session'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // SWIP Score Display
            if (_currentScore != null) ...[
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _getScoreColor(_currentScore!.swipScore)
                            .withOpacity(0.1),
                        Colors.white,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.favorite_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'SWIP Wellness Score',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(32),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color:
                                      _getScoreColor(_currentScore!.swipScore)
                                          .withOpacity(0.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _getScoreColor(
                                              _currentScore!.swipScore)
                                          .withOpacity(0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _currentScore!.swipScore.toStringAsFixed(0),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        color: _getScoreColor(
                                            _currentScore!.swipScore),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 48,
                                      ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _getScoreInterpretation(
                                    _currentScore!.swipScore),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      color: _getScoreColor(
                                          _currentScore!.swipScore),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Confidence: ${(_currentScore!.confidence * 100).toStringAsFixed(1)}%',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            // Emotion Recognition Display
            ...[
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _currentEmotion != null
                            ? _getEmotionColor(_getEmotionClassFromString(
                                    _currentEmotion!.emotion))
                                .withOpacity(0.1)
                            : Colors.blue.withOpacity(0.05),
                        Colors.white,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.psychology_rounded,
                              color: Theme.of(context).colorScheme.primary,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Real-time Emotion Recognition',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        if (_currentEmotion != null) ...[
                          Center(
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(32),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _getEmotionColor(
                                            _getEmotionClassFromString(
                                                _currentEmotion!.emotion))
                                        .withOpacity(0.2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _getEmotionColor(
                                                _getEmotionClassFromString(
                                                    _currentEmotion!.emotion))
                                            .withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    _getEmotionIcon(_getEmotionClassFromString(
                                        _currentEmotion!.emotion)),
                                    size: 80,
                                    color: _getEmotionColor(
                                        _getEmotionClassFromString(
                                            _currentEmotion!.emotion)),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  _currentEmotion!.emotion,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineLarge
                                      ?.copyWith(
                                        color: _getEmotionColor(
                                            _getEmotionClassFromString(
                                                _currentEmotion!.emotion)),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 36,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _getEmotionColor(
                                            _getEmotionClassFromString(
                                                _currentEmotion!.emotion))
                                        .withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${(_currentEmotion!.confidence * 100).toStringAsFixed(1)}% Confidence',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: _getEmotionColor(
                                              _getEmotionClassFromString(
                                                  _currentEmotion!.emotion)),
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 32),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey[300]!),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Emotion Probabilities',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[700],
                                      ),
                                ),
                                const SizedBox(height: 12),
                                ..._currentEmotion!.probabilities.entries
                                    .map((entry) {
                                  final emotionLabel = entry.key;
                                  final probability = entry.value;
                                  final emotion =
                                      _getEmotionClassFromString(emotionLabel);

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 6.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(
                                                  _getEmotionIcon(emotion),
                                                  size: 20,
                                                  color:
                                                      _getEmotionColor(emotion),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  emotionLabel,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w500,
                                                    color: Colors.grey[800],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            Text(
                                              '${(probability * 100).toStringAsFixed(1)}%',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color:
                                                    _getEmotionColor(emotion),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: probability,
                                            minHeight: 8,
                                            backgroundColor: Colors.grey[300],
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                              _getEmotionColor(emotion),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ] else ...[
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32.0),
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.sentiment_neutral_rounded,
                                    size: 64,
                                    color: Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No emotion data yet',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Colors.grey[600],
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Start a session to see real-time emotion recognition',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey[500]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (_lastResults != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Last Session Results',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      Builder(
                        builder: (context) {
                          final summary = _lastResults!.getSummary();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildResultRow('Average SWIP Score',
                                  '${summary['average_swip_score']?.toStringAsFixed(1) ?? 'N/A'}'),
                              _buildResultRow(
                                  'Dominant Emotion',
                                  summary['dominant_emotion']?.toString() ??
                                      'Unknown'),
                              _buildResultRow('Score Count',
                                  '${summary['score_count'] ?? 0}'),
                              _buildResultRow('Emotion Count',
                                  '${summary['emotion_count'] ?? 0}'),
                              _buildResultRow('Duration',
                                  '${summary['duration_seconds'] ?? 0} seconds'),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
            // Model Information Display
            if (_modelInfo != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Emotion Recognition Model',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      _buildInfoRow(
                          'Model ID', _modelInfo!['modelId'] ?? 'Unknown'),
                      _buildInfoRow(
                          'Version', _modelInfo!['version'] ?? 'Unknown'),
                      _buildInfoRow('Type', _modelInfo!['type'] ?? 'Unknown'),
                      if (_performanceMetrics != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Performance Metrics',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        _buildInfoRow('Accuracy',
                            '${(_performanceMetrics!['accuracy'] ?? 0.0).toStringAsFixed(2)}'),
                        _buildInfoRow('F1 Score',
                            '${(_performanceMetrics!['f1_score'] ?? 0.0).toStringAsFixed(2)}'),
                        _buildInfoRow('Dataset',
                            _performanceMetrics!['dataset'] ?? 'Unknown'),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.blue;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  String _getScoreInterpretation(double score) {
    if (score >= 80) return 'Positive';
    if (score >= 60) return 'Neutral';
    if (score >= 40) return 'Mild Stress';
    return 'Negative';
  }

  EmotionClass _getEmotionClassFromString(String emotionString) {
    final lower = emotionString.toLowerCase();
    if (lower.contains('calm')) return EmotionClass.calm;
    if (lower.contains('stress')) return EmotionClass.stressed;
    if (lower.contains('amus')) return EmotionClass.amused;
    return EmotionClass.neutral;
  }

  IconData _getEmotionIcon(EmotionClass emotion) {
    switch (emotion) {
      case EmotionClass.calm:
        return Icons.spa_rounded;
      case EmotionClass.stressed:
        return Icons.warning_rounded;
      case EmotionClass.amused:
        return Icons.sentiment_very_satisfied_rounded;
      case EmotionClass.focused:
        return Icons.psychology_rounded;
      case EmotionClass.neutral:
        return Icons.sentiment_neutral;
    }
  }

  Color _getEmotionColor(EmotionClass emotion) {
    switch (emotion) {
      case EmotionClass.calm:
        return Colors.green;
      case EmotionClass.stressed:
        return Colors.red;
      case EmotionClass.amused:
        return Colors.amber;
      case EmotionClass.focused:
        return Colors.blue;
      case EmotionClass.neutral:
        return Colors.grey;
    }
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
