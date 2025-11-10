import 'dart:async';
import 'dart:math' as math;
import 'package:swip_core/swip.dart';
import 'package:synheart_wear/synheart_wear.dart';
import 'package:synheart_emotion/synheart_emotion.dart';
import 'models.dart';
import 'errors.dart';

/// SWIP SDK Manager - Main entry point for the SDK
///
/// Integrates:
/// - synheart_wear: Reads HR, HRV, motion data
/// - synheart_emotion: Runs emotion inference models
/// - swip_core: Computes SWIP Score
class SwipSdkManager {
  // Core components
  final SynheartWear _wear;
  EmotionEngine? _emotionEngine;
  final SwipEngine _swipEngine;

  // State management
  bool _initialized = false;
  bool _isWearInitialized = false;
  bool _isRunning = false;
  String? _activeSessionId;

  // Stream controllers
  final _scoreStreamController = StreamController<SwipScoreResult>.broadcast();
  final _emotionStreamController = StreamController<EmotionResult>.broadcast();

  // Subscriptions
  StreamSubscription<WearMetrics>? _wearSubscription;
  StreamSubscription<WearMetrics>? _hrvSubscription;
  Timer? _emotionProcessor;

  // Configuration
  final SwipSdkConfig config;

  // Session data
  final List<SwipScoreResult> _sessionScores = [];
  final List<EmotionResult> _sessionEmotions = [];

  SwipSdkManager({
    required this.config,
    SynheartWear? wear,
    EmotionEngine? emotionEngine,
    SwipEngine? swipEngine,
  })  : _wear = wear ?? SynheartWear(),
        _emotionEngine = emotionEngine,
        _swipEngine = swipEngine ??
            SwipEngineFactory.createDefault(
              config: config.swipConfig,
            );

