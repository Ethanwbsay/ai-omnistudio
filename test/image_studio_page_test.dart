import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:question_solver/image_studio_page.dart';
import 'package:question_solver/image_profiles_page.dart';
import 'package:question_solver/models/image_api_profile.dart';
import 'package:question_solver/models/image_artifact.dart';
import 'package:question_solver/services/image_store.dart';
import 'package:question_solver/services/image_api_service.dart';
import 'package:question_solver/services/image_studio_controller.dart';
import 'package:question_solver/widgets/image_mask_editor.dart';

import 'image_api_service_test.dart' show imageProfile;

Future<void> finishImageIo(WidgetTester tester) async {
  // Native image decoding and file I/O need real event-loop turns between frames.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  }
  await tester.pumpAndSettle();
}

Future<void> revealStudioControl(WidgetTester tester, Finder target,
    {double step = 150}) async {
  await tester.scrollUntilVisible(target, step,
      scrollable: find
          .descendant(
              of: find.byType(ListView).first,
              matching: find.byType(Scrollable))
          .first);
  await tester.pumpAndSettle();
}

class MemoryImageStore extends ImageStore {
  MemoryImageStore({super.directory});
  List<ImageApiProfile> profiles = [imageProfile];
  List<ImageArtifact> artifacts = [];
  @override
  Future<List<ImageApiProfile>> loadProfiles() async => profiles;
  @override
  Future<List<ImageArtifact>> loadHistory() async => artifacts;
  @override
  Future<void> saveHistory(List<ImageArtifact> values) async {
    artifacts = values;
  }

  @override
  Future<void> saveProfiles(List<ImageApiProfile> values) async {
    profiles = values;
  }
}

class QueuedImagePicker extends ImagePicker {
  QueuedImagePicker(this.selections);
  final List<List<XFile>> selections;
  int multiPickCalls = 0;

  @override
  Future<List<XFile>> pickMultiImage(
      {double? maxWidth,
      double? maxHeight,
      int? imageQuality,
      int? limit,
      bool requestFullMetadata = true}) async {
    multiPickCalls++;
    return selections.removeAt(0);
  }
}

