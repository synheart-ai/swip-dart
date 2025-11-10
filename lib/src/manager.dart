// import 'dart:async';
// import 'models.dart';
// import 'errors.dart';
// import 'package:synheart_wear/synheart_wear.dart';
// import 'package:synheart_emotion/synheart_emotion.dart' as emo;
// import 'package:synheart_emotion/src/' as emo;

// class SWIPManager {
//   final SynheartWear _wear;
//   emo.EmotionEngine? _emotionEngine;
//   final _emotionCtrl = StreamController<EmotionPrediction>.broadcast();
//   Timer? _emotionTimer;
//   StreamSubscription<WearMetrics>? _wearSubscription;

//   // Session tracking
//   bool _initialized = false;
//   String? _activeSessionId;
//   DateTime? _sessionStartTime;
//   EmotionPrediction? _lastEmotion;
//   final List<HRVMeasurement> _sessionHRVData = [];

//   SWIPManager({
//     SynheartWear? wear,
//   }) : _wear = wear ?? SynheartWear();

//   Future<void> initialize() async {
//     await _wear.initialize();
//     // Request permissions for health data
//     await _wear.requestPermissions();
//     // Load ONNX model from assets and initialize emotion engine
//     final onnx = await emo.OnnxEmotionModel.loadFromAsset(
//       modelAssetPath: 'assets/ml/extratrees_wrist_all_v1_0.onnx',
//       metaAssetPath: 'assets/ml/extratrees_wrist_all_v1_0.meta.json',
//     );
//     _emotionEngine = emo.EmotionEngine.fromPretrained(
//       const emo.EmotionConfig(
//         window: Duration(seconds: 60),
//         step: Duration(seconds: 5),
//         minRrCount: 10,
//       ),
//       model: onnx,
//       onLog: (level, message, {context}) {
//         print('[SWIP][EMO][' +
//             level +
//             '] ' +
//             message +
//             (context != null ? ' ' + context.toString() : ''));
//       },
//     );
//     _initialized = true;
//   }

//   Future<String> startSession({required SWIPSessionConfig config}) async {
//     if (!_initialized) {
//       throw InvalidConfigurationError('SWIPManager not initialized');
//     }

//     _activeSessionId = DateTime.now().millisecondsSinceEpoch.toString();
//     _sessionStartTime = DateTime.now();
//     _sessionHRVData.clear();

//     // Subscribe to HR stream from synheart_wear
//     _wearSubscription?.cancel();
//     _wearSubscription =
//         _wear.streamHR(interval: const Duration(seconds: 2)).listen((metrics) {
//       // Extract HR and HRV data
//       final hr = metrics.getMetric(MetricType.hr)?.toDouble();
//       final hrvSdnn = metrics.getMetric(MetricType.hrvSdnn)?.toDouble();
//       final hrvRmssd = metrics.getMetric(MetricType.hrvRmssd)?.toDouble();

//       // Store HRV data for session results calculation
//       if (hrvSdnn != null && hrvRmssd != null) {
//         _sessionHRVData.add(HRVMeasurement(
//           rmssd: hrvRmssd,
//           sdnn: hrvSdnn,
//           pnn50: 0.0, // Not available from synheart_wear
//           lf: null,
//           hf: null,
//           lfHfRatio: null,
//           timestamp: metrics.timestamp,
//           quality: 'good',
//         ));
//       }

//       // Feed emotion engine
//       if (hr != null) {
//         final rrIntervals = metrics.rrMs ?? <double>[];
//         _emotionEngine?.push(
//           hr: hr,
//           rrIntervalsMs: rrIntervals,
//           timestamp: metrics.timestamp,
//           motion: metrics.metrics['motion'] != null
//               ? {'magnitude': metrics.metrics['motion']!.toDouble()}
//               : null,
//         );
//       }
//     });

//     // Periodically consume results and emit mapped predictions
//     _emotionTimer?.cancel();
//     _emotionTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
//       final results =
//           await _emotionEngine?.consumeReady() ?? const <emo.EmotionResult>[];
//       for (final r in results) {
//         final pred = _mapEmotionResult(r);
//         _emotionCtrl.add(pred);
//         _lastEmotion = pred;
//         _onEmotionUpdate(pred);
//       }
//     });

//     return _activeSessionId!;
//   }

//   Future<SWIPSessionResults> endSession() async {
//     if (_activeSessionId == null) {
//       throw SessionNotFoundError();
//     }

//     _emotionTimer?.cancel();
//     _emotionTimer = null;
//     await _wearSubscription?.cancel();
//     _wearSubscription = null;

//     // Calculate wellness impact from collected HRV data
//     final results =
//         _calculateWellnessImpact(_sessionHRVData, _sessionStartTime!);

//     _activeSessionId = null;
//     _sessionHRVData.clear();
//     _sessionStartTime = null;

//     return results;
//   }

//   Future<SWIPMetrics> getCurrentMetrics() async {
//     final metrics = await _wear.readMetrics();
//     final hrvSdnn = metrics.getMetric(MetricType.hrvSdnn)?.toDouble();
//     return SWIPMetrics(hrv: hrvSdnn, timestamp: DateTime.now());
//   }

//   /// Get stream of real-time emotion predictions
//   Stream<EmotionPrediction> get emotionStream => _emotionCtrl.stream;

//   /// Get current emotion state (best-effort: last emitted)
//   EmotionPrediction? get currentEmotion => _lastEmotion;

//   /// Check if emotion recognition is available
//   bool get isEmotionRecognitionAvailable => _emotionEngine != null;

//   /// Get available emotion classes
//   List<String> get emotionClasses => const ['Calm', 'Stressed', 'Amused'];

