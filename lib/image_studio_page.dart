import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'image_profiles_page.dart';
import 'models/api_profile.dart';
import 'models/image_api_profile.dart';
import 'models/image_artifact.dart';
import 'models/image_output_size.dart';
import 'models/image_reference_limits.dart';
import 'services/image_studio_controller.dart';
import 'widgets/image_mask_editor.dart';

class ImageStudioPage extends StatefulWidget {
  const ImageStudioPage(
      {super.key,
      this.chatProfiles = const [],
      this.controller,
      this.imagePicker});
  final List<ApiProfile> chatProfiles;
  final ImageStudioController? controller;
  final ImagePicker? imagePicker;

  @override
  State<ImageStudioPage> createState() => _ImageStudioPageState();
}

class _ImageStudioPageState extends State<ImageStudioPage>
    with SingleTickerProviderStateMixin {
  late final ImageStudioController _controller;
  late final TabController _tabs;
  late final ImagePicker _picker;
  final _prompt = TextEditingController();
  ImageTaskMode _mode = ImageTaskMode.textToImage;
  String? _profileId;
  String _size = '';
  String _quality = '';
  int _count = 1;
  final List<Uint8List> _references = [];
  Uint8List? _mask;
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? ImageStudioController();
    _picker = widget.imagePicker ?? ImagePicker();
    _tabs = TabController(length: 2, vsync: this);
    _controller.load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _prompt.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  ImageApiProfile? get _profile {
    for (final p in _controller.profiles) {
      if (p.id == _profileId) return p;
    }
    return _controller.profiles.isEmpty ? null : _controller.profiles.first;
  }

  bool get _locked => _controller.busy || _reading;

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _settings() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImageProfilesPage(
          controller: _controller, chatProfiles: widget.chatProfiles)));

  Future<void> _pick(ImageSource source) async {
    final available = ImageReferenceLimits.maxCount - _references.length;
    if (available <= 0) {
      _message('最多添加 ${ImageReferenceLimits.maxCount} 张参考图。');
      return;
    }
    setState(() => _reading = true);
    try {
      final List<XFile> selected;
      if (source == ImageSource.gallery) {
        selected =
            await _picker.pickMultiImage(maxWidth: 4096, maxHeight: 4096);
      } else {
        final image = await _picker.pickImage(
            source: source, maxWidth: 4096, maxHeight: 4096);
        selected = image == null ? [] : [image];
      }
      var failed = 0;
      var added = 0;
      var totalBytes =
          _references.fold<int>(0, (total, image) => total + image.length);
      for (final image in selected.take(available)) {
        try {
          if (await image.length() > ImageReferenceLimits.maxImageBytes) {
            throw const FormatException('图片过大');
          }
          final png = await _normalizeReference(await image.readAsBytes());
          if (!mounted) return;
          if (totalBytes + png.length > ImageReferenceLimits.maxTotalBytes) {
            throw const FormatException('总大小超过限制');
          }
          setState(() => _references.add(png));
          totalBytes += png.length;
          added++;
        } catch (_) {
          failed++;
        }
      }
      if (failed > 0 || selected.length > available) {
        _message('已添加 $added 张；部分图片无法读取或超过数量、大小限制。');
      }
    } catch (_) {
      _message('图片读取失败，请检查权限或重新选择图片。');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<Uint8List> _normalizeReference(Uint8List bytes) async {
    if (bytes.length > ImageReferenceLimits.maxImageBytes) {
      throw const FormatException('图片过大');
    }
    // Normalize input to PNG so uploaded MIME, mask dimensions and preview agree.
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
    frame.image.dispose();
    if (png == null || png.lengthInBytes > ImageReferenceLimits.maxImageBytes) {
      throw const FormatException('图片过大');
    }
    return png.buffer.asUint8List();
  }

  Future<void> _editMask() async {
    final mask = await Navigator.of(context).push<Uint8List>(MaterialPageRoute(
        builder: (_) => ImageMaskEditor(image: _references.first)));
    if (mounted && mask != null) setState(() => _mask = mask);
  }

  Future<void> _generate() async {
    final profile = _profile;
    if (profile == null) {
      _settings();
      return;
    }
    if (_prompt.text.trim().isEmpty) {
      _message('请填写图片提示词。');
      return;
    }
    if (_mode != ImageTaskMode.textToImage && _references.isEmpty) {
      _message('请先选择参考图片。');
      return;
    }
    final before = _controller.history.length;
    FocusScope.of(context).unfocus();
    await _controller.generate(
        profile: profile,
        mode: _mode,
        prompt: _prompt.text.trim(),
        size: _size,
        quality: _quality,
        count: _count,
        images: _mode == ImageTaskMode.textToImage
            ? const []
            : List.of(_references),
        mask: _mode == ImageTaskMode.edit ? _mask : null);
    if (mounted && _controller.history.length > before) _tabs.animateTo(1);
  }

  Future<void> _retryDownload() async {
    final before = _controller.history.length;
    await _controller.retryPendingDownload();
    if (mounted && _controller.history.length > before) _tabs.animateTo(1);
  }

  Future<void> _discardDownload() async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('放弃待下载图片？'),
                content: const Text('图片已由模型生成。放弃后重新生成会再次调用模型。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('保留')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('放弃')),
                ]));
    if (confirmed == true) _controller.discardPendingDownload();
  }

  Future<void> _reuse(ImageArtifact item, ImageTaskMode mode) async {
    setState(() => _reading = true);
    try {
      final png =
          await _normalizeReference(await File(item.path).readAsBytes());
      if (mounted) {
        setState(() {
          _references
            ..clear()
            ..add(png);
          _mask = null;
          _mode = mode;
          _prompt.clear();
        });
        _tabs.animateTo(0);
      }
    } catch (_) {
      _message('原图片读取失败。');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _delete(ImageArtifact item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除这张图片？'),
                content: const Text('将删除本地图片和历史记录。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除')),
                ]));
    if (confirmed != true) return;
    try {
      await _controller.deleteArtifact(item);
    } catch (_) {
      _message('删除图片失败，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
            appBar: AppBar(
                title: const Text('图片工作台'),
                actions: [
                  IconButton(
                      tooltip: '图片 API 配置',
                      onPressed:
                          _locked || !_controller.ready ? null : _settings,
                      icon: const Icon(Icons.tune)),
                ],
                bottom: TabBar(
                    controller: _tabs,
                    tabs: const [Tab(text: '创作'), Tab(text: '作品')])),
            body: _controller.loading
                ? const Center(child: CircularProgressIndicator())
                : !_controller.ready
                    ? Center(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_controller.error ?? '读取失败'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: _controller.load,
                            icon: const Icon(Icons.refresh),
                            label: const Text('重新读取')),
                      ]))
                    : Column(children: [
                        if (_controller.busy) ...[
                          const LinearProgressIndicator(),
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(children: [
                                Expanded(
                                    child: Text(
                                        '${_controller.stage.label}\n已等待 '
                                        '${_controller.elapsedSeconds ~/ 60} 分 ${_controller.elapsedSeconds % 60} 秒')),
                                TextButton.icon(
                                    onPressed: _controller.cancel,
                                    icon: const Icon(Icons.stop),
                                    label: const Text('停止')),
                              ])),
                        ],
                        if (_controller.error != null)
                          Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(Icons.error_outline,
                                        color: Colors.redAccent),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: SelectableText(
                                            _controller.error!,
                                            style: const TextStyle(
                                                color: Colors.redAccent))),
                                    IconButton(
                                        tooltip: '复制错误信息',
                                        onPressed: () => Clipboard.setData(
                                            ClipboardData(
                                                text: _controller.error!)),
                                        icon: const Icon(Icons.copy, size: 18)),
                                  ])),
                        if (_controller.canRetryDownload && !_controller.busy)
                          Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Wrap(spacing: 8, children: [
                                FilledButton.icon(
                                    onPressed: _retryDownload,
                                    icon: const Icon(Icons.download_outlined),
                                    label: const Text('仅重试下载')),
                                TextButton(
                                    onPressed: _discardDownload,
                                    child: const Text('放弃下载')),
                              ])),
                        Expanded(
                            child: TabBarView(
                                controller: _tabs,
                                children: [_creation(), _gallery()])),
                      ]),
          ));

  Widget _creation() => LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final form = _form();
        if (!wide) {
          return ListView(padding: const EdgeInsets.all(16), children: form);
        }
        return Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1200),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                          width: 440,
                          child: ListView(
                              padding: const EdgeInsets.all(24),
                              children: form)),
                      const VerticalDivider(width: 1),
                      Expanded(
                          child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: _controller.history.isEmpty
                                  ? Center(
                                      child: _references.isEmpty
                                          ? const Icon(Icons.image_outlined,
                                              size: 80, color: Colors.white24)
                                          : Image.memory(_references.first,
                                              fit: BoxFit.contain))
                                  : _artifactPreview(
                                      _controller.history.first))),
                    ])));
      });

  List<Widget> _form() => [
        SegmentedButton<ImageTaskMode>(
            showSelectedIcon: false,
            segments: ImageTaskMode.values
                .map((mode) =>
                    ButtonSegment(value: mode, label: Text(mode.label)))
                .toList(),
            selected: {_mode},
            onSelectionChanged:
                _locked ? null : (v) => setState(() => _mode = v.single)),
        const SizedBox(height: 20),
        if (_controller.profiles.isEmpty)
          OutlinedButton.icon(
              onPressed: _locked ? null : _settings,
              icon: const Icon(Icons.add),
              label: const Text('添加图片 API'))
        else
          DropdownButtonFormField<String>(
              key: ValueKey(_profile?.id),
              initialValue: _profile?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: '图片 API', border: OutlineInputBorder()),
              items: _controller.profiles
                  .map((p) => DropdownMenuItem(
                      value: p.id,
                      child: Text('${p.name} · ${p.model}',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged:
                  _locked ? null : (id) => setState(() => _profileId = id)),
        const SizedBox(height: 16),
        TextField(
            controller: _prompt,
            enabled: !_locked,
            minLines: 4,
            maxLines: 8,
            maxLength: 32000,
            decoration: InputDecoration(
                labelText:
                    _mode == ImageTaskMode.textToImage ? '图片提示词' : '修改要求',
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
                counterText: '')),
        if (_mode != ImageTaskMode.textToImage) ...[
          const SizedBox(height: 16),
          if (_references.isNotEmpty) ...[
            Text(
                '参考图片（${_references.length}/${ImageReferenceLimits.maxCount}）'),
            const SizedBox(height: 8),
            _referenceThumbnails(),
            const SizedBox(height: 8),
            const Text('第一张为底图；其他图片用于提供人物、风格或内容参考。',
                style: TextStyle(fontSize: 12, color: Colors.white60)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
                onPressed: _locked ||
                        _references.length >= ImageReferenceLimits.maxCount
                    ? null
                    : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(_references.isEmpty ? '选择参考图' : '添加参考图')),
            if (Platform.isAndroid || Platform.isIOS)
              IconButton(
                  tooltip: '拍照',
                  onPressed: _locked ||
                          _references.length >= ImageReferenceLimits.maxCount
                      ? null
                      : () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined)),
            if (_references.isNotEmpty)
              IconButton(
                  tooltip: '清空参考图',
                  icon: const Icon(Icons.close),
                  onPressed: _locked
                      ? null
                      : () => setState(() {
                            _references.clear();
                            _mask = null;
                          })),
          ]),
          if (_mode == ImageTaskMode.edit && _references.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: _locked ? null : _editMask,
                  icon: const Icon(Icons.brush_outlined),
                  label: Text(_mask == null ? '涂抹编辑区域' : '重新涂抹区域')),
              if (_mask != null)
                IconButton(
                    tooltip: '清除编辑区域',
                    onPressed:
                        _locked ? null : () => setState(() => _mask = null),
                    icon: const Icon(Icons.layers_clear_outlined)),
            ]),
            Text(_mask == null ? '编辑范围：底图整张图片' : '编辑范围：底图已涂抹区域',
                style: const TextStyle(color: Colors.white60)),
          ],
        ],
        const SizedBox(height: 16),
        _option('输出比例 / 分辨率', _size, imageOutputSizes,
            (v) => setState(() => _size = v)),
        const SizedBox(height: 6),
        const Text('可用比例和分辨率取决于所选模型。',
            style: TextStyle(fontSize: 12, color: Colors.white60)),
        const SizedBox(height: 16),
        _option(
            '画质',
            _quality,
            const {
              '': '模型默认',
              'low': '低',
              'medium': '中',
              'high': '高',
              'standard': '标准',
              'hd': 'HD'
            },
            (v) => setState(() => _quality = v)),
        const SizedBox(height: 8),
        Row(children: [
          const Expanded(child: Text('生成数量')),
          IconButton(
              tooltip: '减少数量',
              onPressed: _locked || _count <= 1
                  ? null
                  : () => setState(() => _count--),
              icon: const Icon(Icons.remove)),
          SizedBox(
              width: 28, child: Text('$_count', textAlign: TextAlign.center)),
          IconButton(
              tooltip: '增加数量',
              onPressed: _locked || _count >= 4
                  ? null
                  : () => setState(() => _count++),
              icon: const Icon(Icons.add)),
        ]),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed:
                _locked || _controller.canRetryDownload ? null : _generate,
            icon: const Icon(Icons.auto_awesome),
            label: Text(_reading
                ? '读取图片中'
                : _controller.busy
                    ? '生成中'
                    : '生成图片')),
        const SizedBox(height: 24),
      ];

  Widget _referenceThumbnails() => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: List.generate(
            _references.length,
            (index) => SizedBox(
                  width: 132,
                  height: 152,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                            color: index == 0
                                ? Theme.of(context).colorScheme.primary
                                : Colors.white24)),
                    child: Column(children: [
                      Expanded(
                          child: Stack(fit: StackFit.expand, children: [
                        InkWell(
                            onTap: () => showDialog<void>(
                                context: context,
                                builder: (context) => Dialog(
                                    child: SizedBox(
                                        height:
                                            MediaQuery.sizeOf(context).height *
                                                .65,
                                        child: InteractiveViewer(
                                            minScale: .5,
                                            maxScale: 8,
                                            child: Center(
                                                child: Image.memory(
                                                    _references[index],
                                                    fit: BoxFit.contain)))))),
                            child: Image.memory(_references[index],
                                fit: BoxFit.contain)),
                        Positioned(
                            left: 6,
                            top: 6,
                            child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(6)),
                                child: Text(
                                    index == 0 ? '1 · 底图' : '${index + 1}'))),
                        Positioned(
                            right: 0,
                            top: 0,
                            child: IconButton(
                                tooltip: '移除参考图 ${index + 1}',
                                style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54),
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: _locked
                                    ? null
                                    : () => setState(() {
                                          _references.removeAt(index);
                                          if (index == 0) _mask = null;
                                        }))),
                      ])),
                      SizedBox(
                          height: 40,
                          child: index == 0
                              ? const Center(
                                  child: Text('当前底图',
                                      style: TextStyle(fontSize: 12)))
                              : TextButton(
                                  onPressed: _locked
                                      ? null
                                      : () => setState(() {
                                            final selected =
                                                _references.removeAt(index);
                                            _references.insert(0, selected);
                                            _mask = null;
                                          }),
                                  child: const Text('设为底图',
                                      style: TextStyle(fontSize: 12)))),
                    ]),
                  ),
                )),
      );

  Widget _option(String label, String value, Map<String, String> options,
          ValueChanged<String> change) =>
      DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
          items: options.entries
              .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
              .toList(),
          onChanged: _locked ? null : (v) => change(v!));

  Widget _gallery() => _controller.history.isEmpty
      ? const Center(
          child:
              Icon(Icons.collections_outlined, size: 72, color: Colors.white24))
      : GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              mainAxisExtent: 340,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16),
          itemCount: _controller.history.length,
          itemBuilder: (context, index) =>
              _artifactPreview(_controller.history[index]));

  Widget _artifactPreview(ImageArtifact item) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: SizedBox(
                width: double.infinity,
                child: InkWell(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ImageResultPage(item: item))),
                    child: Image.file(File(item.path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) => const Center(
                            child: Icon(Icons.broken_image_outlined)))))),
        const SizedBox(height: 8),
        Text(item.prompt, maxLines: 2, overflow: TextOverflow.ellipsis),
        Text('${item.mode} · ${item.model}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.white60)),
        Row(children: [
          IconButton(
              tooltip: '保存图片',
              onPressed: () => exportImage(context, item),
              icon: const Icon(Icons.download_outlined)),
          IconButton(
              tooltip: '用作参考图',
              onPressed: _locked
                  ? null
                  : () => _reuse(item, ImageTaskMode.imageToImage),
              icon: const Icon(Icons.add_photo_alternate_outlined)),
          IconButton(
              tooltip: '编辑图片',
              onPressed:
                  _locked ? null : () => _reuse(item, ImageTaskMode.edit),
              icon: const Icon(Icons.edit_outlined)),
          IconButton(
              tooltip: '删除图片',
              onPressed: _locked ? null : () => _delete(item),
              icon: const Icon(Icons.delete_outline)),
        ]),
      ]);
}

