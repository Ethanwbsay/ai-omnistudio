import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_settings.dart';

class SettingsStore {
  static const _baseUrl = 'api_base_url';
  static const _apiKey = 'api_key';
  static const _model = 'api_model';

  Future<ApiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ApiSettings(
      baseUrl: prefs.getString(_baseUrl) ?? 'https://api.openai.com/v1',
      apiKey: prefs.getString(_apiKey) ?? '',
      model: prefs.getString(_model) ?? 'gpt-4o-mini',
    );
  }

  Future<void> save(ApiSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrl, settings.baseUrl.trim());
    await prefs.setString(_apiKey, settings.apiKey.trim());
    await prefs.setString(_model, settings.model.trim());
  }
}
