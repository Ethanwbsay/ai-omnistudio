import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:question_solver/models/api_settings.dart';
import 'package:question_solver/models/api_profile.dart';
import 'package:question_solver/models/character_card.dart';
import 'package:question_solver/models/chat_message.dart';
import 'package:question_solver/models/user_persona.dart';
import 'package:question_solver/services/openai_service.dart';

class RecordingClient extends http.BaseClient {
  RecordingClient(this.responseBody);

  final Map<String, dynamic> responseBody;
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest value) async {
    request = value;
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(responseBody))),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class StreamingClient extends http.BaseClient {
  StreamingClient(this.payload, {this.statusCode = 200});

  final String payload;
  final int statusCode;
  http.BaseRequest? request;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest value) async {
    request = value;
    return http.StreamedResponse(
      Stream.value(utf8.encode(payload)),
      statusCode,
      headers: const {'content-type': 'text/event-stream'},
    );
  }
}

void main() {
  const settings = ApiSettings(
    baseUrl: 'https://api.example.test/v1',
    apiKey: 'test-key',
    model: 'vision-model',
  );

  test('sends text, photo, LaTeX instruction, and conversation history',
      () async {
    final client = RecordingClient({
      'choices': [
        {
          'message': {'content': r'Answer: $x=2$'},
        },
      ],
    });
    final service = OpenAiService(client: client);

    final answer = await service.solve(
      settings: settings,
      conversation: const [
        ChatMessage(
            role: MessageRole.user,
            content: 'Solve this',
            imageBase64: 'aW1hZ2U='),
        ChatMessage(role: MessageRole.assistant, content: 'Previous answer'),
        ChatMessage(role: MessageRole.user, content: 'Why?'),
      ],
    );

    final request = client.request! as http.Request;
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    final messages = payload['messages'] as List<dynamic>;

    expect(answer, r'Answer: $x=2$');
    expect(
        request.url.toString(), 'https://api.example.test/v1/chat/completions');
    expect(request.headers['authorization'], 'Bearer test-key');
    expect(payload['model'], 'vision-model');
    expect(messages, hasLength(5));
    expect((messages[1] as Map)['content'], contains(r'$...$'));
    expect((messages[2] as Map)['content'], isA<List>());
    expect(((messages[2] as Map)['content'] as List)[1], {
      'type': 'image_url',
      'image_url': {'url': 'data:image/jpeg;base64,aW1hZ2U='},
    });
    expect((messages[4] as Map)['content'], 'Why?');
  });

  test('builds character prompt in the documented order', () {
    final service = OpenAiService(client: RecordingClient({}));
    const character = CharacterCard(
      id: 'character-1',
      name: '林默',
      avatarPath: '',
      description: '神秘旅人',
      personality: '温柔而敏锐',
      background: '雨夜车站',
      openingMessage: '你来了。',
      exampleDialogue: '林默：欢迎。',
      systemPrompt: '不要跳出角色。',
      apiProfileId: 'api-1',
    );
    const persona = UserPersona(
      nickname: '阿澈',
      identity: '摄影师',
      preferences: '喜欢安静',
      customPrompt: '称呼我为阿澈。',
    );
    final prompt = service.buildCharacterSystemPrompt(character, persona);
    expect(prompt.indexOf('角色名称：林默'), lessThan(prompt.indexOf('角色性格：')));
    expect(prompt.indexOf('角色性格：'), lessThan(prompt.indexOf('背景与场景：')));
    expect(prompt.indexOf('背景与场景：'), lessThan(prompt.indexOf('角色补充规则：')));
    expect(prompt.indexOf('示例对话：'), lessThan(prompt.indexOf('用户资料：')));
    expect(prompt, contains('称呼我为阿澈。'));
    service.dispose();
  });

  test('parses streamed deltas and request options', () async {
    final client = StreamingClient(
      'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '你好'}
              }
            ]
          })}\n\n'
      'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': '，旅人'}
              }
            ]
          })}\n\n'
      'data: [DONE]\n\n',
    );
    final service = OpenAiService(client: client);
    const profile = ApiProfile(
      id: 'api-1',
      name: '测试 API',
      baseUrl: 'https://example.test/v1',
      apiKey: 'key',
      model: 'role-model',
      temperature: .9,
      maxTokens: 1234,
    );
    const character = CharacterCard(
      id: 'character-1',
      name: '林默',
      avatarPath: '',
      description: '',
      personality: '温柔',
      background: '',
      openingMessage: '',
      exampleDialogue: '',
      systemPrompt: '',
      apiProfileId: 'api-1',
    );
    final chunks = await service.streamReply(
      profile: profile,
      character: character,
      persona: const UserPersona(),
      history: const [
        ChatMessage(role: MessageRole.user, content: '你好'),
      ],
    ).toList();
    expect(chunks, ['你好', '，旅人']);
    final request = client.request! as http.Request;
    final payload = jsonDecode(request.body) as Map<String, dynamic>;
    expect(request.url.toString(), 'https://example.test/v1/chat/completions');
    expect(request.headers['authorization'], 'Bearer key');
    expect(payload['stream'], isTrue);
    expect(payload['temperature'], .9);
    expect(payload['max_tokens'], 1234);
    service.dispose();
  });

  test('turns a streaming HTTP error into ApiException', () async {
    final client = StreamingClient(
      jsonEncode({
        'error': {'message': '额度不足'}
      }),
      statusCode: 429,
    );
    final service = OpenAiService(client: client);
    const profile = ApiProfile(
      id: 'api-1',
      name: '测试 API',
      baseUrl: 'https://example.test/v1',
      apiKey: 'key',
      model: 'model',
    );
    const character = CharacterCard(
      id: 'character-1',
      name: '林默',
      avatarPath: '',
      description: '',
      personality: '温柔',
      background: '',
      openingMessage: '',
      exampleDialogue: '',
      systemPrompt: '',
      apiProfileId: 'api-1',
    );
    expect(
      service.streamReply(
        profile: profile,
        character: character,
        persona: const UserPersona(),
        history: const [],
      ).toList(),
      throwsA(isA<ApiException>()),
    );
    service.dispose();
  });
}
