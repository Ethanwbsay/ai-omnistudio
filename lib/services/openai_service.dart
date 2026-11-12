import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_profile.dart';
import '../models/api_settings.dart';
import '../models/character_card.dart';
import '../models/chat_message.dart';
import '../models/user_persona.dart';

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class OpenAiService {
  OpenAiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  Future<void> Function()? _cancelActive;

  /// Keeps the original question-solving API intact for the preserved tool.
  Future<String> solve({
    required ApiSettings settings,
    required List<ChatMessage> conversation,
  }) async {
    if (!settings.isComplete) {
      throw ApiException('请先在“API 设置”中填写接口地址、API Key 和模型名称。');
    }
    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '''你是一位严谨、耐心的中文学科老师。根据题目给出正确且可核查的解答。
先提炼已知条件和所求，再分步骤推导；公式要说明每一步的依据，最后给出明确答案。
当题目图片模糊、信息缺失或无法确定时，先说明不确定点并提出需要补充的内容，绝不能编造。用户后续追问时结合完整对话继续回答。''',
      },
      {
        'role': 'system',
        'content':
            r'''Format mathematics as renderable LaTeX: use $...$ for inline formulas and $$...$$ for each complete display formula. Do not escape the $ delimiters or Markdown headings, do not leave a standalone $$, and do not use 	ag{...}. Put complete matrices/cases/boxed expressions inside one $$...$$ block. Do not put LaTeX in code fences or replace fractions, roots, superscripts, and subscripts with plain-text approximations.''',
      },
      ...conversation.map(_toApiMessage),
    ];
    final body = await _postJson(
      url: settings.chatCompletionsUrl,
      apiKey: settings.apiKey,
      payload: {
        'model': settings.model.trim(),
        'messages': messages,
        'temperature': 0.2,
      },
    );
    final choices = body['choices'];
    if (choices is! List || choices.isEmpty) {
      throw ApiException('接口没有返回解答内容。');
    }
    final firstChoice = choices.first;
    final message = firstChoice is Map ? firstChoice['message'] : null;
    final content = message is Map ? message['content'] : null;
    final text = _contentText(content);
    if (text.isNotEmpty) return text;
    throw ApiException('接口没有返回解答内容。');
  }

  /// Streams text deltas from an OpenAI-compatible Chat Completions endpoint.
  Stream<String> streamReply({
    required ApiProfile profile,
    required CharacterCard character,
    required UserPersona persona,
    required List<ChatMessage> history,
  }) {
    if (!profile.isComplete) {
      return Stream<String>.error(ApiException('请先完善当前角色绑定的 API 配置。'));
    }
    final output = StreamController<String>();
    StreamSubscription<String>? lines;
    var stopped = false;
    var emittedAny = false;

    _cancelActive = () async {
      stopped = true;
      await lines?.cancel();
      if (!output.isClosed) await output.close();
    };

    () async {
      try {
        final request =
            http.Request('POST', Uri.parse(profile.chatCompletionsUrl))
              ..headers.addAll({
                'Content-Type': 'application/json',
                'Accept': 'text/event-stream',
                'Authorization': 'Bearer ${profile.apiKey.trim()}',
              })
              ..body = jsonEncode({
                'model': profile.model.trim(),
                'messages': buildCharacterMessages(
                  character: character,
                  persona: persona,
                  history: history,
                ),
                'temperature': profile.temperature,
                'max_tokens': profile.maxTokens,
                'stream': true,
              });
        final response = await _client.send(request).timeout(
              const Duration(seconds: 90),
            );
        if (stopped) return;
        if (response.statusCode < 200 || response.statusCode >= 300) {
          final detail = _errorDetail(await response.stream.bytesToString());
          throw ApiException(detail ?? '接口请求失败（HTTP ${response.statusCode}）。');
        }
        final stream = response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());
        lines = stream.listen(
          (line) {
            if (stopped) return;
            final data = line.startsWith('data:')
                ? line.substring(5).trim()
                : line.trim();
            if (data.isEmpty || data == '[DONE]') return;
            try {
              final decoded = jsonDecode(data);
              final choices = decoded is Map ? decoded['choices'] : null;
              final delta = choices is List && choices.isNotEmpty
                  ? choices.first is Map
                      ? choices.first['delta']
                      : null
                  : null;
              final text = delta is Map ? _contentText(delta['content']) : '';
              if (text.isNotEmpty) {
                emittedAny = true;
                output.add(text);
              }
            } on FormatException {
              // Ignore keep-alive/non-JSON lines in otherwise valid SSE.
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!output.isClosed && !stopped) {
              output.addError(_networkError(error), stack);
            }
          },
          onDone: () async {
            if (output.isClosed) return;
            if (!stopped && !emittedAny) {
              output.addError(ApiException('接口没有返回角色消息。'));
            }
            await output.close();
          },
          cancelOnError: false,
        );
      } catch (error, stack) {
        if (!output.isClosed && !stopped) {
          final normalized = error is FormatException
              ? ApiException('接口地址无效，请检查 API Base URL。')
              : error is ApiException
                  ? error
                  : _networkError(error);
          output.addError(normalized, stack);
          await output.close();
        }
      }
    }();
    return output.stream;
  }

  Future<void> cancelActiveRequest() async {
    final cancel = _cancelActive;
    _cancelActive = null;
    if (cancel != null) await cancel();
  }

  List<Map<String, dynamic>> buildCharacterMessages({
    required CharacterCard character,
    required UserPersona persona,
    required List<ChatMessage> history,
  }) =>
      [
        {
          'role': 'system',
          'content': buildCharacterSystemPrompt(character, persona)
        },
        ...history.map(_toApiMessage),
      ];

  String buildCharacterSystemPrompt(
    CharacterCard character,
    UserPersona persona,
  ) {
    final sections = <String>[
      '你正在进行沉浸式角色聊天。请始终以角色身份回复，不要声称自己是语言模型，不要代替用户行动。',
      '角色名称：${character.name.trim()}',
      if (character.description.trim().isNotEmpty)
        '角色简介：${character.description.trim()}',
      '角色性格：${character.personality.trim()}',
      if (character.background.trim().isNotEmpty)
        '背景与场景：${character.background.trim()}',
      if (character.systemPrompt.trim().isNotEmpty)
        '角色补充规则：${character.systemPrompt.trim()}',
      if (character.exampleDialogue.trim().isNotEmpty)
        '示例对话：\n${character.exampleDialogue.trim()}',
      '用户资料：\n昵称：${persona.nickname.trim().isEmpty ? '我' : persona.nickname.trim()}\n身份：${persona.identity.trim()}\n偏好：${persona.preferences.trim()}',
      if (persona.customPrompt.trim().isNotEmpty)
        '用户补充要求：${persona.customPrompt.trim()}',
    ];
    return sections.join('\n\n');
  }

  Future<Map<String, dynamic>> _postJson({
    required String url,
    required String apiKey,
    required Map<String, dynamic> payload,
  }) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 90));
    } on FormatException {
      throw ApiException('接口地址无效，请检查 API Base URL。');
    } catch (_) {
      throw ApiException('请求未完成。请检查网络、接口地址和 API Key 后重试。');
    }
    Map<String, dynamic> body;
    try {
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('接口返回了无法识别的内容（HTTP ${response.statusCode}）。');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
          _errorDetailFromBody(body) ?? '接口请求失败（HTTP ${response.statusCode}）。');
    }
    return body;
  }

  String? _errorDetail(String raw) {
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? _errorDetailFromBody(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  String? _errorDetailFromBody(Map body) {
    final error = body['error'];
    return error is Map ? error['message']?.toString() : null;
  }

  String _contentText(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text'] ?? part['content'])
          .whereType<String>()
          .join('\n');
    }
    return '';
  }

  ApiException _networkError(Object error) => error is ApiException
      ? error
      : ApiException('请求未完成。请检查网络、接口地址和 API Key 后重试。');

  Map<String, dynamic> _toApiMessage(ChatMessage message) {
    if (!message.hasImages) {
      return {'role': message.role.name, 'content': message.content};
    }
    return {
      'role': message.role.name,
      'content': [
        {'type': 'text', 'text': message.content},
        ...message.imagePayloads.map(
          (image) => {
            'type': 'image_url',
            'image_url': {'url': 'data:image/jpeg;base64,$image'},
          },
        ),
      ],
    };
  }

  void dispose() {
    _cancelActive = null;
    _client.close();
  }
}
