import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models/sync_payload.dart';
import 'models/sync_response.dart';
import 'logging.dart';
import 'models/device_payload.dart';
import 'models/session_record.dart';
import 'models/biosignal_record.dart';
import 'models/emotion_record.dart';

class SwipApiClient {
  final String baseUrl;
  final String? apiKey;
  final Duration timeout;

  SwipApiClient({
    this.baseUrl = 'https://swip.synheart.io/api',
    this.apiKey,
    this.timeout = const Duration(seconds: 30),
  });

  /// Register device
  Future<void> registerDevice(DevicePayload payload) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception('API key is required');
    }

    final url = Uri.parse('$baseUrl/v1/devices');

    try {
      logSync('debug', 'HTTP POST', extra: {
        'url': url.toString(),
        'hasApiKey': apiKey != null,
      });
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': apiKey!,
            },
            body: jsonEncode(payload.toJson()),
          )
          .timeout(timeout);

      final bodyText = response.body;
      logSync('debug', 'Device register response', extra: {
        'status': response.statusCode,
        'contentType': response.headers['content-type'],
        'bodyPreview':
            bodyText.length > 200 ? bodyText.substring(0, 200) : bodyText,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
      throw Exception('Device register failed: ${response.statusCode}');
    } on SocketException catch (e, s) {
      logSync('error', 'Network error',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Network error: No internet connection');
    } on HttpException catch (e, s) {
      logSync('error', 'HTTP exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('HTTP error: ${e.message}');
    } on FormatException catch (e, s) {
      logSync('error', 'Format exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('Invalid response format');
    } catch (e, s) {
      logSync('error', 'Unknown exception',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Failed to register device: $e');
    }
  }

  /// Submit session data to SWIP API
  Future<SyncResponse> submitSession(SyncPayload payload) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception('API key is required');
    }

    final url = Uri.parse('$baseUrl/v1/app_sessions');

    try {
      logSync('debug', 'HTTP POST', extra: {
        'url': url.toString(),
        'hasApiKey': apiKey != null,
      });
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': apiKey!,
            },
            body: jsonEncode(payload.toJson()),
          )
          .timeout(timeout);

      final bodyText = response.body;
      logSync('debug', 'HTTP response received', extra: {
        'status': response.statusCode,
        'contentType': response.headers['content-type'],
        'bodyPreview':
            bodyText.length > 200 ? bodyText.substring(0, 200) : bodyText,
      });
      return _handleResponse(response);
    } on SocketException catch (e, s) {
      logSync('error', 'Network error',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Network error: No internet connection');
    } on HttpException catch (e, s) {
      logSync('error', 'HTTP exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('HTTP error: ${e.message}');
    } on FormatException catch (e, s) {
      logSync('error', 'Format exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('Invalid response format');
    } catch (e, s) {
      logSync('error', 'Unknown exception',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Failed to submit session: $e');
    }
  }

  /// Submit app session record
  Future<void> submitAppSession(SessionRecord record) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception('API key is required');
    }

    final url = Uri.parse('$baseUrl/v1/app_sessions');

    log('URL: $url');

    try {
      logSync('debug', 'HTTP POST (app_session)', extra: {
        'url': url.toString(),
        'hasApiKey': apiKey != null,
      });
      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': apiKey!,
            },
            body: jsonEncode(record.toJson()),
          )
          .timeout(timeout);

      final bodyText = response.body;
      logSync('debug', 'App session response', extra: {
        'status': response.statusCode,
        'contentType': response.headers['content-type'],
        'bodyPreview':
            bodyText.length > 200 ? bodyText.substring(0, 200) : bodyText,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
      throw Exception('App session submit failed: ${response.statusCode}');
    } on SocketException catch (e, s) {
      logSync('error', 'Network error',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Network error: No internet connection');
    } on HttpException catch (e, s) {
      logSync('error', 'HTTP exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('HTTP error: ${e.message}');
    } on FormatException catch (e, s) {
      logSync('error', 'Format exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('Invalid response format');
    } catch (e, s) {
      logSync('error', 'Unknown exception',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Failed to submit app session: $e');
    }
  }

  /// Submit biosignals array
  Future<void> submitBiosignals(List<BiosignalRecord> biosignals) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception('API key is required');
    }

    if (biosignals.isEmpty) {
      logSync('debug', 'No biosignals to submit');
      return;
    }

    final url =
        Uri.parse('$baseUrl/v1/app_biosignals');

    try {
      final body = biosignals.map((b) => b.toJson()).toList();
      logSync('debug', 'HTTP POST (biosignals)', extra: {
        'url': url.toString(),
        'count': biosignals.length,
      });

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': apiKey!,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final bodyText = response.body;
      logSync('debug', 'Biosignals response', extra: {
        'status': response.statusCode,
        'contentType': response.headers['content-type'],
        'bodyPreview':
            bodyText.length > 200 ? bodyText.substring(0, 200) : bodyText,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
      throw Exception('Biosignals submit failed: ${response.statusCode}');
    } on SocketException catch (e, s) {
      logSync('error', 'Network error',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Network error: No internet connection');
    } on HttpException catch (e, s) {
      logSync('error', 'HTTP exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('HTTP error: ${e.message}');
    } on FormatException catch (e, s) {
      logSync('error', 'Format exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('Invalid response format');
    } catch (e, s) {
      logSync('error', 'Unknown exception',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Failed to submit biosignals: $e');
    }
  }

  /// Submit emotions array
  Future<void> submitEmotions(List<EmotionRecord> emotions) async {
    if (apiKey == null || apiKey!.isEmpty) {
      throw Exception('API key is required');
    }

    if (emotions.isEmpty) {
      logSync('debug', 'No emotions to submit');
      return;
    }

    final url = Uri.parse('$baseUrl/v1/emotions');

    try {
      final body = emotions.map((e) => e.toJson()).toList();
      logSync('debug', 'HTTP POST (emotions)', extra: {
        'url': url.toString(),
        'count': emotions.length,
      });

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'X-API-Key': apiKey!,
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);

      final bodyText = response.body;
      logSync('debug', 'Emotions response', extra: {
        'status': response.statusCode,
        'contentType': response.headers['content-type'],
        'bodyPreview':
            bodyText.length > 200 ? bodyText.substring(0, 200) : bodyText,
      });

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return;
      }
      throw Exception('Emotions submit failed: ${response.statusCode}');
    } on SocketException catch (e, s) {
      logSync('error', 'Network error',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Network error: No internet connection');
    } on HttpException catch (e, s) {
      logSync('error', 'HTTP exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('HTTP error: ${e.message}');
    } on FormatException catch (e, s) {
      logSync('error', 'Format exception',
          extra: {'stack': s.toString(), 'error': e.message});
      throw Exception('Invalid response format');
    } catch (e, s) {
      logSync('error', 'Unknown exception',
          extra: {'stack': s.toString(), 'error': e.toString()});
      throw Exception('Failed to submit emotions: $e');
    }
  }

  SyncResponse _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    final raw = response.body;
    Map<String, dynamic> body = const {};
    try {
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        } else {
          logSync('warn', 'Non-object JSON response',
              extra: {'status': statusCode});
        }
      } else {
        logSync('warn', 'Empty response body', extra: {'status': statusCode});
      }
    } catch (e) {
      logSync('error', 'Invalid JSON response', extra: {
        'status': statusCode,
        'bodyPreview': raw.length > 200 ? raw.substring(0, 200) : raw,
      });
      throw ApiException(
        statusCode: statusCode,
        message: 'Invalid JSON response',
        isRetryable: false,
      );
    }

    if (statusCode == 200) {
      logSync('info', 'Request succeeded');
      return SyncResponse.fromJson(body);
    } else if (statusCode == 401) {
      final error = body['error'] as String? ?? 'Unauthorized';
      logSync('warn', 'Unauthorized',
          extra: {'status': statusCode, 'error': error});
      throw ApiException(
        statusCode: statusCode,
        message: error,
        isRetryable: false,
      );
    } else if (statusCode == 400) {
      final error = body['error'] as String? ?? 'Bad request';
      logSync('warn', 'Bad request',
          extra: {'status': statusCode, 'error': error});
      throw ApiException(
        statusCode: statusCode,
        message: error,
        isRetryable: false,
      );
    } else if (statusCode == 429) {
      logSync('warn', 'Rate limit exceeded', extra: {'status': statusCode});
      throw ApiException(
        statusCode: statusCode,
        message: 'Rate limit exceeded',
        isRetryable: true,
        retryAfter: _parseRetryAfter(response.headers),
      );
    } else if (statusCode >= 500) {
      logSync('error', 'Server error',
          extra: {'status': statusCode, 'body': body});
      throw ApiException(
        statusCode: statusCode,
        message: body['error'] as String? ?? 'Server error',
        isRetryable: true,
      );
    } else {
      logSync('error', 'Unhandled status',
          extra: {'status': statusCode, 'body': body});
      throw ApiException(
        statusCode: statusCode,
        message: body['error'] as String? ?? 'Unknown error',
        isRetryable: false,
      );
    }
  }

  Duration? _parseRetryAfter(Map<String, String> headers) {
    final retryAfter = headers['retry-after'];
    if (retryAfter != null) {
      final seconds = int.tryParse(retryAfter);
      if (seconds != null) {
        return Duration(seconds: seconds);
      }
    }
    return null;
  }
}

/// API exception with retry information
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final bool isRetryable;
  final Duration? retryAfter;

  ApiException({
    required this.statusCode,
    required this.message,
    required this.isRetryable,
    this.retryAfter,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';
}
