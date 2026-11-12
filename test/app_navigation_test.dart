import 'package:flutter_test/flutter_test.dart';
import 'package:question_solver/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opens video studio and provider presets from the home screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiOmnistudioApp());
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('视频工作台'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('视频工作台'), findsOneWidget);
    expect(find.text('任务与作品'), findsOneWidget);
  });
  testWidgets('opens the image studio from the app home screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const AiOmnistudioApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byTooltip('图片工作台'), findsOneWidget);
    await tester.tap(find.byTooltip('图片工作台'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('图片工作台'), findsOneWidget);
  });

  testWidgets('opens the solver assistant from the app home screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AiOmnistudioApp());
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('AI 万象工坊'), findsOneWidget);
    expect(find.byTooltip('搜题助手'), findsOneWidget);

    await tester.tap(find.byTooltip('搜题助手'));
    await tester.pumpAndSettle();
    expect(find.text('解题助手'), findsOneWidget);
  });

  testWidgets('opens the API configuration page from the app home screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const AiOmnistudioApp());
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byTooltip('API 配置'));
    await tester.pumpAndSettle();

    expect(find.text('API 配置'), findsOneWidget);
    expect(find.text('还没有 API 配置，请添加一个。'), findsOneWidget);

    await tester.tap(find.text('添加 API'));
    await tester.pumpAndSettle();
    expect(find.text('OpenAI 兼容接口'), findsOneWidget);
    expect(find.text('保存配置'), findsOneWidget);
  });
}
