import 'package:flutter/material.dart';

import 'models/api_settings.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.initial, required this.onSave});

  final ApiSettings initial;
  final Future<void> Function(ApiSettings) onSave;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _model;
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initial.baseUrl);
    _key = TextEditingController(text: widget.initial.apiKey);
    _model = TextEditingController(text: widget.initial.model);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings =
        ApiSettings(baseUrl: _url.text, apiKey: _key.text, model: _model.text);
    if (!settings.isComplete) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请填写全部 API 配置。')));
      return;
    }
    setState(() => _saving = true);
    await widget.onSave(settings);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('API 设置')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('使用你自己的 OpenAI 兼容接口',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text(
                'Base URL 填到 /v1 即可；应用会自动补全 /chat/completions。图像题目需要所选模型支持视觉输入。'),
            const SizedBox(height: 24),
            TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: 'https://api.openai.com/v1',
                    border: OutlineInputBorder())),
            const SizedBox(height: 16),
            TextField(
                controller: _key,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                    labelText: 'API Key',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                        icon: Icon(_obscureKey
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureKey = !_obscureKey)))),
            const SizedBox(height: 16),
            TextField(
                controller: _model,
                decoration: const InputDecoration(
                    labelText: '模型名称',
                    hintText: 'gpt-4o-mini',
                    border: OutlineInputBorder())),
            const SizedBox(height: 12),
            const Text('API Key 仅保存在本机应用数据中。生产环境建议改用 Android Keystore 等安全存储。',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 28),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存配置')),
          ],
        ),
      );
}
