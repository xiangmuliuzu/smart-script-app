import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/friendly_error.dart';
import '../../core/providers/auth_providers.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_page_background.dart';
import '../ai/data/ai_sse_parser.dart';
import '../chat/data/chat_providers.dart';
import 'sourcing_agent_cards.dart';
import 'sourcing_agent_repository.dart';

/// 退出 AI 选本页面后的短时会话恢复缓存（默认 3 分钟内重进恢复上次对话，超时重置为欢迎页）。
final sourcingAgentResumeCacheProvider = Provider<SourcingAgentResumeCache>(
  (ref) => SourcingAgentResumeCache(),
);

class SourcingAgentResumeCache {
  SourcingAgentResumeCache({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const Duration resumeWindow = Duration(minutes: 3);

  final DateTime Function() _clock;
  _ResumeSnapshot? _snapshot;

  void _save({
    required int? userId,
    required int? sessionId,
    required List<SourcingSession> sessions,
    required List<_Entry> messages,
  }) {
    _snapshot = _ResumeSnapshot(
      userId: userId,
      sessionId: sessionId,
      sessions: List<SourcingSession>.unmodifiable(sessions),
      messages: messages.map(_Entry.clone).toList(growable: false),
      leftAt: _clock(),
    );
  }

  _ResumeSnapshot? _restore({required int? userId}) {
    final snapshot = _snapshot;
    if (snapshot == null) return null;
    if (snapshot.userId != userId) {
      _snapshot = null;
      return null;
    }
    final elapsed = _clock().difference(snapshot.leftAt);
    if (elapsed.isNegative || elapsed > resumeWindow) {
      _snapshot = null;
      return null;
    }
    return snapshot;
  }

  void clear() => _snapshot = null;
}

class _ResumeSnapshot {
  const _ResumeSnapshot({
    required this.userId,
    required this.sessionId,
    required this.sessions,
    required this.messages,
    required this.leftAt,
  });

  final int? userId;
  final int? sessionId;
  final List<SourcingSession> sessions;
  final List<_Entry> messages;
  final DateTime leftAt;
}

class SourcingAgentPage extends ConsumerStatefulWidget {
  const SourcingAgentPage({super.key});

  @override
  ConsumerState<SourcingAgentPage> createState() => _SourcingAgentPageState();
}

class _SourcingAgentPageState extends ConsumerState<SourcingAgentPage> {
  static const _welcomeGreeting =
      '你好呀，我是 AI 选本顾问。告诉我你想找的题材、预算或集数，我来帮你从书城挑选合适的作品，并以带封面的书籍卡片发给你，点击即可查看详情。';

  static const _prompts = [
    '预算 5 万以内，找 50～80 集竖屏悬疑反转短剧并对比',
    '帮我找适合出海投流的甜宠爽剧并检查版权状态',
    '库里没有合适的，帮我起草一份古装权谋定制剧本采购需求',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final SourcingAgentResumeCache _resumeCache;
  int? _ownerUserId;
  List<SourcingSession> _sessions = [];
  List<_Entry> _messages = [];
  int? _sessionId;
  String? _loadError;
  String? _sessionsError;
  bool _loadingMessages = false;
  bool _contacting = false;
  CancelToken? _turn;

  SourcingAgentRepository get _repository =>
      ref.read(sourcingAgentRepositoryProvider);
  bool get _busy => _loadingMessages || _turn != null;

  int? _tryCurrentUserId() {
    try {
      return ref.read(authControllerProvider).user?.userId;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _resumeCache = ref.read(sourcingAgentResumeCacheProvider);
    _ownerUserId = _tryCurrentUserId();
    final snapshot = _resumeCache._restore(userId: _ownerUserId);
    if (snapshot != null) {
      _sessionId = snapshot.sessionId;
      _sessions = List<SourcingSession>.of(snapshot.sessions);
      _messages = snapshot.messages.map(_Entry.clone).toList();
    }
    unawaited(_refreshSessions());
  }

  @override
  void dispose() {
    final wasGenerating = _turn != null;
    _turn?.cancel();
    if (_sessionId != null || _messages.isNotEmpty) {
      final saved = <_Entry>[];
      for (final entry in _messages) {
        final copy = _Entry.clone(entry);
        if (wasGenerating && !copy.isUser && copy.status != null) {
          copy.status = null;
          if (copy.content.isEmpty &&
              copy.cards.isEmpty &&
              copy.notice == null) {
            copy.notice = '已停止生成';
          }
        }
        saved.add(copy);
      }
      _resumeCache._save(
        userId: _ownerUserId,
        sessionId: _sessionId,
        sessions: _sessions,
        messages: saved,
      );
    } else {
      _resumeCache.clear();
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// 后台静默拉取历史会话列表，不阻断首次进入时立即展示默认欢迎语。
  Future<void> _refreshSessions() async {
    try {
      final sessions = await _repository.listSessions();
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _sessionsError = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _sessionsError = FriendlyError.message(error));
      }
    }
  }

  Future<void> _loadSessionMessages(int sessionId) async {
    setState(() {
      _loadingMessages = true;
      _loadError = null;
      _sessionId = sessionId;
    });
    try {
      final rows = await _repository.listMessages(sessionId);
      if (!mounted) return;
      setState(() {
        _messages = rows.map(_Entry.fromHistory).toList();
      });
      _scrollToLatest();
    } catch (error) {
      if (mounted) setState(() => _loadError = FriendlyError.message(error));
    } finally {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  Future<void> _historySheet() async {
    if (_sessions.isEmpty && _sessionsError != null) {
      await _refreshSessions();
      if (!mounted) return;
    }
    final action = await showModalBottomSheet<({int sessionId, bool delete})>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .62,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Text(
                    '历史会话',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _newSession();
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('新建对话'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_sessionsError != null && _sessions.isEmpty)
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _sessionsError!,
                        style: const TextStyle(color: AppColors.text3),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          unawaited(_refreshSessions());
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              )
            else if (_sessions.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    '暂无历史会话',
                    style: TextStyle(fontSize: 13, color: AppColors.text3),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: _sessions.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                  ),
                  itemBuilder: (_, index) {
                    final session = _sessions[index];
                    final selected = session.id == _sessionId;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: AppColors.primaryTint,
                      leading: Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                        color: selected ? AppColors.primary : AppColors.text3,
                      ),
                      title: Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: AppColors.text1,
                        ),
                      ),
                      onTap: () => Navigator.pop(
                          sheetContext, (sessionId: session.id, delete: false)),
                      trailing: IconButton(
                        tooltip: '删除会话',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 20,
                          color: AppColors.text3,
                        ),
                        onPressed: () => Navigator.pop(sheetContext,
                            (sessionId: session.id, delete: true)),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action.delete) {
      await _deleteSession(action.sessionId);
    } else if (action.sessionId != _sessionId) {
      _input.clear();
      await _loadSessionMessages(action.sessionId);
    }
  }

  Future<void> _deleteSession(int sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r),
        ),
        title: const Text('删除选本对话'),
        content: const Text('删除这段对话及其中的消息？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirm != true || _busy) return;
    setState(() => _loadingMessages = true);
    try {
      await _repository.deleteSession(sessionId);
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere((session) => session.id == sessionId);
        if (_sessionId == sessionId) {
          _sessionId = null;
          _messages = [];
          _loadError = null;
          _input.clear();
          _resumeCache.clear();
        }
      });
    } catch (error) {
      if (mounted) _notice(FriendlyError.message(error));
    } finally {
      if (mounted) setState(() => _loadingMessages = false);
    }
  }

