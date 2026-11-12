import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_profile.dart';
import 'settings_store.dart';

class ApiProfileStore {
  static const _profilesKey = 'ai_tavern_api_profiles';

  Future<List<ApiProfile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profilesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .whereType<Map>()
              .map((item) =>
                  ApiProfile.fromJson(Map<String, dynamic>.from(item)))
              .toList();
        }
      } catch (_) {
        // Treat a malformed local value as an empty profile list.
      }
    }

    // Migrate the original single-profile settings once, without touching
    // the old keys used by the preserved question-solving screen.
    final legacy = await SettingsStore().load();
    if (legacy.apiKey.trim().isEmpty) return [];
    final migrated = ApiProfile(
      id: 'api-legacy-default',
      name: '默认 API',
      baseUrl: legacy.baseUrl,
      apiKey: legacy.apiKey,
      model: legacy.model,
    );
    await save([migrated]);
    return [migrated];
  }

  Future<void> save(List<ApiProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _profilesKey,
      jsonEncode(profiles.map((profile) => profile.toJson()).toList()),
    );
  }
}
