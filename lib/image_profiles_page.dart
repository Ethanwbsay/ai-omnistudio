import 'package:flutter/material.dart';

import 'models/api_profile.dart';
import 'models/image_api_profile.dart';
import 'services/image_studio_controller.dart';

class ImageProfilesPage extends StatelessWidget {
  const ImageProfilesPage(
      {super.key, required this.controller, this.chatProfiles = const []});
  final ImageStudioController controller;
  final List<ApiProfile> chatProfiles;

  void _edit(BuildContext context, [ImageApiProfile? profile]) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ImageProfileEditor(
            controller: controller,
            initial: profile,
            chatProfiles: chatProfiles)));
  }

  Future<void> _delete(BuildContext context, ImageApiProfile profile) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('删除图片 API？'),
                content: Text(profile.name),
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
      await controller.deleteProfile(profile.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除配置失败，请重试。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('图片 API 配置')),
        floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.add),
            label: const Text('添加图片 API')),
        body: AnimatedBuilder(
            animation: controller,
            builder: (context, _) => controller.profiles.isEmpty
                ? const Center(child: Text('还没有图片 API 配置。'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    itemCount: controller.profiles.length,
                    separatorBuilder: (_, index) => const Divider(),
                    itemBuilder: (context, index) {
                      final profile = controller.profiles[index];
                      return ListTile(
                          leading: const Icon(Icons.image_outlined),
                          title: Text(profile.name),
                          subtitle:
                              Text('${profile.model}\n${profile.baseUrl}'),
                          isThreeLine: true,
                          onTap: () => _edit(context, profile),
                          trailing: IconButton(
                              tooltip: '删除配置',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(context, profile)));
                    })),
      );
}

class ImageProfileEditor extends StatefulWidget {
  const ImageProfileEditor(
      {super.key,
      required this.controller,
      this.initial,
      this.chatProfiles = const []});
  final ImageStudioController controller;
  final ImageApiProfile? initial;
  final List<ApiProfile> chatProfiles;

  @override
  State<ImageProfileEditor> createState() => _ImageProfileEditorState();
}

class _ImageProfileEditorState extends State<ImageProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name,
      _url,
      _key,
      _model,
      _generationPath,
      _editPath,
      _timeoutMinutes;
  bool _obscure = true;
  bool _saving = false;
  late String _responseFormat;
  late String _responseMode;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '我的图片 API');
    _url = TextEditingController(
        text: initial?.baseUrl ?? 'https://api.openai.com/v1');
    _key = TextEditingController(text: initial?.apiKey ?? '');
    _model = TextEditingController(text: initial?.model ?? '');
    _generationPath = TextEditingController(
        text: initial?.generationPath ?? 'images/generations');
    _editPath =
        TextEditingController(text: initial?.editPath ?? 'images/edits');
    _responseFormat = initial?.responseFormat ?? '';
    _responseMode = initial?.responseMode ?? 'auto';
    _timeoutMinutes = TextEditingController(
        text: '${initial?.generationTimeoutMinutes ?? 15}');
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _url,
      _key,
      _model,
      _generationPath,
      _editPath,
      _timeoutMinutes
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final profile = ImageApiProfile(
        id: widget.initial?.id ??
            'image-api-${DateTime.now().microsecondsSinceEpoch}',
        name: _name.text.trim(),
        baseUrl: _url.text.trim(),
        apiKey: _key.text.trim(),
        model: _model.text.trim(),
        generationPath: _generationPath.text.trim(),
        editPath: _editPath.text.trim(),
        responseFormat: _responseFormat,
        responseMode: _responseMode,
        generationTimeoutMinutes:
            int.tryParse(_timeoutMinutes.text.trim()) ?? 0);
    if (!profile.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请检查 API 地址、请求路径和等待时间（1–30 分钟）。')));
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.controller.saveProfile(profile);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('配置保存失败，请重试。')));
      }
    }
  }

  Widget _field(TextEditingController c, String label,
          {String? hint,
          bool obscure = false,
          TextInputType? keyboard,
          Widget? suffix}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
              controller: c,
              enabled: !_saving,
              obscureText: obscure,
              autocorrect: false,
              keyboardType: keyboard,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请填写$label' : null,
              decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: const OutlineInputBorder(),
                  suffixIcon: suffix)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.initial == null ? '添加图片 API' : '编辑图片 API')),
        body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Form(
                  key: _form,
                  child: ListView(padding: const EdgeInsets.all(20), children: [
                    if (widget.chatProfiles.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: '复用现有 API 的地址与 Key',
                              border: OutlineInputBorder()),
                          items: widget.chatProfiles
                              .map((e) => DropdownMenuItem(
                                  value: e.id, child: Text(e.name)))
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (id) {
                                  final p = widget.chatProfiles
                                      .firstWhere((e) => e.id == id);
                                  _url.text = p.baseUrl.replaceFirst(
                                      RegExp(r'/chat/completions/?$'), '');
                                  _key.text = p.apiKey;
                                }),
                      const SizedBox(height: 16),
                    ],
                    _field(_name, '配置名称'),
                    _field(_url, 'API Base URL', keyboard: TextInputType.url),
                    _field(_key, 'API Key',
                        obscure: _obscure,
                        suffix: IconButton(
                            tooltip: _obscure ? '显示 Key' : '隐藏 Key',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(_obscure
                                ? Icons.visibility
                                : Icons.visibility_off))),
                    _field(_model, '图片模型名称', hint: '填写服务商提供的模型 ID'),
                    ExpansionTile(
                        title: const Text('接口选项'),
                        tilePadding: EdgeInsets.zero,
                        children: [
                          _field(_generationPath, '文生图请求路径'),
                          _field(_editPath, '图生图 / 编辑请求路径'),
                          _field(_timeoutMinutes, '生成最长等待时间（分钟）',
                              hint: '1–30，默认 15',
                              keyboard: TextInputType.number),
                          DropdownButtonFormField<String>(
                              initialValue: _responseMode,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: '接收方式',
                                  helperText: '自动：梭子蟹 GPT 图片模型使用流式接收',
                                  border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(
                                    value: 'auto', child: Text('自动')),
                                DropdownMenuItem(
                                    value: 'stream', child: Text('流式（服务商须支持）')),
                                DropdownMenuItem(
                                    value: 'json', child: Text('普通 JSON')),
                              ],
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _responseMode = v!)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              initialValue: _responseFormat,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: '图片返回格式',
                                  border: OutlineInputBorder()),
                              items: const [
                                DropdownMenuItem(
                                    value: '', child: Text('模型默认')),
                                DropdownMenuItem(
                                    value: 'b64_json', child: Text('Base64')),
                                DropdownMenuItem(
                                    value: 'url', child: Text('URL'))
                              ],
                              onChanged: _saving
                                  ? null
                                  : (v) =>
                                      setState(() => _responseFormat = v!)),
                          const SizedBox(height: 16),
                        ]),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? '保存中' : '保存图片配置')),
                  ]))),
        ),
      );
}
