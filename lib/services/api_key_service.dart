import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ApiKeyService {
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _groqApiKeyKey = 'groq_api_key';

  /// Get the stored Groq API key
  static Future<String?> getGroqApiKey() async {
    try {
      return await _secureStorage.read(key: _groqApiKeyKey);
    } catch (e) {
      print('Error reading API key: $e');
      return null;
    }
  }

  /// Store a new Groq API key
  static Future<bool> setGroqApiKey(String apiKey) async {
    try {
      await _secureStorage.write(key: _groqApiKeyKey, value: apiKey);
      return true;
    } catch (e) {
      print('Error storing API key: $e');
      return false;
    }
  }

  /// Remove the stored Groq API key
  static Future<bool> removeGroqApiKey() async {
    try {
      await _secureStorage.delete(key: _groqApiKeyKey);
      return true;
    } catch (e) {
      print('Error removing API key: $e');
      return false;
    }
  }

  /// Check if a Groq API key is stored
  static Future<bool> hasGroqApiKey() async {
    try {
      final apiKey = await _secureStorage.read(key: _groqApiKeyKey);
      return apiKey != null && apiKey.isNotEmpty;
    } catch (e) {
      print('Error checking API key: $e');
      return false;
    }
  }

  /// Get the default API key (fallback)
  /// Note: In production, this should be loaded from environment variables or secure storage
  /// For now, users must provide their own API key through the app settings
  static String getDefaultApiKey() {
    // API key removed for security - users must set their own key in app settings
    return ''; // Empty string - app will prompt user to set their API key
  }

  /// Get the API key to use (user's key if available, otherwise default)
  static Future<String> getApiKeyToUse() async {
    final userApiKey = await getGroqApiKey();
    return userApiKey ?? getDefaultApiKey();
  }
}
