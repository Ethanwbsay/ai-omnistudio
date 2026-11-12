import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'image_studio_page.dart';
import 'video_studio_page.dart';
import 'models/api_profile.dart';
import 'models/character_card.dart';
import 'models/chat_message.dart';
import 'models/chat_session.dart';
import 'models/user_persona.dart';
import 'services/openai_service.dart';
import 'services/tavern_controller.dart';
import 'widgets/math_content.dart';

const _ink = Color(0xff171418);
const _panel = Color(0xff242026);
const _gold = Color(0xffd39b6a);

class TavernHome extends StatefulWidget {
  const TavernHome({super.key, required this.solverBuilder});

  final WidgetBuilder solverBuilder;

  @override
  State<TavernHome> createState() => _TavernHomeState();
}

class _TavernHomeState extends State<TavernHome> {
  late final TavernController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TavernController()..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openCharacter([CharacterCard? character]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CharacterEditorPage(
          controller: _controller,
          initial: character,
        ),
      ),
    );
  }

  void _openSolver() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: widget.solverBuilder),
    );
  }

  void _openImageStudio() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImageStudioPage(chatProfiles: _controller.apiProfiles),
    ));
  }

  void _openVideoStudio() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => VideoStudioPage(chatProfiles: _controller.apiProfiles),
    ));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            backgroundColor: _ink,
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI 万象工坊', style: TextStyle(fontWeight: FontWeight.w700)),
                Text('角色酒馆 · 拍照搜题 · 图片与视频生成',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: '视频工作台',
                icon: const Icon(Icons.movie_outlined),
                onPressed: _openVideoStudio,
              ),
              IconButton(
                tooltip: '图片工作台',
                icon: const Icon(Icons.image_outlined),
                onPressed: _openImageStudio,
              ),
              IconButton(
                tooltip: '搜题助手',
                icon: const Icon(Icons.auto_stories_outlined),
                onPressed: _openSolver,
              ),
              IconButton(
                tooltip: '用户 Persona',
                icon: const Icon(Icons.person_outline),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PersonaPage(controller: _controller),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'API 配置',
                icon: const Icon(Icons.tune),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ApiProfilesPage(controller: _controller),
                  ),
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: _gold,
            foregroundColor: _ink,
            onPressed: _controller.loading ? null : () => _openCharacter(),
            icon: const Icon(Icons.add),
            label: const Text('新建角色'),
          ),
          body: _controller.loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _controller.load,
                  child: _controller.characters.isEmpty
                      ? _emptyCharacters()
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 390,
                            mainAxisExtent: 205,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 14,
                          ),
                          itemCount: _controller.characters.length + 3,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return _SolverTile(onTap: _openSolver);
                            }
                            if (index == 1) {
                              return _ImageStudioTile(onTap: _openImageStudio);
                            }
                            if (index == 2) {
                              return _VideoStudioTile(onTap: _openVideoStudio);
                            }
                            final character = _controller.characters[index - 3];
                            return _CharacterTile(
                              character: character,
                              apiReady: _controller
                                      .profileFor(character)
                                      ?.isComplete ??
                                  false,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ChatPage(
                                    controller: _controller,
                                    character: character,
                                  ),
                                ),
                              ),
                              onEdit: () => _openCharacter(character),
                            );
                          },
                        ),
                ),
        ),
      );

  Widget _emptyCharacters() => ListView(
        padding: const EdgeInsets.all(28),
        children: [
          const SizedBox(height: 90),
          Icon(Icons.local_bar_outlined, size: 76, color: _gold.withAlpha(210)),
          const SizedBox(height: 20),
          const Text('欢迎来到 AI 万象工坊',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          const Text('创建一个角色，写下 TA 的性格和故事，然后开始一场只属于你们的对话。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, height: 1.5)),
          const SizedBox(height: 26),
          FilledButton.tonalIcon(
            onPressed: _openSolver,
            icon: const Icon(Icons.auto_stories_outlined),
            label: const Text('打开搜题助手'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _openImageStudio,
            icon: const Icon(Icons.image_outlined),
            label: const Text('打开图片工作台'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _openVideoStudio,
            icon: const Icon(Icons.movie_outlined),
            label: const Text('打开视频工作台'),
          ),
          const SizedBox(height: 12),
          Center(
            child: FilledButton.icon(
              onPressed: () => _openCharacter(),
              icon: const Icon(Icons.add),
              label: const Text('创建第一个角色'),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => ApiProfilesPage(controller: _controller)),
              ),
              icon: const Icon(Icons.key_outlined),
              label: const Text('先配置 API'),
            ),
          ),
        ],
      );
}

class _VideoStudioTile extends StatelessWidget {
  const _VideoStudioTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: const Padding(
      padding: EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.movie_outlined, size: 48, color: Color(0xffbba5ed)),
        Spacer(),
        Text('视频工作台', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text('Seedance · Grok · 文生视频 / 图生视频', style: TextStyle(color: Colors.white70)),
        SizedBox(height: 12),
        Icon(Icons.arrow_forward, color: Color(0xffbba5ed)),
      ]),
    )),
  );
}

