class ApiProfile {
  const ApiProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.8,
    this.maxTokens = 2048,
  });

  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final int maxTokens;

  bool get isComplete =>
      name.trim().isNotEmpty &&
      baseUrl.trim().isNotEmpty &&
      apiKey.trim().isNotEmpty &&
      model.trim().isNotEmpty &&
      temperature.isFinite &&
      temperature >= 0 &&
      temperature <= 2 &&
      maxTokens > 0;

  String get chatCompletionsUrl {
    final normalized = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return normalized.endsWith('/chat/completions')
        ? normalized
        : '$normalized/chat/completions';
  }

  ApiProfile copyWith({
    String? name,
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    int? maxTokens,
  }) =>
      ApiProfile(
        id: id,
        name: name ?? this.name,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        maxTokens: maxTokens ?? this.maxTokens,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'temperature': temperature,
        'maxTokens': maxTokens,
      };

  factory ApiProfile.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now().microsecondsSinceEpoch.toString();
    final rawTemperature = json['temperature'];
    final rawMaxTokens = json['maxTokens'];
    return ApiProfile(
      id: json['id']?.toString() ?? 'api-$now',
      name: json['name']?.toString() ?? '未命名 API',
      baseUrl: json['baseUrl']?.toString() ?? '',
      apiKey: json['apiKey']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
      temperature: rawTemperature is num ? rawTemperature.toDouble() : 0.8,
      maxTokens: rawMaxTokens is num ? rawMaxTokens.toInt() : 2048,
    );
  }
}
