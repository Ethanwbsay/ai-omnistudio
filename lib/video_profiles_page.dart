import 'package:flutter/material.dart';
import 'models/api_profile.dart';
import 'models/video_api_profile.dart';
import 'services/video_studio_controller.dart';

class VideoProfilesPage extends StatelessWidget {
  const VideoProfilesPage(
      {super.key, required this.controller, this.chatProfiles = const []});
  final VideoStudioController controller;
  final List<ApiProfile> chatProfiles;
  void _edit(BuildContext context, [VideoApiProfile? initial]) =>
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VideoProfileEditor(
              controller: controller,
              initial: initial,
              chatProfiles: chatProfiles)));

  Future<void> _delete(BuildContext context, VideoApiProfile p) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除视频 API？'),
                content: const Text('未完成的任务需要原来的配置才能继续查询。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('删除'))
                ]));
    if (confirmed != true) return;
    try {
      await controller.deleteProfile(p.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除配置失败。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('视频 API 配置')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.add),
          label: const Text('添加视频 API')),
      body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => controller.profiles.isEmpty
              ? const Center(child: Text('添加 Seedance 或 Grok 视频 API 开始创作。'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: controller.profiles.length,
                  separatorBuilder: (_, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final p = controller.profiles[index];
                    return ListTile(
                        leading: const Icon(Icons.movie_outlined),
                        title: Text(p.name),
                        subtitle: Text('${p.provider.label}\n${p.model}'),
                        isThreeLine: true,
                        onTap: () => _edit(context, p),
                        trailing: IconButton(
                            tooltip: '删除视频配置',
                            onPressed: controller.busy
                                ? null
                                : () => _delete(context, p),
                            icon: const Icon(Icons.delete_outline)));
                  })));
}

class VideoProfileEditor extends StatefulWidget {
  const VideoProfileEditor(
      {super.key,
      required this.controller,
      this.initial,
      this.chatProfiles = const []});
  final VideoStudioController controller;
  final VideoApiProfile? initial;
  final List<ApiProfile> chatProfiles;
  @override
  State<VideoProfileEditor> createState() => _VideoProfileEditorState();
}

class _VideoProfileEditorState extends State<VideoProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _url, _key, _model, _submit, _query;
  late VideoProvider _provider;
  bool _saving = false, _obscure = true;
  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _provider = p?.provider ?? VideoProvider.ark;
    _name = TextEditingController(text: p?.name ?? 'Seedance 2.5');
    _url = TextEditingController(text: p?.baseUrl ?? _provider.baseUrl);
    _key = TextEditingController(text: p?.apiKey ?? '');
    _model = TextEditingController(text: p?.model ?? _provider.model);
    _submit =
        TextEditingController(text: p?.submitPath ?? _provider.submitPath);
    _query = TextEditingController(text: p?.queryPath ?? _provider.queryPath);
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _key, _model, _submit, _query]) {
      c.dispose();
    }
    super.dispose();
  }

  void _preset(VideoProvider p) => setState(() {
        _provider = p;
        _name.text =
            p == VideoProvider.ark ? 'Seedance 2.5' : 'Grok Imagine Video';
        _url.text = p.baseUrl;
        _model.text = p.model;
        _submit.text = p.submitPath;
        _query.text = p.queryPath;
        _key.clear();
      });
  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final p = VideoApiProfile(
        id: widget.initial?.id ??
            'video-api-${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        provider: _provider,
        baseUrl: _url.text.trim(),
        apiKey: _key.text.trim(),
        model: _model.text.trim(),
        submitPath: _submit.text.trim(),
        queryPath: _query.text.trim());
    if (!p.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请检查地址和请求路径；查询路径必须包含 {id}。')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveProfile(p);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('视频配置保存失败。')));
      }
    }
  }

  Widget _field(TextEditingController c, String label,
          {String? hint, bool secret = false}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
              controller: c,
              enabled: !_saving,
              obscureText: secret && _obscure,
              autocorrect: false,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请填写$label' : null,
              decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  suffixIcon: secret
                      ? IconButton(
                          tooltip: _obscure ? '显示 Key' : '隐藏 Key',
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(_obscure
                              ? Icons.visibility
                              : Icons.visibility_off))
                      : null)));
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar:
          AppBar(title: Text(widget.initial == null ? '添加视频 API' : '编辑视频 API')),
      body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            DropdownButtonFormField<VideoProvider>(
                initialValue: _provider,
                isExpanded: true,
                decoration: const InputDecoration(
                    labelText: '服务商协议', border: OutlineInputBorder()),
                items: VideoProvider.values
                    .map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.label)))
                    .toList(),
                onChanged: _saving ? null : (p) => _preset(p!)),
            const SizedBox(height: 12),
            Text(_provider == VideoProvider.ark
                ? '预置 Seedance 2.5；也可填写方舟提供的 Seedance 模型 ID 或推理接入点 ep-…，需在服务商开通对应模型。'
                : '支持 grok-imagine-video 和 grok-imagine-video-1.5；使用 xAI API Key 或兼容此协议的服务商。'),
            const SizedBox(height: 20),
            if (widget.chatProfiles.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: '复用聊天 API 的地址与 Key',
                      border: OutlineInputBorder()),
                  items: widget.chatProfiles
                      .map((p) =>
                          DropdownMenuItem(value: p.id, child: Text(p.name)))
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (id) {
                          final p =
                              widget.chatProfiles.firstWhere((p) => p.id == id);
                          _url.text = p.baseUrl.replaceFirst(
                              RegExp(r'/chat/completions/?$'), '');
                          _key.text = p.apiKey;
                        }),
              const SizedBox(height: 12),
              const Text('复用后请确认服务商支持所选视频协议，聊天 API 本身不一定支持视频。'),
              const SizedBox(height: 16),
            ],
            _field(_name, '配置名称'),
            _field(_url, 'API Base URL'),
            _field(_key, 'API Key', secret: true),
            _field(_model, '视频模型 ID'),
            if (_provider == VideoProvider.grok)
              Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Wrap(
                      spacing: 8,
                      children: ['grok-imagine-video', 'grok-imagine-video-1.5']
                          .map((m) => ActionChip(
                              label: Text(m),
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _model.text = m)))
                          .toList())),
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('接口路径'),
                children: [
                  _field(_submit, '提交任务路径'),
                  _field(_query, '查询任务路径', hint: '包含 {id} 的相对路径'),
                  const Text('路径相对于 Base URL。更改路径不改变请求协议。'),
                ]),
            const SizedBox(height: 20),
            FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? '保存中' : '保存视频配置')),
          ])));
}