class _ImageStudioTile extends StatelessWidget {
  const _ImageStudioTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(onTap: onTap, child: const Padding(
      padding: EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.image_outlined, size: 48, color: Color(0xff94d8ca)),
        Spacer(),
        Text('图片工作台', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text('文生图 · 图生图 · 图片编辑', style: TextStyle(color: Colors.white70)),
        SizedBox(height: 12),
        Icon(Icons.arrow_forward, color: Color(0xff94d8ca)),
      ]),
    )),
  );
}

class _SolverTile extends StatelessWidget {
  const _SolverTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xff3d2f27), Color(0xff29242a)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 29,
                  backgroundColor: Color(0x33d39b6a),
                  child:
                      Icon(Icons.auto_stories_outlined, color: _gold, size: 29),
                ),
                const Spacer(),
                const Text('搜题助手',
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('拍照或输入题目，获取分步骤解答',
                    style: TextStyle(color: Colors.white70, height: 1.35)),
                const SizedBox(height: 13),
                Row(
                  children: [
                    const Icon(Icons.arrow_forward_rounded,
                        size: 18, color: _gold),
                    const SizedBox(width: 6),
                    Text('立即使用',
                        style: TextStyle(
                            color: _gold, fontWeight: FontWeight.w600)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _CharacterTile extends StatelessWidget {
  const _CharacterTile({
    required this.character,
    required this.apiReady,
    required this.onTap,
    required this.onEdit,
  });

  final CharacterCard character;
  final bool apiReady;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Avatar(character: character, radius: 29),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(character.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: '编辑角色',
                      onPressed: onEdit,
                      icon: const Icon(Icons.more_horiz),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Text(
                    character.description.trim().isEmpty
                        ? character.personality
                        : character.description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, height: 1.4),
                  ),
                ),
                Row(
                  children: [
                    Icon(apiReady ? Icons.check_circle : Icons.warning_amber,
                        size: 16,
                        color: apiReady ? Colors.greenAccent : Colors.orange),
                    const SizedBox(width: 6),
                    Text(apiReady ? 'API 已就绪' : '需要配置 API',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                    const Spacer(),
                    const Icon(Icons.chat_bubble_outline,
                        size: 16, color: _gold),
                    const SizedBox(width: 5),
                    const Text('开始聊天',
                        style: TextStyle(color: _gold, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.character, this.radius = 25});

  final CharacterCard character;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final path = character.avatarPath;
    return CircleAvatar(
      radius: radius,
      backgroundColor: _gold.withAlpha(45),
      backgroundImage: path.isNotEmpty && File(path).existsSync()
          ? FileImage(File(path))
          : null,
      child: path.isEmpty || !File(path).existsSync()
          ? Text(character.name.trim().isEmpty ? '?' : character.name.trim()[0],
              style: TextStyle(
                  color: _gold,
                  fontSize: radius * .82,
                  fontWeight: FontWeight.bold))
          : null,
    );
  }
}

class CharacterEditorPage extends StatefulWidget {
  const CharacterEditorPage({
    super.key,
    required this.controller,
    this.initial,
  });

  final TavernController controller;
  final CharacterCard? initial;

  @override
  State<CharacterEditorPage> createState() => _CharacterEditorPageState();
}

class _CharacterEditorPageState extends State<CharacterEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _personality;
  late final TextEditingController _background;
  late final TextEditingController _opening;
  late final TextEditingController _example;
  late final TextEditingController _systemPrompt;
  String _avatarPath = '';
  String? _apiProfileId;
  bool _saving = false;
  final _picker = ImagePicker();

  bool get _editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _name = TextEditingController(text: value?.name ?? '');
    _description = TextEditingController(text: value?.description ?? '');
    _personality = TextEditingController(text: value?.personality ?? '');
    _background = TextEditingController(text: value?.background ?? '');
    _opening = TextEditingController(text: value?.openingMessage ?? '');
    _example = TextEditingController(text: value?.exampleDialogue ?? '');
    _systemPrompt = TextEditingController(text: value?.systemPrompt ?? '');
    _avatarPath = value?.avatarPath ?? '';
    _apiProfileId = value?.apiProfileId;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _personality,
      _background,
      _opening,
      _example,
      _systemPrompt,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final image = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 88, maxWidth: 1000);
    if (image == null) return;
    try {
      final saved = await widget.controller.persistAvatar(image.path);
      if (mounted) setState(() => _avatarPath = saved);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('头像保存失败，请重试。')));
      }
    }
  }

  Future<void> _save() async {
    final apiId = _apiProfileId ?? '';
    final character = CharacterCard(
      id: widget.initial?.id ??
          'character-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text,
      avatarPath: _avatarPath,
      description: _description.text,
      personality: _personality.text,
      background: _background.text,
      openingMessage: _opening.text,
      exampleDialogue: _example.text,
      systemPrompt: _systemPrompt.text,
      apiProfileId: apiId,
    );
    if (character.name.trim().isEmpty || character.personality.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请至少填写角色名称和性格。')));
      return;
    }
    final profile = widget.controller.profileFor(character);
    if (apiId.isEmpty || profile == null || !profile.isComplete) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请选择一个 API 配置后再保存。')));
      return;
    }
    setState(() => _saving = true);
    await widget.controller.saveCharacter(character);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_editing ? '编辑角色' : '创建角色')),
        body: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(48),
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      _Avatar(
                        character: CharacterCard(
                          id: '',
                          name: _name.text,
                          avatarPath: _avatarPath,
                          description: '',
                          personality: '',
                          background: '',
                          openingMessage: '',
                          exampleDialogue: '',
                          systemPrompt: '',
                          apiProfileId: '',
                        ),
                        radius: 48,
                      ),
                      const Positioned(
                        bottom: 0,
                        right: 0,
                        child: CircleAvatar(
                          radius: 15,
                          backgroundColor: _gold,
                          child: Icon(Icons.camera_alt, size: 16, color: _ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _field(_name, '角色名称 *', '例如：林默'),
              _field(_personality, '性格 *', '例如：温柔、敏锐，偶尔有点毒舌', maxLines: 4),
              _field(_description, '角色简介', '在角色卡上展示的一句话介绍', maxLines: 3),
              _field(_background, '背景与场景', '你们在哪里相遇？这个世界是什么样的？', maxLines: 5),
              _field(_opening, '开场白', '进入新会话时角色说的第一句话', maxLines: 5),
              _field(_example, '示例对话', '用“角色：...”和“用户：...”展示说话方式', maxLines: 6),
              _field(_systemPrompt, '补充系统提示词', '角色必须遵守的额外规则', maxLines: 5),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: widget.controller.apiProfiles
                        .any((profile) => profile.id == _apiProfileId)
                    ? _apiProfileId
                    : null,
                decoration: const InputDecoration(
                    labelText: '使用的 API *', border: OutlineInputBorder()),
                items: widget.controller.apiProfiles
                    .map((profile) => DropdownMenuItem(
                          value: profile.id,
                          child: Text(profile.name),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _apiProfileId = value),
                hint: const Text('请选择 API 配置'),
              ),
              if (widget.controller.apiProfiles.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) =>
                              ApiProfilesPage(controller: widget.controller)),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('还没有 API，去添加一个'),
                  ),
                ),
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存角色'),
              ),
            ],
          ),
        ),
      );

  Widget _field(TextEditingController controller, String label, String hint,
          {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
        ),
      );
}

