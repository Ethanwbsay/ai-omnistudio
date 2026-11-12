import 'package:flutter/foundation.dart';

import '../models/api_profile.dart';
import '../models/character_card.dart';
import '../models/chat_message.dart';
import '../models/chat_session.dart';
import '../models/user_persona.dart';
import 'api_profile_store.dart';
import 'character_store.dart';
import 'chat_session_store.dart';
import 'user_persona_store.dart';

class TavernController extends ChangeNotifier {
  TavernController({
    ApiProfileStore? apiStore,
    CharacterStore? characterStore,
    ChatSessionStore? sessionStore,
    UserPersonaStore? personaStore,
  })  : _apiStore = apiStore ?? ApiProfileStore(),
        _characterStore = characterStore ?? CharacterStore(),
        _sessionStore = sessionStore ?? ChatSessionStore(),
        _personaStore = personaStore ?? UserPersonaStore();

  final ApiProfileStore _apiStore;
  final CharacterStore _characterStore;
  final ChatSessionStore _sessionStore;
  final UserPersonaStore _personaStore;

  List<ApiProfile> apiProfiles = const [];
  List<CharacterCard> characters = const [];
  List<ChatSession> sessions = const [];
  UserPersona persona = const UserPersona();
  bool loading = true;

  Future<void> load() async {
    if (!loading && characters.isNotEmpty) return;
    try {
      final values = await Future.wait([
        _apiStore.load(),
        _characterStore.load(),
        _sessionStore.load(),
        _personaStore.load(),
      ]);
      apiProfiles = values[0] as List<ApiProfile>;
      characters = values[1] as List<CharacterCard>;
      sessions = values[2] as List<ChatSession>;
      persona = values[3] as UserPersona;
      loading = false;
      notifyListeners();
    } catch (_) {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> saveApiProfile(ApiProfile profile) async {
    final updated = [...apiProfiles];
    final index = updated.indexWhere((item) => item.id == profile.id);
    if (index < 0) {
      updated.add(profile);
    } else {
      updated[index] = profile;
    }
    apiProfiles = updated;
    notifyListeners();
    await _apiStore.save(apiProfiles);
  }

  Future<bool> deleteApiProfile(String id) async {
    if (characters.any((character) => character.apiProfileId == id)) {
      return false;
    }
    apiProfiles = apiProfiles.where((profile) => profile.id != id).toList();
    notifyListeners();
    await _apiStore.save(apiProfiles);
    return true;
  }

  Future<void> saveCharacter(CharacterCard character) async {
    final updated = [...characters];
    final index = updated.indexWhere((item) => item.id == character.id);
    if (index < 0) {
      updated.insert(0, character);
    } else {
      updated[index] = character;
    }
    characters = updated;
    notifyListeners();
    await _characterStore.save(characters);
  }

  Future<String> persistAvatar(String sourcePath) =>
      _characterStore.persistAvatar(sourcePath);

  Future<void> savePersona(UserPersona value) async {
    persona = value;
    notifyListeners();
    await _personaStore.save(value);
  }

  Future<ChatSession> ensureSession(CharacterCard character) async {
    final existing = sessions
        .where((session) => session.characterId == character.id)
        .toList();
    if (existing.isNotEmpty) return existing.first;
    final created = ChatSession.create(
      characterId: character.id,
      openingMessage: character.openingMessage,
    );
    sessions = [created, ...sessions];
    notifyListeners();
    await _sessionStore.save(sessions);
    return created;
  }

  Future<ChatSession> createSession(CharacterCard character) async {
    final created = ChatSession.create(
      characterId: character.id,
      openingMessage: character.openingMessage,
    );
    sessions = [created, ...sessions];
    notifyListeners();
    await _sessionStore.save(sessions);
    return created;
  }

  Future<void> saveSession(ChatSession session) async {
    final updated = [...sessions];
    final index = updated.indexWhere((item) => item.id == session.id);
    if (index < 0) {
      updated.insert(0, session);
    } else {
      updated[index] = session;
    }
    updated.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    sessions = updated;
    notifyListeners();
    await _sessionStore.save(sessions);
  }

  Future<void> clearSession(
      ChatSession session, CharacterCard character) async {
    final cleared = session.copyWith(
      title: '新会话',
      messages: character.openingMessage.trim().isEmpty
          ? const []
          : [
              ChatMessage(
                role: MessageRole.assistant,
                content: character.openingMessage,
              ),
            ],
      updatedAt: DateTime.now(),
    );
    await saveSession(cleared);
  }

  ApiProfile? profileFor(CharacterCard character) {
    for (final profile in apiProfiles) {
      if (profile.id == character.apiProfileId) return profile;
    }
    return null;
  }
}
