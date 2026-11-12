import 'chat_message.dart';

class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  factory Conversation.create() {
    final now = DateTime.now();
    return Conversation(
      id: now.microsecondsSinceEpoch.toString(),
      title: '新对话',
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
  }

  Conversation copyWith({
    String? title,
    DateTime? updatedAt,
    List<ChatMessage>? messages,
  }) =>
      Conversation(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        messages: messages ?? this.messages,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((message) => message.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final rawMessages = json['messages'];
    return Conversation(
      id: json['id']?.toString() ?? now.microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? '未命名对话',
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
