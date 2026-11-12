import 'package:flutter_test/flutter_test.dart';
import 'package:question_solver/models/chat_message.dart';

void main() {
  test('image state is true only when a base64 payload is present', () {
    const textOnly = ChatMessage(role: MessageRole.user, content: '1 + 1 = ?');
    const photoQuestion = ChatMessage(
      role: MessageRole.user,
      content: '请解答图片中的题目',
      imageBase64: 'ZmFrZS1pbWFnZQ==',
    );

    expect(textOnly.hasImage, isFalse);
    expect(photoQuestion.hasImage, isTrue);
  });
}