class ApiProfilesPage extends StatelessWidget {
  const ApiProfilesPage({super.key, required this.controller});

  final TavernController controller;

  Future<void> _edit(BuildContext context, [ApiProfile? profile]) async {
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            ApiProfileEditorPage(controller: controller, initial: profile)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('API 配置')),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context),
          icon: const Icon(Icons.add),
          label: const Text('添加 API'),
        ),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) => controller.apiProfiles.isEmpty
              ? const Center(child: Text('还没有 API 配置，请添加一个。'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: controller.apiProfiles.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final profile = controller.apiProfiles[index];
                    return Card(
                      child: ListTile(
                        leading: const CircleAvatar(
                            backgroundColor: Color(0x3323c483),
                            child: Icon(Icons.cloud_outlined,
                                color: Colors.greenAccent)),
                        title: Text(profile.name),
                        subtitle: Text(
                            '${profile.model}  ·  ${profile.baseUrl}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'edit') await _edit(context, profile);
                            if (value == 'delete') {
                              final deleted =
                                  await controller.deleteApiProfile(profile.id);
                              if (!deleted && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text('该 API 正被角色使用，请先更换角色绑定。')),
                                );
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('编辑')),
                            PopupMenuItem(value: 'delete', child: Text('删除')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      );
}

class ApiProfileEditorPage extends StatefulWidget {
  const ApiProfileEditorPage({
    super.key,
    required this.controller,
    this.initial,
  });

  final TavernController controller;
  final ApiProfile? initial;

  @override
  State<ApiProfileEditorPage> createState() => _ApiProfileEditorPageState();
}

class _ApiProfileEditorPageState extends State<ApiProfileEditorPage> {
  late final TextEditingController _name;
  late final TextEditingController _url;
  late final TextEditingController _key;
  late final TextEditingController _model;
  late final TextEditingController _maxTokens;
  late double _temperature;
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.initial;
    _name = TextEditingController(text: value?.name ?? '我的 API');
    _url = TextEditingController(
        text: value?.baseUrl ?? 'https://api.openai.com/v1');
    _key = TextEditingController(text: value?.apiKey ?? '');
    _model = TextEditingController(text: value?.model ?? 'gpt-4o-mini');
    _maxTokens = TextEditingController(text: '${value?.maxTokens ?? 2048}');
    _temperature = value?.temperature ?? .8;
  }

  @override
  void dispose() {
    for (final controller in [_name, _url, _key, _model, _maxTokens]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final tokens = int.tryParse(_maxTokens.text.trim());
    final profile = ApiProfile(
      id: widget.initial?.id ?? 'api-${DateTime.now().microsecondsSinceEpoch}',
      name: _name.text,
      baseUrl: _url.text,
      apiKey: _key.text,
      model: _model.text,
      temperature: _temperature,
      maxTokens: tokens ?? 0,
    );
    if (!profile.isComplete) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请完整填写名称、地址、Key、模型和有效的输出参数。')));
      return;
    }
    setState(() => _saving = true);
    await widget.controller.saveApiProfile(profile);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar:
            AppBar(title: Text(widget.initial == null ? '添加 API' : '编辑 API')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('OpenAI 兼容接口',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Base URL 填到 /v1 即可，应用会自动补全 /chat/completions。',
                style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 22),
            _field(_name, '配置名称', '例如：OpenAI 主账号'),
            _field(_url, 'API Base URL', 'https://api.openai.com/v1',
                keyboardType: TextInputType.url),
            TextField(
              controller: _key,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon:
                      Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _field(_model, '模型名称', 'gpt-4o-mini'),
            const SizedBox(height: 4),
            Text('Temperature：${_temperature.toStringAsFixed(1)}'),
            Slider(
              value: _temperature,
              min: 0,
              max: 2,
              divisions: 20,
              label: _temperature.toStringAsFixed(1),
              onChanged: (value) => setState(() => _temperature = value),
            ),
            _field(_maxTokens, '最大输出 tokens', '2048',
                keyboardType: TextInputType.number),
            const SizedBox(height: 16),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存配置')),
          ],
        ),
      );

  Widget _field(TextEditingController controller, String label, String hint,
          {TextInputType? keyboardType}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
        ),
      );
}

class PersonaPage extends StatefulWidget {
  const PersonaPage({super.key, required this.controller});

  final TavernController controller;

  @override
  State<PersonaPage> createState() => _PersonaPageState();
}

class _PersonaPageState extends State<PersonaPage> {
  late final TextEditingController _nickname;
  late final TextEditingController _identity;
  late final TextEditingController _preferences;
  late final TextEditingController _prompt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final value = widget.controller.persona;
    _nickname = TextEditingController(text: value.nickname);
    _identity = TextEditingController(text: value.identity);
    _preferences = TextEditingController(text: value.preferences);
    _prompt = TextEditingController(text: value.customPrompt);
  }

  @override
  void dispose() {
    for (final controller in [_nickname, _identity, _preferences, _prompt]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await widget.controller.savePersona(UserPersona(
      nickname: _nickname.text.trim().isEmpty ? '我' : _nickname.text.trim(),
      identity: _identity.text,
      preferences: _preferences.text,
      customPrompt: _prompt.text,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('我的 Persona')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('告诉角色，你是谁',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('这些资料会作为背景提供给所有角色，也可以随时修改。',
                style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 22),
            _field(_nickname, '昵称', '角色如何称呼你'),
            _field(_identity, '身份', '例如：刚搬到这座城市的摄影师', maxLines: 3),
            _field(_preferences, '偏好', '例如：喜欢咖啡、夜晚散步和慢节奏的对话', maxLines: 4),
            _field(_prompt, '补充提示词', '希望角色对你保持的态度或互动规则', maxLines: 5),
            const SizedBox(height: 10),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存 Persona')),
          ],
        ),
      );

  Widget _field(TextEditingController controller, String label, String hint,
          {int maxLines = 1}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              border: const OutlineInputBorder()),
        ),
      );
}

