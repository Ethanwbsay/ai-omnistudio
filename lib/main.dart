import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import 'models/api_settings.dart';
import 'models/chat_message.dart';
import 'models/conversation.dart';
import 'services/conversation_store.dart';
import 'services/openai_service.dart';
import 'services/settings_store.dart';
import 'settings_page.dart';
import 'widgets/math_content.dart';
import 'tavern_app.dart';

void main() => runApp(const AiOmnistudioApp());

class AiOmnistudioApp extends StatelessWidget {
  const AiOmnistudioApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AI 万象工坊',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xffd39b6a),
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xff171418),
          cardTheme: const CardThemeData(
            color: Color(0xff242026),
            margin: EdgeInsets.zero,
          ),
        ),
        home: TavernHome(
          solverBuilder: (_) => const SolverPage(),
        ),
      );
}

class SolverPage extends StatefulWidget {
  const SolverPage({super.key});

  @override
  State<SolverPage> createState() => _SolverPageState();
}

class _SolverPageState extends State<SolverPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _settingsStore = SettingsStore();
  final _conversationStore = ConversationStore();
  final _api = OpenAiService();

  final List<String> _pendingImages = [];
  List<Conversation> _conversations = [];
  ApiSettings? _settings;
  String? _activeConversationId;
  bool _loading = false;

  Conversation get _activeConversation => _conversations.firstWhere(
        (conversation) => conversation.id == _activeConversationId,
        orElse: Conversation.create,
      );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final values = await Future.wait([
      _settingsStore.load(),
      _conversationStore.load(),
    ]);
    final settings = values[0] as ApiSettings;
    final savedConversations = values[1] as List<Conversation>;
    final conversations = savedConversations.isEmpty
        ? <Conversation>[Conversation.create()]
        : savedConversations;
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _conversations = conversations;
      _activeConversationId = conversations.first.id;
    });
    if (savedConversations.isEmpty) await _saveConversations();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _saveConversations() => _conversationStore.save(_conversations);

  Future<void> _newConversation() async {
    final conversation = Conversation.create();
    setState(() {
      _conversations = [conversation, ..._conversations];
      _activeConversationId = conversation.id;
      _pendingImages.clear();
      _input.clear();
    });
    await _saveConversations();
  }

  Future<void> _selectConversation(Conversation conversation) async {
    if (_loading) return;
    setState(() {
      _activeConversationId = conversation.id;
      _pendingImages.clear();
      _input.clear();
    });
    Navigator.of(context).pop();
    _scrollToEnd();
  }

  Future<void> _replaceConversation(
    String id, {
    required List<ChatMessage> messages,
    String? title,
  }) async {
    final index =
        _conversations.indexWhere((conversation) => conversation.id == id);
    if (index < 0) return;
    final updated = _conversations[index].copyWith(
      messages: messages,
      title: title,
      updatedAt: DateTime.now(),
    );
    final conversations = [..._conversations]..[index] = updated;
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (mounted) setState(() => _conversations = conversations);
    await _saveConversations();
  }

  Future<void> _chooseGalleryImages() async {
    try {
      final images =
          await _picker.pickMultiImage(imageQuality: 82, maxWidth: 1800);
      if (images.isEmpty) return;
      await _cropAndAdd(images);
    } catch (_) {
      _showImageError();
    }
  }

  Future<void> _chooseCameraImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (image == null) return;
      await _cropAndAdd([image]);
    } catch (_) {
      _showImageError();
    }
  }

  Future<void> _cropAndAdd(List<XFile> images) async {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final croppedImages = <String>[];
    for (final image in images) {
      if (!mounted) return;
      final cropped = await ImageCropper().cropImage(
        sourcePath: image.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 88,
        maxWidth: 1800,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪题目图片',
            toolbarColor: primaryColor,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: primaryColor,
            lockAspectRatio: false,
          ),
        ],
      );
      if (cropped == null) continue;
      croppedImages.add(base64Encode(await File(cropped.path).readAsBytes()));
    }
    if (!mounted || croppedImages.isEmpty) return;
    setState(() => _pendingImages.addAll(croppedImages));
  }

  void _showImageError() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法读取或裁剪图片，请检查相机和相册权限。')),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (_loading || (text.isEmpty && _pendingImages.isEmpty)) return;
    if (_settings == null || !_settings!.isComplete) {
      await _openSettings();
      return;
    }
    final conversationId = _activeConversation.id;
    final prompt = text.isEmpty ? '请识别并详细解答图片中的题目。' : text;
    final userMessage = ChatMessage(
      role: MessageRole.user,
      content: prompt,
      imagesBase64: List<String>.from(_pendingImages),
    );
    final before = _activeConversation;
    final conversation = [...before.messages, userMessage];
    final title =
        before.messages.isEmpty ? _conversationTitle(prompt) : before.title;
    setState(() {
      _input.clear();
      _pendingImages.clear();
      _loading = true;
    });
    await _replaceConversation(conversationId,
        messages: conversation, title: title);
    _scrollToEnd();
    try {
      final answer =
          await _api.solve(settings: _settings!, conversation: conversation);
      final targetIndex =
          _conversations.indexWhere((item) => item.id == conversationId);
      if (targetIndex >= 0) {
        final target = _conversations[targetIndex];
        await _replaceConversation(
          conversationId,
          messages: [
            ...target.messages,
            ChatMessage(role: MessageRole.assistant, content: answer)
          ],
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.message),
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        _scrollToEnd();
      }
    }
  }

  String _conversationTitle(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.isEmpty) return '图片题目';
    return compact.length > 20 ? '${compact.substring(0, 20)}…' : compact;
  }

  void _scrollToEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOut,
          );
        }
      });

  Future<void> _openSettings() async {
    final current = _settings ?? await _settingsStore.load();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(
          initial: current,
          onSave: (value) async {
            await _settingsStore.save(value);
            if (mounted) setState(() => _settings = value);
          },
        ),
      ),
    );
  }

  Future<void> _showImageMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照搜题'),
              subtitle: const Text('拍摄一张图片后裁剪'),
              onTap: () {
                Navigator.pop(context);
                _chooseCameraImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.collections_outlined),
              title: const Text('从相册选择多张图片'),
              subtitle: const Text('可同时选择多张，逐张裁剪后一起发送'),
              onTap: () {
                Navigator.pop(context);
                _chooseGalleryImages();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        drawer: _conversationDrawer(),
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('解题助手'),
              Text(_activeConversation.title,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.normal)),
            ],
          ),
          actions: [
            IconButton(
                onPressed: _newConversation,
                icon: const Icon(Icons.edit_square),
                tooltip: '新建对话'),
            IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.tune),
                tooltip: 'API 设置'),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: _activeConversation.messages.isEmpty
                  ? _emptyState()
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: _activeConversation.messages.length +
                          (_loading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _activeConversation.messages.length)
                          return _loadingView();
                        return _MessageBubble(
                            message: _activeConversation.messages[index]);
                      },
                    ),
            ),
            if (_pendingImages.isNotEmpty) _imagePreview(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: _loading ? null : _showImageMenu,
                      icon: const Icon(Icons.add_a_photo_outlined),
                      tooltip: '拍照或选择多张图片',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: '输入题目，或附加多张图片继续追问…',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _loading ? null : _send,
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: '发送',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Drawer _conversationDrawer() => Drawer(
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    const Expanded(
                        child: Text('历史对话',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold))),
                    IconButton(
                        onPressed: _newConversation,
                        icon: const Icon(Icons.add),
                        tooltip: '新建对话'),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: _conversations.length,
                  itemBuilder: (context, index) {
                    final conversation = _conversations[index];
                    final selected = conversation.id == _activeConversationId;
                    return ListTile(
                      selected: selected,
                      selectedTileColor:
                          Theme.of(context).colorScheme.secondaryContainer,
                      leading: Icon(
                          selected ? Icons.forum : Icons.chat_bubble_outline),
                      title: Text(conversation.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_conversationSubtitle(conversation),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _selectConversation(conversation),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );

  String _conversationSubtitle(Conversation conversation) {
    if (conversation.messages.isEmpty) return '还没有消息';
    final count = conversation.messages.length;
    return '$count 条消息 · ${conversation.updatedAt.month}/${conversation.updatedAt.day} ${conversation.updatedAt.hour.toString().padLeft(2, '0')}:${conversation.updatedAt.minute.toString().padLeft(2, '0')}';
  }

  Widget _loadingView() => const Padding(
        padding: EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 12),
            Text('正在推理并整理详细解答…'),
          ],
        ),
      );

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_stories_outlined,
                  size: 68, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              const Text('把题目交给我',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('输入文字、拍照，或从相册一次选择多张题图。我会给出分步骤解答；侧边栏会保存所有对话。',
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.key_outlined),
                label: Text(
                    _settings?.isComplete == true ? '修改 API 设置' : '先配置 API'),
              ),
            ],
          ),
        ),
      );

  Widget _imagePreview() => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.collections_outlined),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 58,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pendingImages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(base64Decode(_pendingImages[index]),
                            width: 58, height: 58, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: -8,
                        top: -8,
                        child: InkWell(
                          onTap: () =>
                              setState(() => _pendingImages.removeAt(index)),
                          child: const CircleAvatar(
                              radius: 11, child: Icon(Icons.close, size: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text('${_pendingImages.length} 张'),
          ],
        ),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final color = isUser
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isUser ? '我的题目' : '详细解答',
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            if (message.hasImages) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: message.imagePayloads
                    .map(
                      (image) => ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(base64Decode(image),
                            width: 84, height: 84, fit: BoxFit.cover),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 6),
            MathContent(content: message.content, selectable: isUser),
          ],
        ),
      ),
    );
  }
}
