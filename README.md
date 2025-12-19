# SWIP Flutter SDK

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)
[![Platform](https://img.shields.io/badge/platform-Flutter-blue.svg)](https://flutter.dev)
[![Pub](https://img.shields.io/badge/pub-1.0.0-blue.svg)](https://pub.dev/packages/swip)

**Quantify your app's impact on human wellness using real-time biosignals and emotion inference**

## Features

- **🔒 Privacy-First**: All processing happens locally on-device by default
- **📱 Biosignal Collection**: Uses synheart_wear to read HR and HRV from wearables
- **🧠 Emotion Recognition**: On-device emotion classification from biosignals
- **📊 SWIP Score**: Quantitative wellness impact scoring (0-100)
- **🔐 GDPR Compliant**: User consent management and data purging
- **⚡ Dart Streams**: Real-time score and emotion updates
- **📲 Cross-Platform**: iOS, Android, Web support

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  swip: ^1.0.0
```

Then run:
```bash
flutter pub get
```

## Requirements

- **Flutter**: 3.10.0+
- **Dart**: 3.0.0+

## Quick Start

### 1. Initialize the SDK

```dart
import 'package:swip/swip.dart';

final sdk = SwipSdkManager(
  config: SwipSdkConfig(
    enableLogging: true,
  ),
);

await sdk.initialize();
```

### 2. Start a Session

```dart
// Start session
final sessionId = await sdk.startSession(
  appId: 'com.example.myapp',
  metadata: {'screen': 'meditation'},
);

// Listen to SWIP scores
sdk.scoreStream.listen((result) {
  print('SWIP Score: ${result.swipScore}');
  print('Emotion: ${result.dominantEmotion}');
  print('Confidence: ${result.confidence}');
});
```

### 3. Stop a Session

```dart
final results = await sdk.stopSession();
print('Average SWIP Score: ${results.getSummary()['average_swip_score']}');
```

## API Reference

### SwipSdkManager

#### Methods

- `Future<void> initialize()` - Initialize the SDK
- `Future<String> startSession(String appId, {Map<String, dynamic>? metadata})` - Start a session
- `Future<SwipSessionResults> stopSession()` - Stop the current session
- `SwipScoreResult? getCurrentScore()` - Get current SWIP score
- `EmotionResult? getCurrentEmotion()` - Get current emotion
- `Future<void> setUserConsent(ConsentLevel level, String reason)` - Set consent level
- `ConsentLevel getUserConsent()` - Get current consent level
- `Future<void> purgeAllData()` - Delete all user data (GDPR compliance)

#### Streams

- `Stream<SwipScoreResult> scoreStream` - Real-time SWIP scores (~1 Hz)
- `Stream<EmotionResult> emotionStream` - Real-time emotion predictions

### Models

```dart
class SwipScoreResult {
  final double swipScore;              // 0-100 wellness score
  final double physSubscore;           // Physiological contribution
  final double emoSubscore;            // Emotion contribution
  final double confidence;             // Confidence level
  final String dominantEmotion;        // "Calm", "Stressed", etc.
  final Map<String, double> emotionProbabilities;
  final DateTime timestamp;
  final String modelId;
  final Map<String, double> reasons;   // Explainable factors
  final bool artifactFlag;
}

enum ConsentLevel {
  onDevice,       // Local processing only (default)
  localExport,    // Manual export allowed
  dashboardShare  // Aggregated data sharing
}
```

## Score Interpretation

| Score Range | State | Meaning |
|-------------|-------|---------|
| 80-100 | Positive | Relaxed / Engaged - app supports wellness |
| 60-79 | Neutral | Emotionally stable |
| 40-59 | Mild Stress | Cognitive or emotional fatigue |
| <40 | Negative | Stress / emotional load detected |

## Architecture

```
Wearables → synheart_wear → swip_core → swip-dart
                ↓
          synheart_emotion
```

The SDK uses:
- **synheart_wear** for biosignal collection from wearables
- **swip_core** for HRV feature extraction and SWIP score computation
- **synheart_emotion** for on-device emotion classification

## Privacy

- **Local-first**: All processing happens on-device by default
- **Explicit Consent**: Required before any data sharing
- **GDPR Compliance**: `purgeAllData()` deletes all user data
- **No Raw Biosignals**: Only aggregated metrics transmitted (if consent given)
- **Anonymization**: Hashed device IDs, per-session UUIDs

## Testing

```bash
# Run tests
flutter test

# Run with coverage
flutter test --coverage
```

## 📄 License

Apache 2.0 License


## Support

- **Issues**: https://github.com/synheart-ai/swip/issues
- **Docs**: https://swip.synheart.ai/docs
- **Email**: dev@synheart.ai

---

Part of the Synheart Wellness Impact Protocol (SWIP) open standard.


## Patent Pending Notice

This project is provided under an open-source license. Certain underlying systems, methods, and architectures described or implemented herein may be covered by one or more pending patent applications.

Nothing in this repository grants any license, express or implied, to any patents or patent applications, except as provided by the applicable open-source license.