  /// Initialize the SDK
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    try {
      // Initialize emotion engine if not provided
      if (_emotionEngine == null) {
        try {
          final onnxModel = await OnnxEmotionModel.loadFromAsset(
            modelAssetPath: 'assets/ml/extratrees_wrist_all_v1_0.onnx',
            metaAssetPath: 'assets/ml/extratrees_wrist_all_v1_0.meta.json',
          );

          // Update emotion config with correct model ID
          final emotionConfig = EmotionConfig(
            modelId: 'extratrees_wrist_all_v1_0',
            window: config.emotionConfig.window,
            step: config.emotionConfig.step,
            minRrCount: config.emotionConfig.minRrCount,
            returnAllProbas: config.emotionConfig.returnAllProbas,
            hrBaseline: config.emotionConfig.hrBaseline,
            priors: config.emotionConfig.priors,
          );

          _emotionEngine = EmotionEngine.fromPretrained(
            emotionConfig,
            model: onnxModel,
          );
        } catch (e) {
          throw InitializationError('Failed to load emotion model: $e');
        }
      }

      // Initialize wearable SDK
      await _wear.initialize();
      _isWearInitialized = true;

      // Request permissions for health data
      await _wear.requestPermissions();

      _initialized = true;
    } catch (e) {
      throw InitializationError('Failed to initialize SWIP SDK: $e');
    }
  }

  /// Start a session for an app
  Future<String> startSession({
    required String appId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!_initialized) {
      throw InvalidConfigurationError('SWIP SDK not initialized');
    }

    if (_isRunning) {
      throw SessionError('Session already in progress');
    }

    // Generate session ID
    _activeSessionId = '${DateTime.now().millisecondsSinceEpoch}_$appId';

    try {
      // Initialize wearable SDK if not already initialized
      if (!_isWearInitialized) {
        await _wear.initialize();
      }

      // Subscribe to HR stream - this provides HR data regularly and may include HRV
      // We use this as the primary source since it emits more frequently
      _wearSubscription =
          _wear.streamHR(interval: const Duration(seconds: 2)).listen(
        (metrics) {
          // Handle HR stream metrics - this is the primary data source
          _handleWearMetrics(metrics);
        },
        onError: (error) {
          // Error handling for HR stream
        },
        onDone: () {
          // HR stream closed
        },
      );

      // Subscribe to HRV stream for HRV data when available
      // This supplements the HR stream with HRV-specific data
      _hrvSubscription =
          _wear.streamHRV(windowSize: const Duration(seconds: 5)).listen(
        (metrics) {
          // Also handle HRV stream metrics - they may have better HRV data
          _handleWearMetrics(metrics);
        },
        onError: (error) {
          // Error handling for HRV stream
        },
        onDone: () {
          // HRV stream closed
        },
      );

      // Start emotion processing timer (1 Hz)
      _emotionProcessor = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _processEmotionUpdates(),
      );

      _isRunning = true;

      return _activeSessionId!;
    } catch (e) {
      await stopSession();
      throw SessionError('Failed to start session: $e');
    }
  }

  /// Stop the current session
  Future<SwipSessionResults> stopSession() async {
    if (!_isRunning || _activeSessionId == null) {
      throw SessionError('No active session');
    }

    try {
      // Cancel subscriptions
      await _wearSubscription?.cancel();
      _wearSubscription = null;
      await _hrvSubscription?.cancel();
      _hrvSubscription = null;

      // Stop timer
      _emotionProcessor?.cancel();
      _emotionProcessor = null;

      // Metrics subscription will stop automatically when disposed

      // Create session results
      final results = SwipSessionResults(
        sessionId: _activeSessionId!,
        scores: List.from(_sessionScores),
        emotions: List.from(_sessionEmotions),
        startTime: _sessionScores.isNotEmpty
            ? _sessionScores.first.timestamp
            : DateTime.now(),
        endTime: _sessionScores.isNotEmpty
            ? _sessionScores.last.timestamp
            : DateTime.now(),
      );

      // Clear session data
      _clearSession();

      _isRunning = false;

      return results;
    } catch (e) {
      throw SessionError('Failed to stop session: $e');
    }
  }

  /// Handle incoming wearable metrics from either HR or HRV stream
  void _handleWearMetrics(WearMetrics metrics) {
    // Extract HR and HRV
    final hr = metrics.getMetric(MetricType.hr)?.toDouble();
    final hrvSdnn = metrics.getMetric(MetricType.hrvSdnn)?.toDouble();
    final hrvRmssd = metrics.getMetric(MetricType.hrvRmssd)?.toDouble();
    final motion = metrics.metrics['motion']?.toDouble() ?? 0.0;

    if (hr == null) {
      return;
    }

    // Use real RR intervals if available, otherwise generate synthetic ones
    List<double> rrIntervals;
    if (metrics.rrMs != null && metrics.rrMs!.isNotEmpty) {
      rrIntervals = metrics.rrMs!;
    } else {
      // Generate synthetic RR intervals from HR and HRV data (or just HR with default variability)
      rrIntervals = _generateRRIntervalsFromHRV(
        hr: hr,
        hrvSdnn: hrvSdnn,
        hrvRmssd: hrvRmssd,
      );
    }

    // Push to emotion engine
    try {
      // Use current time for timestamp - emotion engine needs real-time window calculations
      // The metrics.timestamp may be when data was originally recorded (could be old),
      // but for the sliding window, we need when we're processing it now
      final now = DateTime.now().toUtc();

      _emotionEngine?.push(
        hr: hr,
        rrIntervalsMs: rrIntervals,
        timestamp: now,
        motion: {'magnitude': motion},
      );
    } catch (e) {
      // Error pushing to emotion engine
    }
  }

  /// Process emotion updates from the emotion engine
  void _processEmotionUpdates() async {
    if (_emotionEngine == null) {
      return;
    }

    try {
      final emotionResults = await _emotionEngine!.consumeReady();

      if (emotionResults.isEmpty) {
        return;
      }

      // Get latest emotion result
      final latestEmotion = emotionResults.last;
      _sessionEmotions.add(latestEmotion);

      // Emit emotion stream
      if (_emotionStreamController.isClosed) {
        return;
      }

      _emotionStreamController.add(latestEmotion);

      // Get current physiological data for SWIP computation
      try {
        final lastMetrics = await _wear.readMetrics();
        final hr = lastMetrics.getMetric(MetricType.hr)?.toDouble() ?? 0.0;
        final hrv =
            lastMetrics.getMetric(MetricType.hrvSdnn)?.toDouble() ?? 0.0;
        final motion = lastMetrics.metrics['motion']?.toDouble() ?? 0.0;

        // Compute SWIP score
        final swipResult = _swipEngine.computeScore(
          hr: hr,
          hrv: hrv,
          motion: motion,
          emotion: _buildEmotionSnapshot(latestEmotion),
        );

        // Store and emit score
        _sessionScores.add(swipResult);
        _scoreStreamController.add(swipResult);
      } catch (e) {
        // Failed to read metrics or compute SWIP score
      }
    } catch (e) {
      // Error processing emotion updates
    }
  }

  /// Generate RR intervals from HR and HRV metrics (SDNN and/or RMSSD)
  ///
  /// This method creates a realistic sequence of RR intervals that would
  /// produce the observed HRV metrics when calculated from them.
  ///
  /// Algorithm:
  /// 1. Calculate mean RR from HR: meanRR = 60000 / HR
  /// 2. Use SDNN as the target standard deviation
  /// 3. Use RMSSD to add short-term variability (if available)
  /// 4. Generate a sequence with correct statistical properties
  List<double> _generateRRIntervalsFromHRV({
    required double hr,
    double? hrvSdnn,
    double? hrvRmssd,
  }) {
    // Calculate mean RR interval from heart rate
    final meanRR = 60000.0 / hr;

    // Determine target variability
    // Prefer SDNN if available, otherwise estimate from RMSSD
    // RMSSD is typically 0.5-0.7 of SDNN for healthy individuals
    final targetStdDev =
        hrvSdnn ?? (hrvRmssd != null ? hrvRmssd / 0.6 : meanRR * 0.05);

    // Generate ~60 intervals for ~1 minute of data (adjust based on HR)
    // Aim for roughly 1 minute: numIntervals ≈ HR (since HR is beats per minute)
    final numIntervals = (hr * 1.0).round().clamp(30, 120);

    final intervals = <double>[];

    // Generate RR intervals with correct mean and standard deviation
    // Using a simple autoregressive model to create realistic variability
    double currentRR = meanRR;
    final alpha = 0.7; // Autocorrelation coefficient for smooth transitions

    for (int i = 0; i < numIntervals; i++) {
      // Add random variation scaled by target standard deviation
      final randomValue = _getPseudoRandom();
      final randomComponent = (randomValue - 0.5) * 2.0 * targetStdDev;

      // Use autoregressive model: new = α * old + (1-α) * target + noise
      currentRR = alpha * currentRR + (1 - alpha) * meanRR + randomComponent;

      // Add short-term variability if RMSSD is available
      if (hrvRmssd != null && i > 0) {
        // RMSSD captures beat-to-beat differences
        final shortTermRandom = _getPseudoRandom();
        final shortTermVar = (shortTermRandom - 0.5) * hrvRmssd * 0.5;
        currentRR += shortTermVar;
      }

      // Clamp to physiologically valid range (300ms to 2000ms)
      currentRR = currentRR.clamp(300.0, 2000.0);
      intervals.add(currentRR);
    }

    // Post-process: scale the sequence to match the target SDNN exactly
    if (hrvSdnn != null && intervals.length >= 2) {
      final currentMean = intervals.reduce((a, b) => a + b) / intervals.length;
      final currentVariance = intervals
              .map((x) => (x - currentMean) * (x - currentMean))
              .reduce((a, b) => a + b) /
          (intervals.length - 1);
      final currentStdDev = math.sqrt(currentVariance);

      if (currentStdDev > 0.1) {
        // Scale to match target SDNN while preserving mean
        final scaleFactor = targetStdDev / currentStdDev;
        for (int i = 0; i < intervals.length; i++) {
          intervals[i] =
              currentMean + (intervals[i] - currentMean) * scaleFactor;
          intervals[i] = intervals[i].clamp(300.0, 2000.0);
        }
      }
    }

    return intervals;
  }

  /// Simple pseudo-random number generator for deterministic but varied sequences
  /// Uses a linear congruential generator with a seed based on timestamp
  int _randomSeed = DateTime.now().millisecondsSinceEpoch;

  /// Get next pseudo-random number in range [0, 1)
  double _getPseudoRandom() {
    // Linear congruential generator: simple but sufficient for this use case
    _randomSeed = (_randomSeed * 1103515245 + 12345) & 0x7fffffff;
    return _randomSeed / 0x7fffffff; // Normalize to [0, 1)
  }

  /// Stream of SWIP scores (emits ~1 Hz)
  Stream<SwipScoreResult> get scoreStream {
    return _scoreStreamController.stream;
  }

  /// Stream of emotion results
  Stream<EmotionResult> get emotionStream {
    return _emotionStreamController.stream;
  }

  /// Get current SWIP score
  SwipScoreResult? getCurrentScore() {
    return _sessionScores.isNotEmpty ? _sessionScores.last : null;
  }

  /// Get current emotion
  EmotionResult? getCurrentEmotion() {
    return _sessionEmotions.isNotEmpty ? _sessionEmotions.last : null;
  }

  /// Clear session data
  void _clearSession() {
    _sessionScores.clear();
    _sessionEmotions.clear();
    _activeSessionId = null;
    _emotionEngine?.clear();
  }

  /// Dispose resources
  void dispose() {
    _wearSubscription?.cancel();
    _hrvSubscription?.cancel();
    _emotionProcessor?.cancel();
    _scoreStreamController.close();
    _emotionStreamController.close();
    _wear.dispose();
  }

  EmotionSnapshot _buildEmotionSnapshot(EmotionResult result) {
    final probabilities = result.probabilities;
    final stressProb = probabilities['Stress'] ??
        probabilities['Stressed'] ??
        probabilities['stress'] ??
        0.0;
    final calmProb = probabilities['Calm'] ??
        probabilities['calm'] ??
        probabilities['Relaxed'] ??
        0.0;
    double arousal = stressProb;
    if (arousal <= 0.0 && probabilities.isNotEmpty) {
      arousal = 1.0 - calmProb;
    }
    if (arousal <= 0.0) {
      arousal = result.confidence;
    }
    arousal = arousal.clamp(0.0, 1.0);

    final state = _mapEmotionState(result.emotion);
    final confidence = result.confidence.clamp(0.0, 1.0);
    final isWarmingUp = probabilities.isEmpty;

    return EmotionSnapshot(
      arousalScore: arousal,
      state: state,
      confidence: confidence,
      isWarmingUp: isWarmingUp,
    );
  }

  String _mapEmotionState(String label) {
    switch (label.toLowerCase()) {
      case 'calm':
      case 'relaxed':
        return 'Calm';
      case 'stress':
      case 'stressed':
      case 'anxious':
        return 'Stress';
      default:
        return 'Neutral';
    }
  }
}

/// Configuration for SWIP SDK
class SwipSdkConfig {
  final SwipConfig swipConfig;
  final EmotionConfig emotionConfig;
  final bool enableLogging;
  final bool enableLocalStorage;
  final String? localStoragePath;

  const SwipSdkConfig({
    SwipConfig? swipConfig,
    EmotionConfig? emotionConfig,
    this.enableLogging = true,
    this.enableLocalStorage = true,
    this.localStoragePath,
  })  : swipConfig = swipConfig ?? const SwipConfig(),
        emotionConfig = emotionConfig ??
            const EmotionConfig(
              modelId: 'extratrees_wrist_all_v1_0',
            );
}
