import 'package:flutter/foundation.dart';

/// Simple logger for SWIP cloud sync
void logSync(String level, String message, {Object? extra}) {
  final ts = DateTime.now().toIso8601String();
  final payload = extra != null ? ' | extra=$extra' : '';
  debugPrint('[SWIP:SYNC][$level][$ts] $message$payload');
}
