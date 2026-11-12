import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:question_solver/models/video_api_profile.dart';
import 'package:question_solver/models/video_job.dart';
import 'package:question_solver/services/video_store.dart';
import 'package:question_solver/services/video_studio_controller.dart';
import 'package:question_solver/video_studio_page.dart';
import 'package:question_solver/video_profiles_page.dart';
import 'video_api_service_test.dart' show profile;

class MemoryVideoStore extends VideoStore {
  List<VideoApiProfile> profiles = [
    profile(VideoProvider.ark),
    profile(VideoProvider.grok)
  ];
  List<VideoJob> jobs = [];
  @override
  Future<List<VideoApiProfile>> loadProfiles() async => profiles;
  @override
  Future<List<VideoJob>> loadJobs() async => jobs;
  @override
  Future<void> saveProfiles(List<VideoApiProfile> values) async {
    profiles = values;
  }

  @override
  Future<void> saveJobs(List<VideoJob> values) async {
    jobs = values;
  }
}

class CapturingVideoController extends VideoStudioController {
  CapturingVideoController({required super.store});
  VideoOptions? capturedOptions;
  VideoApiProfile? capturedProfile;
  String? capturedPrompt;
  @override
  Future<void> generate(
      {required VideoApiProfile profile,
      required String prompt,
      required VideoOptions options,
      String? image}) async {
    capturedProfile = profile;
    capturedPrompt = prompt;
    capturedOptions = options;
  }
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 160,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'phone form selects models and forwards chosen duration and prompt',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = CapturingVideoController(store: MemoryVideoStore());
    final boundary = GlobalKey();
    const screenshots = bool.fromEnvironment('VIDEO_STUDIO_SCREENSHOTS');
    if (screenshots) {
      await tester.runAsync(() async {
        final font = FontLoader('Microsoft YaHei')
          ..addFont(Future.value(ByteData.sublistView(
              await File('C:/Windows/Fonts/msyh.ttc').readAsBytes())));
        await font.load();
        final icons = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.sublistView(await File(
                  'D:/flutter_windows_3.44.8/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
              .readAsBytes())));
        await icons.load();
      });
    }
    await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            fontFamily: screenshots ? 'Microsoft YaHei' : null,
            colorSchemeSeed: const Color(0xffd39b6a)),
        home: RepaintBoundary(
            key: boundary, child: VideoStudioPage(controller: controller))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextField), '海边日落，镜头缓缓拉远，海浪声');
    await tester.pumpAndSettle();
    if (const bool.fromEnvironment('VIDEO_STUDIO_SCREENSHOTS')) {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await Directory('build/video-previews').create(recursive: true);
        await File('build/video-previews/create.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      });
    }
    await reveal(
        tester, find.widgetWithText(DropdownButtonFormField<int>, '视频时长'));
    await tester.tap(find.widgetWithText(DropdownButtonFormField<int>, '视频时长'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('30 秒'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('30 秒').last);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('生成视频'));
    await tester.tap(find.text('生成视频'));
    await tester.pumpAndSettle();
    expect(controller.capturedProfile!.model, 'doubao-seedance-2-5-260628');
    expect(controller.capturedOptions!.duration, 30);
    expect(controller.capturedPrompt, contains('海边日落'));
    expect(find.text('还没有视频任务，去创作你的第一段视频。'), findsOneWidget);
    await tester.tap(find.text('创作'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, 1400));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(DropdownButtonFormField<String>, '视频 API'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('xAI · Grok Imagine · grok-imagine-video').last);
    await tester.pumpAndSettle();
    await reveal(
        tester, find.widgetWithText(DropdownButtonFormField<String>, '分辨率'));
    await tester
        .tap(find.widgetWithText(DropdownButtonFormField<String>, '分辨率'));
    await tester.pumpAndSettle();
    expect(find.text('1080p'), findsNothing);
    await tester.tap(find.text('480p').last);
    await tester.pumpAndSettle();
    await reveal(tester, find.text('生成视频'));
    await tester.tap(find.text('生成视频'));
    await tester.pumpAndSettle();
    expect(controller.capturedProfile!.provider, VideoProvider.grok);
    expect(controller.capturedOptions!.duration, 5);
    expect(controller.capturedOptions!.resolution, '480p');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('provider presets save independent configuration with Grok 1.5',
      (tester) async {
    final store = MemoryVideoStore();
    final controller = VideoStudioController(store: store);
    await controller.load();
    await tester.pumpWidget(
        MaterialApp(home: VideoProfileEditor(controller: controller)));
    await tester.pumpAndSettle();
    await tester.tap(
        find.widgetWithText(DropdownButtonFormField<VideoProvider>, '服务商协议'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('xAI · Grok Imagine').last);
    await tester.pumpAndSettle();
    final keyField = find.widgetWithText(TextFormField, 'API Key');
    await reveal(tester, keyField);
    await tester.enterText(keyField, 'new-video-key');
    await reveal(
        tester, find.widgetWithText(ActionChip, 'grok-imagine-video-1.5'));
    await tester.tap(find.widgetWithText(ActionChip, 'grok-imagine-video-1.5'));
    await tester.pumpAndSettle();
    await reveal(tester, find.text('保存视频配置'));
    await tester.tap(find.text('保存视频配置'));
    await tester.pumpAndSettle();
    expect(store.profiles, hasLength(3));
    final saved = store.profiles.last;
    expect(saved.provider, VideoProvider.grok);
    expect(saved.model, 'grok-imagine-video-1.5');
    expect(saved.apiKey, 'new-video-key');
    expect(saved.endpoint(taskId: 'task').toString(),
        'https://api.x.ai/v1/videos/task');
    controller.dispose();
  });

  testWidgets('job view shows resume and local playback/export actions',
      (tester) async {
    final store = MemoryVideoStore();
    final pending = VideoJob(
        id: 'video-1',
        profileId: 'ark',
        provider: VideoProvider.ark,
        baseUrl: VideoProvider.ark.baseUrl,
        queryPath: VideoProvider.ark.queryPath,
        taskId: 'task-1',
        prompt: '森林中的小屋，清晨阳光透过树叶，镜头缓慢向前推进。',
        model: VideoProvider.ark.model,
        mode: '文生视频',
        createdAt: DateTime(2026, 10, 7, 18),
        duration: 10,
        ratio: '16:9',
        resolution: '720p',
        status: 'running');
    store.jobs = [
      pending,
      pending.copyWith(status: 'succeeded', localPath: 'example.mp4')
    ];
    final controller = VideoStudioController(store: store);
    await tester
        .pumpWidget(MaterialApp(home: VideoStudioPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('任务与作品'));
    await tester.pumpAndSettle();
    expect(find.text('继续查询 / 下载'), findsOneWidget);
    expect(find.text('播放视频'), findsOneWidget);
    expect(find.text('保存视频'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
