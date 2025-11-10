import 'dart:math' as math;

import '../src/models.dart';

/// Physiological weights remain identical to SWIP-1.0.
class PhysiologicalWeights {
  static const double hr = 0.45;
  static const double hrv = 0.35;
  static const double motion = 0.20;
}

/// Snapshot emitted by the Synheart Emotion RFC pipeline.
class EmotionSnapshot {
  final double arousalScore; // smoothed \tilde{A}_t in [0,1]
  final String state; // Calm | Neutral | Stress | warming_up
  final double confidence; // 1 - MAD_norm in [0,1]
  final bool isWarmingUp;

  const EmotionSnapshot({
    required this.arousalScore,
    required this.state,
    required this.confidence,
    required this.isWarmingUp,
  });

  String get normalisedState {
    switch (state.toLowerCase()) {
      case 'calm':
        return 'Calm';
      case 'stress':
      case 'stressed':
        return 'Stress';
      case 'warming_up':
        return 'warming_up';
      default:
        return 'Neutral';
    }
  }
}

/// SWIP score computation that consumes the new emotion snapshot but keeps the
/// 0-100 wellness impact semantics.
class SwipScoreComputation {
  static double computePhysiologicalSubscore({
    required double hr,
    required double hrv,
    required double motion,
    required PhysiologicalBaseline baseline,
  }) {
    final hrStd = baseline.hrStd == 0.0 ? 1.0 : baseline.hrStd;
    final hrvStd = baseline.hrvStd == 0.0 ? 1.0 : baseline.hrvStd;

    final hrScore = 1.0 - ((hr - baseline.hrMean).abs() / hrStd).clamp(0.0, 1.0);
    final hrvScore = 1.0 - ((hrv - baseline.hrvMean).abs() / hrvStd).clamp(0.0, 1.0);
    final motionScore = (1.0 - (motion / 2.0).clamp(0.0, 1.0));

    final physScore =
        PhysiologicalWeights.hr * hrScore +
        PhysiologicalWeights.hrv * hrvScore +
        PhysiologicalWeights.motion * motionScore;

    return physScore.clamp(0.0, 1.0);
  }

  static double computeEmotionSubscore(EmotionSnapshot snapshot) {
    final arousal = snapshot.arousalScore.clamp(0.0, 1.0);
    switch (snapshot.normalisedState) {
      case 'Calm':
        return math.max(arousal, 0.8);
      case 'Stress':
        return math.min(arousal, 0.3);
      case 'warming_up':
        return arousal * 0.5;
      default:
        return arousal;
    }
  }

  static double computeConfidence(EmotionSnapshot snapshot) {
    if (snapshot.isWarmingUp) {
      return 0.0;
    }
    return snapshot.confidence.clamp(0.0, 1.0);
  }

  static String _dominantEmotion(EmotionSnapshot snapshot) {
    final state = snapshot.normalisedState;
    if (state == 'warming_up') {
      return 'Neutral';
    }
    return state;
  }

  static SwipScoreResult computeSwipScore({
    required double hr,
    required double hrv,
    required double motion,
    required EmotionSnapshot emotion,
    required PhysiologicalBaseline baseline,
    required String modelId,
    DateTime? timestamp,
  }) {
    final physScore = computePhysiologicalSubscore(
      hr: hr,
      hrv: hrv,
      motion: motion,
      baseline: baseline,
    );

    final emoScore = computeEmotionSubscore(emotion);
    final confidence = computeConfidence(emotion);
    final beta = math.min(0.6, confidence);

    final swipRaw = beta * emoScore + (1.0 - beta) * physScore;
    final swipScore = (swipRaw * 100).clamp(0.0, 100.0);
    final dominantEmotion = _dominantEmotion(emotion);

    final reasons = {
      'hr': hr,
      'hrv': hrv,
      'motion': motion,
      'phys_contribution': physScore,
      'emo_contribution': emoScore,
      'beta': beta,
      'emotion_confidence': confidence,
      'arousal_score': emotion.arousalScore.clamp(0.0, 1.0),
    };

    return SwipScoreResult(
      swipScore: swipScore,
      physSubscore: physScore,
      emoSubscore: emoScore,
      confidence: confidence,
      dominantEmotion: dominantEmotion,
      emotionProbabilities: {
        dominantEmotion: 1.0,
        'Arousal': emotion.arousalScore.clamp(0.0, 1.0),
      },
      timestamp: timestamp ?? DateTime.now().toUtc(),
      modelId: modelId,
      reasons: reasons,
    );
  }

  static double smoothScore(double current, double previous, {double lambda = 0.9}) {
    return lambda * current + (1.0 - lambda) * previous;
  }

  static String interpretScore(double swipScore) {
    if (swipScore >= 80.0) {
      return 'Positive';
    } else if (swipScore >= 60.0) {
      return 'Neutral';
    } else if (swipScore >= 40.0) {
      return 'Mild Stress';
    } else {
      return 'Negative';
    }
  }
}

