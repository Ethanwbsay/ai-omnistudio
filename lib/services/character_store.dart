import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/character_card.dart';

class CharacterStore {
  static const _fileName = 'ai_tavern_characters.json';

  Future<List<CharacterCard>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map(
              (item) => CharacterCard.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<CharacterCard> characters) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(characters.map((character) => character.toJson()).toList()),
      flush: true,
    );
  }

  Future<String> persistAvatar(String sourcePath) async {
    final directory = await getApplicationDocumentsDirectory();
    final avatars =
        Directory('${directory.path}${Platform.pathSeparator}avatars');
    await avatars.create(recursive: true);
    final source = File(sourcePath);
    final extension = source.path.contains('.')
        ? source.path.substring(source.path.lastIndexOf('.'))
        : '.jpg';
    final destination = File(
        '${avatars.path}${Platform.pathSeparator}avatar-${DateTime.now().microsecondsSinceEpoch}$extension');
    await source.copy(destination.path);
    return destination.path;
  }

  Future<File> _file() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}