class ChatPage extends StatefulWidget {
  const ChatPage(
      {super.key, required this.controller, required this.character});

  final TavernController controller;
  final CharacterCard character;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _service = OpenAiService();
  ChatSession? _session;
  StreamSubscription<String>? _replySubscription;
  String _streamingText = '';
  String? _error;
  ChatMessage? _failedUserMessage;
  bool _loading = true;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final session = await widget.controller.ensureSession(widget.character);
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
    _scrollToEnd();
  }

  @override
  void dispose() {
    _replySubscription?.cancel();
    _service.cancelActiveRequest();
    _service.dispose();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _newSession() async {
    if (_loading) return;
    await _stop();
    final session = await widget.controller.createSession(widget.character);
    if (!mounted) return;
    setState(() {
      _session = session;
      _streamingText = '';
      _error = null;
      _failedUserMessage = null;
    });
    _scrollToEnd();
  }

  Future<void> _clearSession() async {
    final session = _session;
    if (session == null) return;
    await _stop();
    await widget.controller.clearSession(session, widget.character);
    final updated =
        widget.controller.sessions.firstWhere((item) => item.id == session.id);
    if (!mounted) return;
    setState(() {
      _session = updated;
      _error = null;
      _failedUserMessage = null;
      _streamingText = '';
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _loading || _session == null) return;
    final user = ChatMessage(role: MessageRole.user, content: text);
    _input.clear();
    await _startReply(userMessage: user);
  }

  Future<void> _retry() async {
    final failed = _failedUserMessage;
    if (failed == null || _loading || _session == null) return;
    await _startReply(userMessage: failed, retry: true);
  }

  Future<void> _startReply({
    required ChatMessage userMessage,
    bool retry = false,
  }) async {
    final session = _session;
    final profile = widget.controller.profileFor(widget.character);
    if (session == null) return;
    if (profile == null || !profile.isComplete) {
      setState(() => _error = '当前角色没有可用的 API 配置，请先编辑角色。');
      return;
    }
    final prior = retry &&
            session.messages.isNotEmpty &&
            session.messages.last.role == MessageRole.user
        ? session.messages.sublist(0, session.messages.length - 1)
        : session.messages;
    final history = [...prior, userMessage];
    final title = session.title == '新会话'
        ? _shortTitle(userMessage.content)
        : session.title;
    final saved = session.copyWith(
      title: title,
      messages: history,
      updatedAt: DateTime.now(),
    );
    await widget.controller.saveSession(saved);
    if (!mounted) return;
    setState(() {
      _session = saved;
      _loading = true;
      _stopping = false;
      _streamingText = '';
      _error = null;
      _failedUserMessage = null;
    });
    _scrollToEnd();
    try {
      _replySubscription = _service
          .streamReply(
        profile: profile,
        character: widget.character,
        persona: widget.controller.persona,
        history: history,
      )
          .listen(
        (chunk) {
          if (!mounted) return;
          setState(() => _streamingText += chunk);
          _scrollToEnd();
        },
        onError: (Object error) {
          if (!mounted) return;
          setState(() {
            _error =
                error is ApiException ? error.message : '回复失败，请检查 API 配置和网络。';
            _failedUserMessage = userMessage;
            _loading = false;
          });
        },
        onDone: () async {
          final text = _streamingText.trim();
          final wasStopping = _stopping;
          if (text.isNotEmpty && mounted && !wasStopping) {
            final completed = _session!.copyWith(
              messages: [
                ..._session!.messages,
                ChatMessage(role: MessageRole.assistant, content: text),
              ],
              updatedAt: DateTime.now(),
            );
            await widget.controller.saveSession(completed);
            if (mounted) setState(() => _session = completed);
          }
          if (mounted) {
            setState(() {
              _loading = false;
              _streamingText = '';
              if (wasStopping) _error = '已停止生成';
            });
            _scrollToEnd();
          }
        },
      );
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop() async {
    if (!_loading) return;
    final partial = _streamingText.trim();
    final session = _session;
    setState(() => _stopping = true);
    await _service.cancelActiveRequest();
    await _replySubscription?.cancel();
    if (partial.isNotEmpty && session != null) {
      final completed = session.copyWith(
        messages: [
          ...session.messages,
          ChatMessage(role: MessageRole.assistant, content: partial),
        ],
        updatedAt: DateTime.now(),
      );
      await widget.controller.saveSession(completed);
      if (mounted) _session = completed;
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _stopping = false;
        _streamingText = '';
        _error = partial.isEmpty ? '已停止生成' : '已停止生成，已保留当前回复';
      });
    }
  }

  String _shortTitle(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ');
    return compact.length > 18 ? '${compact.substring(0, 18)}…' : compact;
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut);
        }
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          titleSpacing: 8,
          title: Row(
            children: [
              _Avatar(character: widget.character, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.character.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '新会话',
              onPressed: _loading ? null : _newSession,
              icon: const Icon(Icons.add_comment_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'clear') _clearSession();
                if (value == 'history') _showSessions();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'history', child: Text('会话历史')),
                PopupMenuItem(value: 'clear', child: Text('清空当前会话')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(child: _messageList()),
            if (_error != null) _errorBar(),
            _composer(),
          ],
        ),
      );

  Widget _messageList() {
    if (_loading && _session == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final messages = _session?.messages ?? const <ChatMessage>[];
    final count = messages.length + (_streamingText.isNotEmpty ? 1 : 0);
    if (count == 0) {
      return const Center(
          child: Text('从一句问候开始吧。', style: TextStyle(color: Colors.white54)));
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 20, 14, 16),
      itemCount: count,
      itemBuilder: (context, index) => index < messages.length
          ? _ChatBubble(character: widget.character, message: messages[index])
          : _ChatBubble(
              character: widget.character,
              message: ChatMessage(
                  role: MessageRole.assistant, content: _streamingText),
              streaming: true,
            ),
    );
  }

  Widget _errorBar() => Container(
        color: const Color(0xff3a2528),
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
                child: Text(_error!,
                    maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (_failedUserMessage != null)
              TextButton(onPressed: _retry, child: const Text('重试')),
            IconButton(
                tooltip: '关闭提示',
                onPressed: () => setState(() => _error = null),
                icon: const Icon(Icons.close, size: 18)),
          ],
        ),
      );

  Widget _composer() => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  enabled: !_loading,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '和 ${widget.character.name} 说点什么…',
                    filled: true,
                    fillColor: _panel,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              _loading
                  ? IconButton.filled(
                      tooltip: '停止生成',
                      onPressed: _stop,
                      icon: const Icon(Icons.stop),
                    )
                  : IconButton.filled(
                      tooltip: '发送',
                      onPressed: _send,
                      icon: const Icon(Icons.arrow_upward),
                    ),
            ],
          ),
        ),
      );

  Future<void> _showSessions() async {
    final sessions = widget.controller.sessions
        .where((session) => session.characterId == widget.character.id)
        .toList();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 360,
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              const ListTile(
                  title: Text('会话历史',
                      style: TextStyle(fontWeight: FontWeight.bold))),
              ...sessions.map((session) => ListTile(
                    selected: session.id == _session?.id,
                    leading: const Icon(Icons.forum_outlined),
                    title: Text(session.title),
                    subtitle: Text('${session.messages.length} 条消息'),
                    onTap: () {
                      setState(() => _session = session);
                      Navigator.pop(context);
                      _scrollToEnd();
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.character,
    required this.message,
    this.streaming = false,
  });

  final CharacterCard character;
  final ChatMessage message;
  final bool streaming;

  @override
  Widget build(BuildContext context) {
    final user = message.role == MessageRole.user;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment:
            user ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!user) ...[
            _Avatar(character: character, radius: 18),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.fromLTRB(14, 11, 14, 12),
              decoration: BoxDecoration(
                color: user ? const Color(0xff674b39) : _panel,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(user ? 16 : 4),
                  bottomRight: Radius.circular(user ? 4 : 16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(user ? '我' : character.name,
                      style: TextStyle(
                          fontSize: 11,
                          color: user ? Colors.white70 : _gold,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  MathContent(content: message.content, selectable: user),
                  if (streaming)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text('▌', style: TextStyle(color: _gold)),
                    ),
                ],
              ),
            ),
          ),
          if (user) const SizedBox(width: 8),
        ],
      ),
    );
  }
}