//   /// Add heart rate data for emotion analysis (manual feed)
//   void addHeartRateData(double heartRate, DateTime timestamp) {
//     _emotionEngine?.push(
//         hr: heartRate,
//         rrIntervalsMs: const <double>[],
//         timestamp: timestamp.toUtc());
//   }

//   /// Add RR interval data for emotion analysis (manual feed)
//   void addRRIntervalData(double rrIntervalMs, DateTime timestamp) {
//     _emotionEngine?.push(
//         hr: 60000.0 / rrIntervalMs,
//         rrIntervalsMs: [rrIntervalMs],
//         timestamp: timestamp.toUtc());
//   }

//   /// Handle emotion prediction updates
//   void _onEmotionUpdate(EmotionPrediction prediction) {
//     print(
//         'Emotion detected: ${prediction.emotion} (confidence: ${prediction.confidence.toStringAsFixed(2)})');
//   }

//   /// Dispose resources
//   void dispose() {
//     _emotionTimer?.cancel();
//     _wearSubscription?.cancel();
//     _emotionCtrl.close();
//     _wear.dispose();
//   }

//   /// Calculate wellness impact from HRV data (similar to adapter's logic)
//   SWIPSessionResults _calculateWellnessImpact(
//     List<HRVMeasurement> sessionData,
//     DateTime sessionStartTime,
//   ) {
//     if (sessionData.isEmpty) {
//       return SWIPSessionResults(
//         sessionId: _activeSessionId!,
//         duration: DateTime.now().difference(sessionStartTime),
//         wellnessScore: 0.0,
//         deltaHrv: 0.0,
//         coherenceIndex: 0.0,
//         stressRecoveryRate: 0.0,
//         impactType: 'neutral',
//       );
//     }

//     if (sessionData.length < 2) {
//       throw DataQualityError('Insufficient HRV data for analysis');
//     }

//     // Calculate pre-session baseline (first 30% of data)
//     final baselineCount =
//         (sessionData.length * 0.3).round().clamp(1, sessionData.length);
//     final baselineRMSSD = sessionData
//             .take(baselineCount)
//             .map((m) => m.rmssd)
//             .reduce((a, b) => a + b) /
//         baselineCount;

//     // Calculate post-session average (last 30% of data)
//     final postCount =
//         (sessionData.length * 0.3).round().clamp(1, sessionData.length);
//     final postRMSSD = sessionData
//             .skip(sessionData.length - postCount)
//             .map((m) => m.rmssd)
//             .reduce((a, b) => a + b) /
//         postCount;

//     // Calculate ΔHRV (normalized)
//     final deltaHrv = (postRMSSD - baselineRMSSD) / baselineRMSSD;

//     // Calculate Coherence Index (simplified)
//     final coherenceIndex = _calculateCoherenceIndex(sessionData);

//     // Calculate Stress-Recovery Rate (simplified)
//     final stressRecoveryRate = _calculateStressRecoveryRate(sessionData);

//     // Calculate Wellness Impact Score (WIS) per SWIP-1.0 spec
//     // WIS = w1(ΔHRV) + w2(CI) + w3(-SRR) where w1=0.5, w2=0.3, w3=0.2
//     final wellnessScore = (0.5 * deltaHrv) +
//         (0.3 * coherenceIndex) +
//         (0.2 * (1.0 - stressRecoveryRate));

//     // Classify impact type
//     String impactType;
//     if (wellnessScore > 0.2) {
//       impactType = 'beneficial';
//     } else if (wellnessScore < -0.2) {
//       impactType = 'harmful';
//     } else {
//       impactType = 'neutral';
//     }

//     return SWIPSessionResults(
//       sessionId: _activeSessionId!,
//       duration: DateTime.now().difference(sessionStartTime),
//       wellnessScore: wellnessScore.clamp(-1.0, 1.0),
//       deltaHrv: deltaHrv,
//       coherenceIndex: coherenceIndex,
//       stressRecoveryRate: stressRecoveryRate,
//       impactType: impactType,
//     );
//   }

//   double _calculateCoherenceIndex(List<HRVMeasurement> measurements) {
//     // Without LF/HF, fall back to SDNN stability heuristic
//     final sdnnValues = measurements.map((m) => m.sdnn).toList();
//     if (sdnnValues.isEmpty) return 0.5;
//     final mean = sdnnValues.reduce((a, b) => a + b) / sdnnValues.length;
//     final variance =
//         sdnnValues.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
//             sdnnValues.length;
//     return (1.0 - (variance / (mean + 1.0))).clamp(0.0, 1.0);
//   }

//   double _calculateStressRecoveryRate(List<HRVMeasurement> measurements) {
//     // Simplified recovery rate calculation
//     // Look for return to baseline in the last portion of the session
//     final baselineCount = (measurements.length * 0.3).round();
//     final baselineRMSSD = measurements
//             .take(baselineCount)
//             .map((m) => m.rmssd)
//             .reduce((a, b) => a + b) /
//         baselineCount;

//     final lastCount = (measurements.length * 0.2).round();
//     final lastRMSSD = measurements
//             .skip(measurements.length - lastCount)
//             .map((m) => m.rmssd)
//             .reduce((a, b) => a + b) /
//         lastCount;

//     // Recovery rate is how close the final RMSSD is to baseline
//     return (lastRMSSD / baselineRMSSD).clamp(0.0, 1.0);
//   }

//   EmotionPrediction _mapEmotionResult(emo.EmotionResult r) {
//     // Convert EmotionResult to EmotionPrediction
//     // Map probabilities to string keys for compatibility
//     final probMap = <String, double>{};
//     for (final entry in r.probabilities.entries) {
//       probMap[entry.key] = entry.value;
//     }

//     return EmotionPrediction(
//       emotion: r.emotion, // Already a String
//       confidence: r.confidence,
//       probabilities: probMap,
//     );
//   }
// }
