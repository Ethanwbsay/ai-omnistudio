class UserPersona {
  const UserPersona({
    this.nickname = '我',
    this.identity = '',
    this.preferences = '',
    this.customPrompt = '',
  });

  final String nickname;
  final String identity;
  final String preferences;
  final String customPrompt;

  UserPersona copyWith({
    String? nickname,
    String? identity,
    String? preferences,
    String? customPrompt,
  }) =>
      UserPersona(
        nickname: nickname ?? this.nickname,
        identity: identity ?? this.identity,
        preferences: preferences ?? this.preferences,
        customPrompt: customPrompt ?? this.customPrompt,
      );

  Map<String, dynamic> toJson() => {
        'nickname': nickname,
        'identity': identity,
        'preferences': preferences,
        'customPrompt': customPrompt,
      };

  factory UserPersona.fromJson(Map<String, dynamic> json) => UserPersona(
        nickname: json['nickname']?.toString() ?? '我',
        identity: json['identity']?.toString() ?? '',
        preferences: json['preferences']?.toString() ?? '',
        customPrompt: json['customPrompt']?.toString() ?? '',
      );
}
