import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/chat_session.dart';

class ChatSessionStore {
  static const _fileName = 'ai_tavern_sessions.json';

  Future<List<ChatSession>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final sessions = decoded
          .whereType<Map>()
          .map((item) => ChatSession.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      _sort(sessions);
      return sessions;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<ChatSession> sessions) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(sessions.map((session) => session.toJson()).toList()),
      flush: true,
    );
  }

  void _sort(List<ChatSession> sessions) {
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
