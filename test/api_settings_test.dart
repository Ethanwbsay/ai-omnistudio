import 'package:flutter_test/flutter_test.dart';
import 'package:question_solver/models/api_settings.dart';

void main() {
  test('adds the chat completions path to a v1 base URL', () {
    const settings = ApiSettings(
        baseUrl: 'https://example.com/v1/', apiKey: 'key', model: 'model');
    expect(
        settings.chatCompletionsUrl, 'https://example.com/v1/chat/completions');
  });

  test('keeps a fully specified chat completions URL', () {
    const settings = ApiSettings(
        baseUrl: 'https://example.com/v1/chat/completions',
        apiKey: 'key',
        model: 'model');
    expect(
        settings.chatCompletionsUrl, 'https://example.com/v1/chat/completions');
  });
}