  void _newSession() {
    _input.clear();
    _resumeCache.clear();
    setState(() {
      _sessionId = null;
      _messages = [];
      _loadError = null;
    });
  }

  Future<void> _send(String value) async {
    final question = value.trim();
    if (question.isEmpty || _busy || _loadError != null) return;
    if (question.runes.length > 4000) {
      _notice('请输入 1 到 4000 字的采购诉求');
      return;
    }
    FocusScope.of(context).unfocus();
    final cancel = CancelToken();
    final user = _Entry(isUser: true, content: question);
    final reply = _Entry(status: '正在为你挑选合适的作品…');
    _input.clear();
    setState(() {
      _turn = cancel;
      _messages.addAll([user, reply]);
    });
    _scrollToLatest();
    try {
      final repository = _repository;
      if (_sessionId == null) {
        final session = await repository.createSession();
        if (!mounted) return;
        setState(() {
          _sessionId = session.id;
          _sessions = [session, ..._sessions].take(30).toList();
        });
      }
      if (cancel.isCancelled) {
        setState(() {
          _messages.remove(user);
          reply.notice = '已停止生成';
          _input.text = question;
        });
        return;
      }
      final id = _sessionId!;
      await repository.chat(id, question, cancelToken: cancel,
          onEvent: (event) {
        if (!mounted || !identical(_turn, cancel)) return;
        setState(() {
          _applyEvent(event, reply, id);
          if (event.event == 'error') {
            _showTurnError(
                user,
                reply,
                ApiException(
                  event.text('message'),
                  code: event.intValue('code'),
                ),
                cancelled: false);
          }
          if (event.event == 'done' || event.event == 'error') {
            reply.status = null;
            _turn = null;
          }
        });
      });
      if (mounted && cancel.isCancelled) {
        setState(() {
          reply.cards.clear();
          reply.notice = '已停止生成';
        });
      }
    } catch (error) {
      if (!mounted || !identical(_turn, cancel)) return;
      setState(() =>
          _showTurnError(user, reply, error, cancelled: cancel.isCancelled));
    } finally {
      if (mounted && identical(_turn, cancel)) {
        setState(() {
          reply.status = null;
          _turn = null;
        });
      }
    }
  }