void main() {
  const screenshots = bool.fromEnvironment('IMAGE_STUDIO_SCREENSHOTS');

  testWidgets(
      'download failure offers a download-only retry on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('image-studio-retry-')))!;
    final png = (await tester.runAsync(() => renderImageMask(16, 16, [])))!;
    var posts = 0, gets = 0;
    final store = MemoryImageStore(directory: dir);
    final controller = ImageStudioController(
        store: store,
        service: ImageApiService(
            clientFactory: () => MockClient((request) async {
                  if (request.method == 'POST') {
                    posts++;
                    return http.Response(
                        jsonEncode({
                          'data': [
                            {'url': 'https://cdn.test/image.png'}
                          ]
                        }),
                        200);
                  }
                  return ++gets == 1
                      ? http.Response('unavailable', 503)
                      : http.Response.bytes(png, 200);
                })));
    await tester
        .pumpWidget(MaterialApp(home: ImageStudioPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'original prompt');
    await revealStudioControl(tester, find.text('生成图片'));
    await tester.tap(find.text('生成图片'));
    await finishImageIo(tester);
    expect(find.text('仅重试下载'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('仅重试下载'));
    await finishImageIo(tester);
    expect(find.text('仅重试下载'), findsNothing);
    expect(store.artifacts, hasLength(1));
    expect(store.artifacts.single.prompt, 'original prompt');
    expect(posts, 1);
    expect(gets, 2);
    await tester.pumpWidget(const SizedBox());
    await finishImageIo(tester);
    controller.dispose();
    await tester.runAsync(() async {
      expect(dir.absolute.path, startsWith(Directory.systemTemp.absolute.path));
      expect(dir.path.split(Platform.pathSeparator).last,
          startsWith('image-studio-retry-'));
      await dir.delete(recursive: true);
    });
  });

  testWidgets('image API editor persists longer generation waits',
      (tester) async {
    final store = MemoryImageStore();
    final controller = ImageStudioController(store: store);
    await controller.load();
    await tester.pumpWidget(MaterialApp(
        home:
            ImageProfileEditor(controller: controller, initial: imageProfile)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('接口选项'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('接口选项'));
    await tester.pumpAndSettle();
    final timeoutField = find.widgetWithText(TextFormField, '生成最长等待时间（分钟）');
    await tester.ensureVisible(timeoutField);
    await tester.enterText(timeoutField, '20');
    final responseModeField =
        find.widgetWithText(DropdownButtonFormField<String>, '接收方式');
    await tester.ensureVisible(responseModeField);
    await tester.tap(responseModeField);
    await tester.pumpAndSettle();
    await tester.tap(find.text('普通 JSON').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('保存图片配置'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView), matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('保存图片配置'));
    await tester.pumpAndSettle();
    expect(store.profiles.single.generationTimeoutMinutes, 20);
    expect(store.profiles.single.responseMode, 'json');
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });

  testWidgets('generated artwork can be reused with a painted edit mask',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dir = (await tester
        .runAsync(() => Directory.systemTemp.createTemp('image-studio-ui-')))!;
    final png = (await tester.runAsync(() => renderImageMask(120, 60, [])))!;
    final secondPng =
        (await tester.runAsync(() => renderImageMask(60, 120, [])))!;
    final picker = QueuedImagePicker([
      [
        XFile.fromData(png, name: 'reference-a.png'),
        XFile.fromData(secondPng, name: 'reference-b.png')
      ],
      [],
    ]);
    final store = MemoryImageStore(directory: dir);
    final requests = <http.Request>[];
    final controller = ImageStudioController(
        store: store,
        service: ImageApiService(
            clientFactory: () => MockClient((request) async {
                  requests.add(request);
                  return http.Response(
                      jsonEncode({
                        'data': [
                          {'b64_json': base64Encode(png)}
                        ]
                      }),
                      200);
                })));
    await tester.pumpWidget(MaterialApp(
        home: ImageStudioPage(controller: controller, imagePicker: picker)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'a landscape');
    await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, '输出比例 / 分辨率'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('16:9 · 1536 × 864').last);
    await tester.pumpAndSettle();
    await revealStudioControl(tester, find.text('生成图片'));
    await tester.tap(find.text('生成图片'));
    await finishImageIo(tester);
    expect(controller.error, isNull);
    expect(jsonDecode(requests.first.body)['size'], '1536x864');
    expect(store.artifacts, hasLength(1));
    expect(find.byTooltip('编辑图片'), findsOneWidget);
    await tester.tap(find.byTooltip('编辑图片'));
    await finishImageIo(tester);
    expect(find.text('编辑范围：底图整张图片'), findsOneWidget);
    await tester.tap(find.text('涂抹编辑区域'));
    await finishImageIo(tester);
    final paint = find
        .descendant(
            of: find.byType(GestureDetector),
            matching: find.byType(CustomPaint))
        .first;
    await tester.dragFrom(tester.getCenter(paint), const Offset(40, 0));
    await tester.pump();
    await tester.tap(find.text('确认区域'));
    await finishImageIo(tester);
    expect(find.text('编辑范围：底图已涂抹区域'), findsOneWidget);
    await tester.tap(find.text('添加参考图'));
    await finishImageIo(tester);
    expect(find.text('参考图片（3/16）'), findsOneWidget);
    expect(picker.multiPickCalls, 1);
    await revealStudioControl(tester, find.text('编辑范围：底图已涂抹区域'));
    expect(find.text('编辑范围：底图已涂抹区域'), findsOneWidget);
    await tester.ensureVisible(find.text('添加参考图'));
    await tester.tap(find.text('添加参考图'));
    await finishImageIo(tester);
    await revealStudioControl(tester, find.text('参考图片（3/16）'), step: -150);
    expect(find.text('参考图片（3/16）'), findsOneWidget);
    // Changing the base image invalidates the mask, while removing an auxiliary
    // reference leaves the base and its freshly drawn mask intact.
    await tester.tap(find.text('设为底图').first);
    await tester.pumpAndSettle();
    await revealStudioControl(tester, find.text('编辑范围：底图整张图片'));
    expect(find.text('编辑范围：底图整张图片'), findsOneWidget);
    await tester.ensureVisible(find.text('涂抹编辑区域'));
    await tester.tap(find.text('涂抹编辑区域'));
    await finishImageIo(tester);
    final newPaint = find
        .descendant(
            of: find.byType(GestureDetector),
            matching: find.byType(CustomPaint))
        .first;
    await tester.dragFrom(tester.getCenter(newPaint), const Offset(30, 0));
    await tester.pump();
    await tester.tap(find.text('确认区域'));
    await finishImageIo(tester);
    await revealStudioControl(tester, find.byTooltip('移除参考图 3'), step: -150);
    await tester.tap(find.byTooltip('移除参考图 3'));
    await tester.pumpAndSettle();
    expect(find.text('参考图片（2/16）'), findsOneWidget);
    await revealStudioControl(tester, find.text('编辑范围：底图已涂抹区域'));
    expect(find.text('编辑范围：底图已涂抹区域'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'replace the sky');
    await tester.scrollUntilVisible(find.text('生成图片'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('生成图片'));
    await finishImageIo(tester);
    expect(controller.error, isNull);
    expect(store.artifacts, hasLength(2));
    expect(requests, hasLength(2));
    expect(requests.last.url.path, '/v1/images/edits');
    expect(
        RegExp('name="image\\[\\]"; filename=')
            .allMatches(latin1.decode(requests.last.bodyBytes)),
        hasLength(2));
    expect(latin1.decode(requests.last.bodyBytes),
        contains('name="mask"; filename="mask.png"'));
    await tester.pumpWidget(const SizedBox());
    await finishImageIo(tester);
    controller.dispose();
    await tester.runAsync(() async {
      expect(dir.absolute.path, startsWith(Directory.systemTemp.absolute.path));
      expect(dir.path.split(Platform.pathSeparator).last,
          startsWith('image-studio-ui-'));
      await dir.delete(recursive: true);
    });
  });

  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(1280, 800)
  ]) {
    testWidgets(
        'image studio modes and settings fit ${size.width} x ${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
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
      final controller = ImageStudioController(store: MemoryImageStore());
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                  brightness: Brightness.dark,
                  useMaterial3: true,
                  fontFamily: screenshots ? 'Microsoft YaHei' : null,
                  colorSchemeSeed: const Color(0xffd39b6a),
                  scaffoldBackgroundColor: const Color(0xff171418)),
              home: ImageStudioPage(controller: controller))));
      await tester.pumpAndSettle();
      expect(find.text('文生图'), findsOneWidget);
      expect(find.text('图片提示词'), findsOneWidget);
      await tester.tap(
          find.widgetWithText(DropdownButtonFormField<String>, '输出比例 / 分辨率'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('16:9 · 1536 × 864').last);
      await tester.pumpAndSettle();
      expect(find.text('16:9 · 1536 × 864').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);

      if (screenshots) {
        await tester.runAsync(() async {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes =
              (await image.toByteData(format: ui.ImageByteFormat.png))!
                  .buffer
                  .asUint8List();
          final dir = Directory('build/image_studio_previews');
          await dir.create(recursive: true);
          await File('${dir.path}/studio-${size.width.toInt()}.png')
              .writeAsBytes(bytes);
          image.dispose();
        });
      }

      await tester.tap(find.text('图生图'));
      await tester.pumpAndSettle();
      expect(find.text('选择参考图'), findsOneWidget);
      expect(find.text('修改要求'), findsOneWidget);
      await tester.tap(find.text('图片编辑'));
      await tester.pumpAndSettle();
      expect(find.text('选择参考图'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('图片 API 配置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加图片 API'));
      await tester.pumpAndSettle();
      expect(find.text('图片模型名称'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    });
  }

  testWidgets('missing prompts and references do not start image requests',
      (tester) async {
    final controller = ImageStudioController(store: MemoryImageStore());
    await tester
        .pumpWidget(MaterialApp(home: ImageStudioPage(controller: controller)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('生成图片'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('生成图片'));
    await tester.pumpAndSettle();
    expect(find.text('请填写图片提示词。'), findsOneWidget);
    expect(controller.busy, isFalse);
    await tester.enterText(find.byType(TextField), 'change the sky');
    await tester.scrollUntilVisible(find.text('图生图'), -200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('图生图'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('生成图片'), 200,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('生成图片'));
    await tester.pumpAndSettle();
    expect(find.text('请先选择参考图片。'), findsOneWidget);
    expect(controller.busy, isFalse);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}
