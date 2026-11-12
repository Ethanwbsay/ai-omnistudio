import 'package:flutter_test/flutter_test.dart';
import 'package:question_solver/models/api_profile.dart';
import 'package:question_solver/models/character_card.dart';
import 'package:question_solver/models/chat_message.dart';
import 'package:question_solver/models/chat_session.dart';
import 'package:question_solver/models/user_persona.dart';

void main() {
  const profile = ApiProfile(
    id: 'api-1',
    name: '本地模型',
    baseUrl: 'https://example.test/v1/',
    apiKey: 'secret',
    model: 'chat-model',
    temperature: .7,
    maxTokens: 4096,
  );
  const character = CharacterCard(
    id: 'character-1',
    name: '林默',
    avatarPath: '/tmp/avatar.jpg',
    description: '一位神秘的旅人',
    personality: '温柔、敏锐',
    background: '雨夜的旧车站',
    openingMessage: '你终于来了。',
    exampleDialogue: '林默：欢迎。',
    systemPrompt: '保持克制。',
    apiProfileId: 'api-1',
  );

  test('validates and round-trips API profile', () {
    expect(profile.isComplete, isTrue);
    expect(
        profile.chatCompletionsUrl, 'https://example.test/v1/chat/completions');
    expect(ApiProfile.fromJson(profile.toJson()).toJson(), profile.toJson());
  });

  test('round-trips character, persona, and session data', () {
    const persona = UserPersona(
      nickname: '阿澈',
      identity: '摄影师',
      preferences: '喜欢慢节奏对话',
      customPrompt: '不要替我做决定',
    );
    final session = ChatSession.create(
      characterId: character.id,
      openingMessage: character.openingMessage,
    ).copyWith(messages: [
      const ChatMessage(role: MessageRole.assistant, content: '你终于来了。'),
      const ChatMessage(role: MessageRole.user, content: '我来了。'),
    ]);

    expect(CharacterCard.fromJson(character.toJson()).toJson(),
        character.toJson());
    expect(UserPersona.fromJson(persona.toJson()).toJson(), persona.toJson());
    final restored = ChatSession.fromJson(session.toJson());
    expect(restored.characterId, character.id);
    expect(restored.messages, hasLength(2));
    expect(restored.messages.last.content, '我来了。');
  });

  test('new sessions include a non-empty opening message', () {
    final session = ChatSession.create(
      characterId: character.id,
      openingMessage: character.openingMessage,
    );
    expect(session.messages, hasLength(1));
    expect(session.messages.single.role, MessageRole.assistant);
    expect(session.messages.single.content, character.openingMessage);
  });
}
