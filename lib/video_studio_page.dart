import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'models/api_profile.dart';
import 'models/video_api_profile.dart';
import 'models/video_job.dart';
import 'services/video_studio_controller.dart';
import 'video_profiles_page.dart';
import 'widgets/local_video_player.dart';

class VideoStudioPage extends StatefulWidget {
  const VideoStudioPage(
      {super.key,
      this.chatProfiles = const [],
      this.controller,
      this.imagePicker});
  final List<ApiProfile> chatProfiles;
  final VideoStudioController? controller;
  final ImagePicker? imagePicker;
  @override
  State<VideoStudioPage> createState() => _VideoStudioPageState();
}

class _VideoStudioPageState extends State<VideoStudioPage>
    with SingleTickerProviderStateMixin {
  late final VideoStudioController _controller;
  late final TabController _tabs;
  final _prompt = TextEditingController();
  String? _profileId;
  bool _imageMode = false, _reading = false, _exporting = false;
  Uint8List? _image;
  int _duration = 5;
  String _ratio = '16:9', _resolution = '720p';
  bool? _audio;
  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? VideoStudioController();
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

  VideoApiProfile? get _profile {
    for (final p in _controller.profiles) {
      if (p.id == _profileId) return p;
    }
    return _controller.profiles.isEmpty ? null : _controller.profiles.first;
  }

  bool get _locked => _controller.busy || _reading;
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _settings() => Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoProfilesPage(
          controller: _controller, chatProfiles: widget.chatProfiles)));

  Future<void> _pick() async {
    setState(() => _reading = true);
    try {
      final file = await (widget.imagePicker ?? ImagePicker()).pickImage(
          source: ImageSource.gallery, maxWidth: 4096, maxHeight: 4096);
      if (file == null) return;
      if (await file.length() > 20 * 1024 * 1024) {
        throw const FormatException('参考图片应小于 20 MB。');
      }
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      final frame = await codec.getNextFrame();
      codec.dispose();
      try {
        final ratio = frame.image.width / frame.image.height;
        if (_profile?.provider == VideoProvider.ark &&
            (frame.image.width < 300 ||
                frame.image.height < 300 ||
                ratio < 0.4 ||
                ratio > 2.5)) {
          throw const FormatException(
              'Seedance 首帧图片宽高至少 300 像素，宽高比应在 0.4–2.5 之间。');
        }
        final data =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null || data.lengthInBytes > 20 * 1024 * 1024) {
          throw const FormatException('转换后的 PNG 超过 20 MB，请缩小图片。');
        }
        if (mounted) setState(() => _image = data.buffer.asUint8List());
      } finally {
        frame.image.dispose();
      }
    } catch (e) {
      _message(e is FormatException ? e.message : '图片读取失败，请检查权限或重新选择。');
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _generate() async {
    final profile = _profile;
    if (profile == null || !profile.isComplete) {
      _message('请先添加完整的视频 API 配置。');
      return;
    }
    if (_prompt.text.trim().isEmpty) {
      _message('请输入视频提示词。');
      return;
    }
    if (_imageMode && _image == null) {
      _message('请先选择首帧图片。');
      return;
    }
    FocusScope.of(context).unfocus();
    final image =
        _imageMode ? 'data:image/png;base64,${base64Encode(_image!)}' : null;
    final ratios = VideoOptions.ratios(profile.provider);
    final options = VideoOptions(
        duration: _duration.clamp(profile.minDuration, profile.maxDuration),
        ratio: ratios.contains(_ratio) ? _ratio : '16:9',
        resolution:
            profile.resolutions.contains(_resolution) ? _resolution : '720p',
        audio: _audio);
    _tabs.animateTo(1);
    await _controller.generate(
        profile: profile, prompt: _prompt.text, options: options, image: image);
  }

  Future<void> _export(VideoJob job) async {
    setState(() => _exporting = true);
    try {
      final source = File(job.localPath);
      if (!await source.exists()) throw const FileSystemException('missing');
      // Mobile's system save picker needs bytes; desktop copies the file directly.
      final path = await FilePicker.platform.saveFile(
          dialogTitle: '保存视频',
          fileName: '${job.id}.mp4',
          type: FileType.custom,
          allowedExtensions: ['mp4'],
          bytes: Platform.isAndroid || Platform.isIOS
              ? await source.readAsBytes()
              : null);
      if (path == null) return;
      if (!Platform.isAndroid &&
          !Platform.isIOS &&
          File(path).absolute.path != source.absolute.path) {
        await source.copy(path);
      }
      _message('视频已导出。');
    } catch (_) {
      _message('视频导出失败，请检查文件和可用空间。');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _delete(VideoJob job) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除本地视频和任务记录？'),
                content: const Text('删除后无法在此恢复；已提交的服务端任务仍可能继续。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ]));
    if (ok != true) return;
    try {
      await _controller.deleteJob(job);
    } catch (_) {
      _message('删除失败，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Scaffold(
          appBar: AppBar(
              title: const Text('视频工作台'),
              actions: [
                IconButton(
                    tooltip: '视频 API 配置',
                    onPressed: _locked ? null : _settings,
                    icon: const Icon(Icons.tune))
              ],
              bottom: TabBar(
                  controller: _tabs,
                  tabs: const [Tab(text: '创作'), Tab(text: '任务与作品')])),
          body: _controller.loading
              ? const Center(child: CircularProgressIndicator())
              : !_controller.ready
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_controller.error ?? '读取失败'),
                      TextButton(
                          onPressed: _controller.load, child: const Text('重试'))
                    ]))
                  : Column(children: [
                      if (_controller.error != null)
                        Material(
                            color: Theme.of(context).colorScheme.errorContainer,
                            child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Row(children: [
                                  const Icon(Icons.info_outline),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_controller.error!))
                                ]))),
                      Expanded(
                          child: TabBarView(
                              controller: _tabs,
                              children: [_create(), _history()])),
                    ])));

  Widget _create() {
    final profile = _profile;
    final provider = profile?.provider ?? VideoProvider.ark;
    final ratios = VideoOptions.ratios(provider);
    final resolutions = profile?.resolutions ?? ['480p', '720p', '1080p'];
    final min = profile?.minDuration ?? 4;
    final max = profile?.maxDuration ?? 30;
    return ListView(padding: const EdgeInsets.all(20), children: [
      const Text('把想象变成一段视频',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const Text('Seedance · Grok Imagine\n描述主体、动作、运镜和声音，生成结果自动保存到本地。'),
      const SizedBox(height: 20),
      if (profile == null)
        FilledButton.tonalIcon(
            onPressed: _settings,
            icon: const Icon(Icons.add),
            label: const Text('添加视频 API'))
      else
        DropdownButtonFormField<String>(
            key: ValueKey('profile-${profile.id}'),
            initialValue: profile.id,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: '视频 API', border: OutlineInputBorder()),
            items: _controller.profiles
                .map((p) => DropdownMenuItem(
                    value: p.id,
                    child: Text('${p.name} · ${p.model}',
                        overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: _locked
                ? null
                : (id) => setState(() {
                      _profileId = id;
                      _duration = 5;
                      _ratio = '16:9';
                      _resolution = '720p';
                      _audio = null;
                      _image = null;
                    })),
      const SizedBox(height: 16),
      SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
                value: false,
                label: Text('文生视频'),
                icon: Icon(Icons.text_fields)),
            ButtonSegment(
                value: true,
                label: Text('图生视频'),
                icon: Icon(Icons.image_outlined))
          ],
          selected: {
            _imageMode
          },
          onSelectionChanged:
              _locked ? null : (v) => setState(() => _imageMode = v.first)),
      const SizedBox(height: 16),
      TextField(
          controller: _prompt,
          enabled: !_locked,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
              labelText: '视频提示词',
              hintText: '例如：雨后的街道，一只橘猫缓缓走过，镜头低角度跟随，电影质感，背景有轻柔雨声。',
              border: OutlineInputBorder())),
      if (_imageMode) ...[
        const SizedBox(height: 16),
        if (_image != null)
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_image!, height: 180, fit: BoxFit.contain)),
        OutlinedButton.icon(
            onPressed: _locked ? null : _pick,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: Text(_reading
                ? '读取中'
                : _image == null
                    ? '选择首帧图片'
                    : '更换首帧图片')),
        if (provider == VideoProvider.ark)
          const Text('Seedance 首帧生成会自动保持图片比例。'),
      ],
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
          key: ValueKey('duration-${profile?.id}-$min-$max'),
          initialValue: _duration.clamp(min, max),
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: '视频时长', border: OutlineInputBorder()),
          items: List.generate(
              max - min + 1,
              (i) => DropdownMenuItem(
                  value: min + i, child: Text('${min + i} 秒'))),
          onChanged: _locked ? null : (v) => setState(() => _duration = v!)),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
          key: ValueKey('ratio-${profile?.id}-$_imageMode'),
          initialValue: _imageMode && provider == VideoProvider.ark
              ? 'adaptive'
              : ratios.contains(_ratio)
                  ? _ratio
                  : '16:9',
          isExpanded: true,
          decoration: InputDecoration(
              labelText: _imageMode && provider == VideoProvider.ark
                  ? '输出比例（保持首帧）'
                  : '输出比例',
              border: const OutlineInputBorder()),
          items: ratios
              .map((r) => DropdownMenuItem(
                  value: r, child: Text(r == 'adaptive' ? '自动适配' : r)))
              .toList(),
          onChanged: _locked || (_imageMode && provider == VideoProvider.ark)
              ? null
              : (v) => setState(() => _ratio = v!)),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
          key: ValueKey('resolution-${profile?.id}'),
          initialValue:
              resolutions.contains(_resolution) ? _resolution : '720p',
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: '分辨率', border: OutlineInputBorder()),
          items: resolutions
              .map((r) => DropdownMenuItem(value: r, child: Text(r)))
              .toList(),
          onChanged: _locked ? null : (v) => setState(() => _resolution = v!)),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
          key: ValueKey('audio-${profile?.id}'),
          initialValue: _audio == null ? 'default' : _audio.toString(),
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: '声音', border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'default', child: Text('模型默认')),
            DropdownMenuItem(value: 'true', child: Text('生成声音')),
            DropdownMenuItem(value: 'false', child: Text('静音'))
          ],
          onChanged: _locked
              ? null
              : (v) =>
                  setState(() => _audio = v == 'default' ? null : v == 'true')),
      const SizedBox(height: 20),
      FilledButton.icon(
          onPressed: _locked || profile == null ? null : _generate,
          icon: const Icon(Icons.movie_creation_outlined),
          label: const Text('生成视频')),
      const SizedBox(height: 12),
      const Text('生成通常需要几分钟。离开页面会暂停本地查询，任务 ID 会保留；返回“任务与作品”继续查询。'),
    ]);
  }

  Widget _history() => ListView(padding: const EdgeInsets.all(20), children: [
        if (_controller.busy)
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const LinearProgressIndicator(),
                        const SizedBox(height: 12),
                        Text(_controller.submitting
                            ? '正在提交任务，请等待任务 ID 返回。'
                            : '正在查询或下载视频…'),
                        if (!_controller.submitting)
                          TextButton.icon(
                              onPressed: _controller.pause,
                              icon: const Icon(Icons.pause),
                              label: const Text('暂停查询')),
                      ]))),
        if (_controller.jobs.isEmpty && !_controller.busy)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: Text('还没有视频任务，去创作你的第一段视频。'))),
        for (final job in _controller.jobs)
          Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.movie_outlined),
                              const SizedBox(width: 8),
                              Expanded(
                                  child: Text(job.statusLabel,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600))),
                              IconButton(
                                  tooltip: '删除视频任务',
                                  onPressed: _controller.busy || _exporting
                                      ? null
                                      : () => _delete(job),
                                  icon: const Icon(Icons.delete_outline))
                            ]),
                            Text(job.prompt,
                                maxLines: 4, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 8),
                            Text(
                                '${job.model}\n${job.mode} · ${job.duration} 秒 · ${job.ratio} · ${job.resolution}\n${job.createdAt.toLocal().toString().split('.').first}',
                                style: Theme.of(context).textTheme.bodySmall),
                            const SizedBox(height: 8),
                            SelectableText('任务 ID：${job.taskId}'),
                            if (job.error.isNotEmpty) Text(job.error),
                            Wrap(spacing: 8, children: [
                              if (job.canResume)
                                FilledButton.tonalIcon(
                                    onPressed: _controller.busy
                                        ? null
                                        : () => _controller.resume(job),
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('继续查询 / 下载')),
                              if (job.localPath.isNotEmpty) ...[
                                FilledButton.tonalIcon(
                                    onPressed: () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                LocalVideoPlayerPage(
                                                    path: job.localPath))),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('播放视频')),
                                OutlinedButton.icon(
                                    onPressed:
                                        _exporting ? null : () => _export(job),
                                    icon: const Icon(Icons.download),
                                    label: const Text('保存视频')),
                              ],
                              TextButton(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                        ClipboardData(text: job.prompt));
                                    _message('提示词已复制。');
                                  },
                                  child: const Text('复制提示词')),
                              TextButton(
                                  onPressed: () {
                                    _prompt.text = job.prompt;
                                    _tabs.animateTo(0);
                                  },
                                  child: const Text('复用提示词')),
                            ]),
                          ]))))
      ]);
}
