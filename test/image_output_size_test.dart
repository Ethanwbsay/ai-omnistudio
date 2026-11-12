import 'package:flutter_test/flutter_test.dart';
import 'package:question_solver/models/image_output_size.dart';

void main() {
  test('displayed aspect ratios agree with the dimensions sent to the API', () {
    for (final option
        in imageOutputSizes.entries.where((e) => e.key.isNotEmpty)) {
      final dimensions = option.key.split('x').map(int.parse).toList();
      final ratio =
          option.value.split(' · ').first.split(':').map(int.parse).toList();
      expect(dimensions[0] * ratio[1], dimensions[1] * ratio[0],
          reason: option.value);
    }
    expect(imageOutputSizes['1536x864'], startsWith('16:9'));
    expect(imageOutputSizes['864x1536'], startsWith('9:16'));
    expect(imageOutputSizes['1792x1024'], startsWith('7:4'));
  });
}
