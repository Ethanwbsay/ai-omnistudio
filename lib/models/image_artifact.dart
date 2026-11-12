class ImageArtifact {
  const ImageArtifact(
      {required this.id,
      required this.path,
      required this.prompt,
      required this.model,
      required this.mode,
      required this.createdAt,
      this.revisedPrompt = ''});

  final String id;
  final String path;
  final String prompt;
  final String model;
  final String mode;
  final DateTime createdAt;
  final String revisedPrompt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'prompt': prompt,
        'model': model,
        'mode': mode,
        'createdAt': createdAt.toIso8601String(),
        'revisedPrompt': revisedPrompt,
      };

  factory ImageArtifact.fromJson(Map<String, dynamic> json) => ImageArtifact(
        id: json['id'] as String,
        path: json['path'] as String,
        prompt: json['prompt'] as String,
        model: json['model'] as String,
        mode: json['mode'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        revisedPrompt: json['revisedPrompt'] as String? ?? '',
      );
}
