enum MessageRole { user, assistant }

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.imagesBase64 = const [],
    this.imageBase64,
  });

  final MessageRole role;
  final String content;
  final List<String> imagesBase64;
  // Retained only to read messages created by the first single-image version.
  final String? imageBase64;

  List<String> get imagePayloads => imagesBase64.isNotEmpty
      ? imagesBase64
      : imageBase64 == null || imageBase64!.isEmpty
          ? const []
          : [imageBase64!];

  bool get hasImage => imagePayloads.isNotEmpty;
  bool get hasImages => imagePayloads.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        'images': imagePayloads,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final savedImages = json['images'];
    final images = savedImages is List
        ? savedImages
            .whereType<String>()
            .where((image) => image.isNotEmpty)
            .toList()
        : const <String>[];
    return ChatMessage(
      role: json['role'] == MessageRole.assistant.name
          ? MessageRole.assistant
          : MessageRole.user,
      content: json['content']?.toString() ?? '',
      imagesBase64: images,
      imageBase64: images.isEmpty ? json['imageBase64']?.toString() : null,
    );
  }
}