  void _showTurnError(_Entry user, _Entry reply, Object error,
      {required bool cancelled}) {
    final code = error is ApiException ? error.code : null;
    reply.cards.clear();
    reply.limited = code == 429;
    reply.notice = cancelled
        ? '已停止生成'
        : reply.limited
            ? sourcingLimitMessage
            : FriendlyError.message(error);
    if (reply.limited || code == 409 || _sessionId == null) {
      _messages.remove(user);
      if (_input.text.isEmpty) _input.text = user.content;
    }
  }

  void _applyEvent(AiSseEvent event, _Entry reply, int id) {
    switch (event.event) {
      case 'step':
      case 'tool_call':
      case 'tool_result':
        reply.status = '正在为你挑选合适的作品…';
      case 'delta':
        reply.content += event.text('text');
      case 'card':
        final data = event.payload;
        if (data != null) reply.cards.add(SourcingCard.fromJson(data));
      case 'done':
        final title = event.text('sessionTitle');
        if (title.isNotEmpty) {
          _sessions = [
            SourcingSession(id, title),
            ..._sessions.where((session) => session.id != id),
          ];
        }
    }
  }

  Future<void> _contactPlatform() async {
    if (_contacting) return;
    setState(() => _contacting = true);
    try {
      final chat = await ref.read(chatRepositoryProvider).createAdminSession(
            businessType: 'GENERAL',
            businessName: '平台沟通',
          );
      if (mounted) context.push(RoutePath.chatDetail(chat.session.sessionId));
    } catch (error) {
      if (mounted) _notice(FriendlyError.message(error));
    } finally {
      if (mounted) setState(() => _contacting = false);
    }
  }

  void _scrollToLatest() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final sessionTitle = _sessions
        .where((session) => session.id == _sessionId)
        .firstOrNull
        ?.title;

    return AppPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          title: Row(
            children: [
              const _AgentAvatar(size: 32),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'AI 选本顾问',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      sessionTitle ?? '在线 · 智能检索书城好本',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                        color: AppColors.text3,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '新建对话',
              onPressed: _busy ? null : _newSession,
              icon: const Icon(Icons.add_comment_outlined, size: 21),
            ),
            IconButton(
              tooltip: '历史会话',
              onPressed: _busy ? null : _historySheet,
              icon: const Icon(Icons.history_rounded, size: 22),
            ),
            const SizedBox(width: 4),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(
              height: 1,
              color: AppColors.divider.withOpacity(0.7),
            ),
          ),
        ),
        body: Column(
          children: [
            Expanded(child: _timeline()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _timeline() {
    if (_loadingMessages) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.primary,
          ),
        ),
      );
    }
    if (_loadError case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.text2),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _sessionId == null
                    ? _newSession
                    : () => _loadSessionMessages(_sessionId!),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(100, 36),
                ),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_messages.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
        children: [
          _WelcomeBubble(
            greeting: _welcomeGreeting,
            prompts: _prompts,
            showPrompts: true,
            onPromptTap: _busy ? null : _send,
          ),
        ],
      );
    }
    return ListView.builder(
      reverse: true,
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      itemCount: _messages.length + 1,
      itemBuilder: (_, index) {
        if (index == _messages.length) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 16),
            child: _WelcomeBubble(
              greeting: _welcomeGreeting,
              prompts: _prompts,
              showPrompts: false,
            ),
          );
        }
        final entry = _messages[_messages.length - index - 1];
        return _MessageView(
          key: ObjectKey(entry),
          message: entry,
          onContact: _contacting ? null : _contactPlatform,
        );
      },
    );
  }

  Widget _composer() => Container(
        decoration: const BoxDecoration(
          color: AppColors.card,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 4000,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.text1,
                      height: 1.4,
                    ),
                    decoration: InputDecoration(
                      hintText: '说说你想找什么题材、预算或集数…',
                      hintStyle: const TextStyle(
                        fontSize: 14,
                        color: AppColors.placeholder,
                      ),
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.fill,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_turn case final turn?)
                  OutlinedButton(
                    onPressed: turn.cancel,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      side: const BorderSide(color: AppColors.divider),
                      foregroundColor: AppColors.text1,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(21),
                      ),
                    ),
                    child: const Text('停止生成'),
                  )
                else
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _input,
                    builder: (_, value, __) {
                      final enabled = !_busy &&
                          _loadError == null &&
                          value.text.trim().isNotEmpty;
                      return FilledButton(
                        onPressed: enabled ? () => _send(value.text) : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 42),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.fill,
                          foregroundColor: Colors.white,
                          disabledForegroundColor: AppColors.text3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(21),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('发送'),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      );
}

