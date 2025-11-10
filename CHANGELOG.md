# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-XX

### Added
- Initial release of SWIP Flutter SDK
- `SwipSdkManager` - Main SDK entry point for orchestrating all components
- `SwipScoreResult` - Comprehensive score results with emotion probabilities
- Consent management system with three privacy levels (onDevice, localExport, dashboardShare)
- Local SQLite storage with automatic data retention policies
- Real-time SWIP score streaming
- Session lifecycle management
- Integration with synheart_wear and synheart_emotion packages
- Comprehensive documentation and quick start guide
- Example Flutter app demonstrating SDK usage

### Features
- Privacy-first design with local-first processing
- Automatic artifact detection and smoothing
- Adaptive baseline computation
- Emotion recognition with confidence scores
- Physiological subscore computation (HR, HRV, motion)
- Emotion subscore computation with utility weights
- SWIP score fusion algorithm (0-100 scale)
- 30-day raw biosignal retention with auto-purge
- TLS 1.3 encryption for cloud transmission
- GDPR-compliant data purge API

### Requirements
- Flutter SDK >=3.0.0
- Dart SDK >=3.0.0
- iOS 13+ or Android API 24+
- Compatible wearable device
- Health permissions

[1.0.0]: https://github.com/synheart-ai/swip-flutter/releases/tag/v1.0.0

