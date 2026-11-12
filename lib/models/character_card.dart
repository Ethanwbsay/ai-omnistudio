class CharacterCard {
  const CharacterCard({
    required this.id,
    required this.name,
    required this.avatarPath,
    required this.description,
    required this.personality,
    required this.background,
    required this.openingMessage,
    required this.exampleDialogue,
    required this.systemPrompt,
    required this.apiProfileId,
  });

  final String id;
  final String name;
  final String avatarPath;
  final String description;
  final String personality;
  final String background;
  final String openingMessage;
  final String exampleDialogue;
  final String systemPrompt;
  final String apiProfileId;

  bool get isComplete =>
      name.trim().isNotEmpty &&
      personality.trim().isNotEmpty &&
      apiProfileId.trim().isNotEmpty;

  CharacterCard copyWith({
    String? name,
    String? avatarPath,
    String? description,
    String? personality,
    String? background,
    String? openingMessage,
    String? exampleDialogue,
    String? systemPrompt,
    String? apiProfileId,
  }) =>
      CharacterCard(
        id: id,
        name: name ?? this.name,
        avatarPath: avatarPath ?? this.avatarPath,
        description: description ?? this.description,
        personality: personality ?? this.personality,
        background: background ?? this.background,
        openingMessage: openingMessage ?? this.openingMessage,
        exampleDialogue: exampleDialogue ?? this.exampleDialogue,
        systemPrompt: systemPrompt ?? this.systemPrompt,
        apiProfileId: apiProfileId ?? this.apiProfileId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'avatarPath': avatarPath,
        'description': description,
        'personality': personality,
        'background': background,
        'openingMessage': openingMessage,
        'exampleDialogue': exampleDialogue,
        'systemPrompt': systemPrompt,
        'apiProfileId': apiProfileId,
      };

  factory CharacterCard.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    return CharacterCard(
      id: json['id']?.toString() ?? 'character-$now',
      name: json['name']?.toString() ?? '',
      avatarPath: json['avatarPath']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      personality: json['personality']?.toString() ?? '',
      background: json['background']?.toString() ?? '',
      openingMessage: json['openingMessage']?.toString() ?? '',
      exampleDialogue: json['exampleDialogue']?.toString() ?? '',
      systemPrompt: json['systemPrompt']?.toString() ?? '',
      apiProfileId: json['apiProfileId']?.toString() ?? '',
    );
  }
}
