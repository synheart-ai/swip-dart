class EmotionRecord {
  final int id;
  final String appBiosignalId;
  final double? swipScore;
  final double? physSubscore;
  final double? emoSubscore;
  final double confidence;
  final String dominantEmotion;
  final String modelId;

  EmotionRecord({
    required this.id,
    required this.appBiosignalId,
    required this.swipScore,
    required this.physSubscore,
    required this.emoSubscore,
    required this.confidence,
    required this.dominantEmotion,
    required this.modelId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'app_biosignal_id': appBiosignalId,
      'swip_score': swipScore, // Required by API - filtered out if null before sync
      if (physSubscore != null) 'phys_subscore': physSubscore,
      if (emoSubscore != null) 'emo_subscore': emoSubscore,
      'confidence': confidence,
      'dominant_emotion': dominantEmotion,
      'model_id': modelId,
    };
  }
}
