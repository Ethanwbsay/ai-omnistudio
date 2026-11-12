import 'chat_message.dart';

class ChatSession {
  const ChatSession({
    required this.id,
    required this.characterId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String characterId;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  factory ChatSession.create({
    required String characterId,
    String? openingMessage,
  }) {
    final now = DateTime.now();
    final opening = openingMessage?.trim() ?? '';
    return ChatSession(
      id: 'session-${now.microsecondsSinceEpoch}',
      characterId: characterId,
      title: '新会话',
      createdAt: now,
      updatedAt: now,
      messages: opening.isEmpty
          ? const []
          : [ChatMessage(role: MessageRole.assistant, content: opening)],
    );
  }

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) =>
      ChatSession(
        id: id,
        characterId: characterId,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'characterId': characterId,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawMessages = json['messages'];
    return ChatSession(
      id: json['id']?.toString() ?? 'session-${now.microsecondsSinceEpoch}',
      characterId: json['characterId']?.toString() ?? '',
      title: json['title']?.toString() ?? '未命名会话',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? now,
      messages: rawMessages is List
          ? rawMessages
              .whereType<Map>()
              .map((item) =>
                  ChatMessage.fromJson(Map<String, dynamic>.from(item)))
              .toList()
          : const [],
    );
  }
}