Future<void> exportImage(BuildContext context, ImageArtifact item) async {
  try {
    final bytes = await File(item.path).readAsBytes();
    final name = item.path.split(RegExp(r'[/\\]')).last;
    final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存图片',
        fileName: name,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [name.split('.').last]);
    if (path == null) return;
    // On mobile the system document picker writes bytes; desktop returns a path.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      await File(path).writeAsBytes(bytes, flush: true);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('图片已保存。')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('图片导出失败，请重试。')));
    }
  }
}

class ImageResultPage extends StatelessWidget {
  const ImageResultPage({super.key, required this.item});
  final ImageArtifact item;

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('图片预览'), actions: [
        IconButton(
            tooltip: '复制提示词',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: item.prompt));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('提示词已复制。')));
              }
            }),
        IconButton(
            tooltip: '保存图片',
            icon: const Icon(Icons.download_outlined),
            onPressed: () => exportImage(context, item)),
      ]),
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: InteractiveViewer(
                minScale: .5,
                maxScale: 8,
                child: Center(
                    child: Image.file(File(item.path),
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) =>
                            const Text('本地图片不存在或已损坏。'))))),
        SizedBox(
            height: 130,
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${item.mode} · ${item.model} · ${item.createdAt.toLocal().toString().split('.').first}',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 12)),
                      const SizedBox(height: 8),
                      SelectableText(item.prompt),
                      if (item.revisedPrompt.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        SelectableText(item.revisedPrompt)
                      ],
                    ]))),
      ])));
}
