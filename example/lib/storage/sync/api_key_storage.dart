import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure storage for API keys
class ApiKeyStorage {
  static const _storage = FlutterSecureStorage();
  static const _keyName = 'swip_api_key';

  /// Store API key securely
  Future<void> setApiKey(String apiKey) async {
    await _storage.write(key: _keyName, value: apiKey);
  }

  /// Retrieve API key
  Future<String?> getApiKey() async {
    return await _storage.read(key: _keyName);
  }

  /// Delete API key
  Future<void> deleteApiKey() async {
    await _storage.delete(key: _keyName);
  }

  /// Check if API key exists
  Future<bool> hasApiKey() async {
    final key = await getApiKey();
    return key != null && key.isNotEmpty;
  }
}
