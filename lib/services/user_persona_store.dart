import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_persona.dart';

class UserPersonaStore {
  static const _key = 'ai_tavern_user_persona';

  Future<UserPersona> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const UserPersona();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return UserPersona.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      // Use the default persona when the local value is malformed.
    }
    return const UserPersona();
  }

  Future<void> save(UserPersona persona) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(persona.toJson()));
  }
}