class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar({this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.12),
      decoration: BoxDecoration(
        color: AppColors.card,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.divider),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Image.asset(
        'assets/images/sourcing_agent_bubble.png',
        fit: BoxFit.contain,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// 智能体默认欢迎语气泡 + 快捷提问引导。
class _WelcomeBubble extends StatelessWidget {
  const _WelcomeBubble({
    required this.greeting,
    required this.prompts,
    required this.showPrompts,
    this.onPromptTap,
  });

  final String greeting;
  final List<String> prompts;
  final bool showPrompts;
  final ValueChanged<String>? onPromptTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AgentAvatar(size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: AppColors.divider.withOpacity(0.6)),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '这次想找什么样的剧本？',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  greeting,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: AppColors.text2,
                    height: 1.55,
                  ),
                ),
                if (showPrompts) ...[
                  const SizedBox(height: 12),
                  Divider(
                    height: 1,
                    color: AppColors.divider.withOpacity(0.7),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '你可以直接问我',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < prompts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _PromptChip(
                      text: prompts[i],
                      onTap: onPromptTap == null
                          ? null
                          : () => onPromptTap!(prompts[i]),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.warmGray,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.text1,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_ios_rounded,
                size: 12,
                color: AppColors.text3,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Entry {
  _Entry(
      {this.isUser = false,
      this.content = '',
      this.status,
      this.notice,
      this.limited = false,
      List<SourcingCard>? cards})
      : cards = List<SourcingCard>.of(cards ?? const []);
  final bool isUser;
  String content;
  String? status;
  String? notice;
  bool limited;
  final List<SourcingCard> cards;

  factory _Entry.fromHistory(SourcingMessage row) =>
      _Entry(isUser: row.isUser, content: row.content, cards: row.cards);

  factory _Entry.clone(_Entry source) => _Entry(
        isUser: source.isUser,
        content: source.content,
        status: source.status,
        notice: source.notice,
        limited: source.limited,
        cards: source.cards,
      );
}

final _retrievalTraceSignal = RegExp(
  r'scanLimited|扫描上限|按以下路径检索|真实标签\s*ID|无标签宽检索|工具要求必须|标签体系|检索方式\s*\||检索结论|检索边界|workId|tradeType|requiresLicenseType',
  caseSensitive: false,
);

const _gentleNotFoundReply =
    '抱歉，目前书城里暂时还没有找到特别符合你要求的现成剧本呢。\n\n'
    '你可以试试换一个相近的题材，或适当放宽预算和集数条件再找找；如果有明确想法，也可以告诉我，我来帮你整理一份定制需求交给平台运营跟进。';

String _conciseWorksLeadIn(List<SourcingCard> cards) {
  final workListCard =
      cards.where((card) => card.type == 'work_list').firstOrNull;
  final hasComparison = cards.any((card) => card.type == 'work_comparison');
  final count = workListCard == null
      ? 0
      : sourcingRows(workListCard.payload['works']).length;
  if (count > 0 && hasComparison) {
    return '为你筛选出 $count 部推荐作品，下方可左右滑动查看书籍卡片与多作品对比，点击封面即可进入详情页。';
  }
  if (count > 0) {
    return '为你找到了 $count 部推荐作品，下方可左右滑动查看，点击任意书籍卡片即可进入详情主页。';
  }
  return '已为你整理好候选作品对比，点击下方封面或按钮可查看详情或发起询盘。';
}

bool _isVerboseOrTechnical(String text) {
  if (text.isEmpty) return false;
  if (_retrievalTraceSignal.hasMatch(text)) return true;
  if (text.contains('|') && text.contains('---')) return true;
  final nonEmptyLines =
      text.split('\n').where((line) => line.trim().isNotEmpty).length;
  return nonEmptyLines > 2 || text.runes.length > 90;
}

/// 过滤大模型偶发泄露的工具调用标记（DeepSeek DSML / XML）与内部检索过程表格/术语。
String sanitizeAgentDisplayText(String raw) {
  if (raw.isEmpty) return '';
  var cleaned = raw
      .replaceAll(
        RegExp(
          r'<[｜|]DSML[｜|]function_calls\b[^>]*>[\s\S]*?(?:</[｜|]DSML[｜|]function_calls>|$)',
        ),
        '',
      )
      .replaceAll(
        RegExp(r'</?[｜|]DSML[｜|][^>]*>|<[｜|]DSML[｜|][\s\S]*$'),
        '',
      )
      .replaceAll(
        RegExp(
          r'<(?:function_calls|tool_call|think)\b[^>]*>[\s\S]*?(?:</(?:function_calls|tool_call|think)>|$)',
          caseSensitive: false,
        ),
        '',
      )
      .replaceAll(
        RegExp(
          r'</?(?:function_calls|tool_call|invoke|parameter|think)\b[^>]*>',
          caseSensitive: false,
        ),
        '',
      );

  // 去掉误泄露给用户的内部检索过程表格和术语行
  final lines = cleaned.split('\n');
  final kept = <String>[];
  var skippingTraceTable = false;
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.contains('|') &&
        (trimmed.contains('检索方式') || trimmed.contains('标签 1') || trimmed.contains('无标签宽检索'))) {
      skippingTraceTable = true;
      continue;
    }
    if (skippingTraceTable) {
      if (trimmed.contains('|') || trimmed.isEmpty) continue;
      skippingTraceTable = false;
    }
    if (RegExp(r'scanLimited|扫描上限|真实标签\s*ID|无标签宽检索|工具要求必须', caseSensitive: false)
        .hasMatch(trimmed)) {
      continue;
    }
    kept.add(line);
  }

  return kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// 面向用户展示的最终文案：
/// - 若已返回推荐作品 / 作品对比卡片：上方文字仅保留 1～2 行简洁导语，
///   当服务端返回长篇报告或内部技术字段时自动收敛为一两行温和引导；
/// - 若未找到作品且返回内部排查报告：自动收敛为温和友好的未找到提示。
String resolveAgentDisplayText(
  String raw, {
  required List<SourcingCard> cards,
  required bool isStreaming,
}) {
  final hasWorkCards = cards.any(
    (card) => card.type == 'work_list' || card.type == 'work_comparison',
  );
  final hasDemandBrief = cards.any((card) => card.type == 'demand_brief');
  final cleaned = sanitizeAgentDisplayText(raw);

  if (hasWorkCards && !hasDemandBrief) {
    if (isStreaming) {
      return _isVerboseOrTechnical(raw) || _isVerboseOrTechnical(cleaned)
          ? ''
          : cleaned;
    }
    if (cleaned.isEmpty ||
        _isVerboseOrTechnical(raw) ||
        _isVerboseOrTechnical(cleaned)) {
      return _conciseWorksLeadIn(cards);
    }
    return cleaned;
  }

  final hasStructuredResult = cards.isNotEmpty;
  final isTraceDump = _retrievalTraceSignal.hasMatch(raw);
  if (isStreaming && isTraceDump && !hasStructuredResult) {
    return '';
  }
  if (!isStreaming && !hasStructuredResult && isTraceDump) {
    return _gentleNotFoundReply;
  }
  return cleaned;
}

class _MessageView extends StatelessWidget {
  const _MessageView({super.key, required this.message, this.onContact});

  final _Entry message;
  final VoidCallback? onContact;

  @override
  Widget build(BuildContext context) {
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          margin: const EdgeInsets.only(bottom: 14, left: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
              bottomRight: Radius.circular(4),
            ),
          ),
          child: SelectableText(
            message.content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    final displayCards = mergeSourcingCards(message.cards);
    final displayText = resolveAgentDisplayText(
      message.content,
      cards: displayCards,
      isStreaming: message.status != null,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _AgentAvatar(size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (message.status case final status?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(16),
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                          border: Border.all(
                            color: AppColors.divider.withOpacity(0.7),
                          ),
                          boxShadow: AppColors.cardShadow,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Semantics(
                                liveRegion: true,
                                child: Text(
                                  status,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: AppColors.text2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (displayText.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border.all(
                        color: AppColors.divider.withOpacity(0.6),
                      ),
                      boxShadow: AppColors.cardShadow,
                    ),
                    child: _AgentMarkdown(text: displayText),
                  ),
                for (final card in displayCards)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: SourcingCardView(card: card),
                  ),
                if (message.notice case final notice?)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warmGray,
                      borderRadius: BorderRadius.circular(AppRadius.r),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                notice,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.text1,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (message.limited) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: onContact,
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                backgroundColor: AppColors.card,
                                foregroundColor: AppColors.text1,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: const BorderSide(
                                    color: AppColors.divider,
                                  ),
                                ),
                              ),
                              child: const Text('联系平台客服'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AgentMarkdown extends StatelessWidget {
  const _AgentMarkdown({required this.text});

  final String text;
  static final _heading = RegExp(r'^#{1,6}\s+');
  static final _bullet = RegExp(r'^(\s*)[-*+]\s+');
  static final _strong = RegExp(r'\*\*([^*\n]+)\*\*');
  static final _tableRule =
      RegExp(r'^\s*\|?\s*:?-{3,}:?\s*(?:\|\s*:?-{3,}:?\s*)+\|?\s*$');

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final blocks = <Widget>[];
    final paragraph = <TextSpan>[];
    void flushText() {
      if (paragraph.isEmpty) return;
      blocks.add(
        SelectableText.rich(
          TextSpan(
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.text1,
              height: 1.6,
            ),
            children: List.of(paragraph),
          ),
        ),
      );
      paragraph.clear();
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (i + 1 < lines.length &&
          line.contains('|') &&
          _tableRule.hasMatch(lines[i + 1])) {
        flushText();
        final header = _tableCells(line);
        final rows = <List<String>>[header];
        i++;
        while (i + 1 < lines.length && lines[i + 1].contains('|')) {
          rows.add(_tableCells(lines[++i]));
        }
        blocks.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Table(
                  border: TableBorder.all(color: AppColors.divider, width: 0.7),
                  defaultColumnWidth: const FixedColumnWidth(116),
                  children: [
                    for (var r = 0; r < rows.length; r++)
                      TableRow(
                        decoration: r == 0
                            ? const BoxDecoration(color: AppColors.fill)
                            : null,
                        children: [
                          for (var c = 0; c < header.length; c++)
                            Padding(
                              padding: const EdgeInsets.all(7),
                              child: Text(
                                c < rows[r].length ? rows[r][c] : '',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.text1,
                                  fontWeight: r == 0
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        continue;
      }
      final heading = _heading.hasMatch(line);
      final body = line.replaceFirst(_heading, '').replaceFirstMapped(
            _bullet,
            (match) => '${match.group(1)}• ',
          );
      final children = <TextSpan>[];
      var offset = 0;
      for (final match in _strong.allMatches(body)) {
        children.add(TextSpan(text: body.substring(offset, match.start)));
        children.add(TextSpan(
            text: match.group(1),
            style: const TextStyle(fontWeight: FontWeight.w600)));
        offset = match.end;
      }
      children.add(TextSpan(text: body.substring(offset)));
      if (i < lines.length - 1) children.add(const TextSpan(text: '\n'));
      paragraph.add(TextSpan(
          children: children,
          style: heading
              ? const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text1,
                )
              : null));
    }
    flushText();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: blocks);
  }

  static List<String> _tableCells(String line) => line
      .trim()
      .replaceFirst(RegExp(r'^\|'), '')
      .replaceFirst(RegExp(r'\|$'), '')
      .split('|')
      .map((cell) => cell.trim())
      .toList();
}
