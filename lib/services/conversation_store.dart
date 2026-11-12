import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/conversation.dart';

class ConversationStore {
  static const _fileName = 'question_solver_conversations.json';

  Future<List<Conversation>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      final conversations = decoded
          .whereType<Map>()
          .map((item) => Conversation.fromJson(Map<String, dynamic>.from(item)))
          .toList();
      conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return conversations;
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<Conversation> conversations) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(
          conversations.map((conversation) => conversation.toJson()).toList()),
      flush: true,
    );
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
