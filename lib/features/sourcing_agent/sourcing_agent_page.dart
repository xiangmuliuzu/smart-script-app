import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/network/friendly_error.dart';
import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../ai/data/ai_sse_parser.dart';
import '../chat/data/chat_providers.dart';
import 'sourcing_agent_cards.dart';
import 'sourcing_agent_repository.dart';

class SourcingAgentPage extends ConsumerStatefulWidget {
  const SourcingAgentPage({super.key});

  @override
  ConsumerState<SourcingAgentPage> createState() => _SourcingAgentPageState();
}

class _SourcingAgentPageState extends ConsumerState<SourcingAgentPage> {
  static const _prompts = [
    '预算 5 万以内，找 50～80 集竖屏悬疑反转短剧并对比',
    '帮我找适合出海投流的甜宠爽剧并检查版权状态',
    '库里没有合适的，帮我起草一份古装权谋定制剧本采购需求',
  ];

  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<SourcingSession> _sessions = [];
  List<_Entry> _messages = [];
  int? _sessionId;
  String? _loadError;
  bool _loading = true;
  bool _contacting = false;
  CancelToken? _turn;

  SourcingAgentRepository get _repository =>
      ref.read(sourcingAgentRepositoryProvider);
  bool get _busy => _loading || _turn != null;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    _turn?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory({int? sessionId, bool refreshList = true}) async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final repository = _repository;
      final sessions =
          refreshList ? await repository.listSessions() : _sessions;
      if (!mounted) return;
      final target = sessionId ??
          (sessions.any((session) => session.id == _sessionId)
              ? _sessionId
              : sessions.firstOrNull?.id);
      final rows = target == null
          ? const <SourcingMessage>[]
          : await repository.listMessages(target);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _sessionId = target;
        _messages = rows.map(_Entry.fromHistory).toList();
      });
      _scrollToLatest();
    } catch (error) {
      if (mounted) setState(() => _loadError = FriendlyError.message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _historySheet() async {
    final action = await showModalBottomSheet<({int sessionId, bool delete})>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: .62,
        child: Column(
          children: [
            const ListTile(title: Text('历史会话')),
            const Divider(height: 1),
            if (_sessions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('暂无历史会话'),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (_, index) {
                    final session = _sessions[index];
                    return ListTile(
                      title: Text(session.title),
                      selected: session.id == _sessionId,
                      onTap: () => Navigator.pop(
                          sheetContext, (sessionId: session.id, delete: false)),
                      trailing: IconButton(
                        tooltip: '删除会话',
                        icon: const Icon(Icons.delete_outline),
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
      await _loadHistory(sessionId: action.sessionId, refreshList: false);
    }
  }

  Future<void> _deleteSession(int sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除选本对话'),
        content: const Text('删除这段对话及其中的消息？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (!mounted || confirm != true || _busy) return;
    setState(() => _loading = true);
    try {
      await _repository.deleteSession(sessionId);
      if (!mounted) return;
      setState(() {
        _sessions.removeWhere((session) => session.id == sessionId);
        if (_sessionId == sessionId) {
          _sessionId = null;
          _messages = [];
          _input.clear();
        }
      });
    } catch (error) {
      if (mounted) _notice(FriendlyError.message(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _newSession() {
    _input.clear();
    setState(() {
      _sessionId = null;
      _messages = [];
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
    final reply = _Entry(status: '正在连接选本顾问…');
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
        reply.status = event.text('message');
      case 'tool_call':
        reply.tools.add(_ToolCall(event.text('callId'), event.text('label'),
            event.text('argsSummary')));
      case 'tool_result':
        for (final call in reply.tools.reversed) {
          if (call.id != event.text('callId')) continue;
          call.result = event.text('summary');
          break;
        }
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
    final title = _sessions
        .where((session) => session.id == _sessionId)
        .firstOrNull
        ?.title;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 选本顾问'),
        actions: [
          IconButton(
            tooltip: '新建对话',
            onPressed: _busy || _loadError != null ? null : _newSession,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: '历史会话',
            onPressed: _busy || _loadError != null ? null : _historySheet,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (title != null && !_loading && _loadError == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 3, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child:
                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            Expanded(child: _timeline()),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _timeline() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError case final error?) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error),
            TextButton(onPressed: _loadHistory, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        children: [
          Text('这次想找什么样的剧本？', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('告诉我题材、预算和集数，或描述定制采购要求。'),
          const SizedBox(height: 12),
          for (final prompt in _prompts)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: OutlinedButton(
                  onPressed: () => _send(prompt), child: Text(prompt)),
            ),
        ],
      );
    }
    return ListView.builder(
      reverse: true,
      controller: _scroll,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (_, index) {
        final entry = _messages[_messages.length - index - 1];
        return _MessageView(
          key: ObjectKey(entry),
          message: entry,
          onContact: _contacting ? null : _contactPlatform,
        );
      },
    );
  }

  Widget _composer() => Material(
        color: AppColors.card,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
                  decoration: const InputDecoration(
                    hintText: '输入题材、预算、集数或定制要求',
                    labelText: '采购诉求',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_turn case final turn?)
                OutlinedButton(
                    onPressed: turn.cancel, child: const Text('停止生成'))
              else
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (_, value, __) => FilledButton(
                    onPressed:
                        _busy || _loadError != null || value.text.trim().isEmpty
                            ? null
                            : () => _send(value.text),
                    child: const Text('发送'),
                  ),
                ),
            ],
          ),
        ),
      );
}

class _Entry {
  _Entry(
      {this.isUser = false,
      this.content = '',
      this.status,
      List<SourcingCard>? cards})
      : cards = List<SourcingCard>.of(cards ?? const []);
  final bool isUser;
  String content;
  String? status;
  String? notice;
  bool limited = false;
  final List<SourcingCard> cards;
  final tools = <_ToolCall>[];

  factory _Entry.fromHistory(SourcingMessage row) =>
      _Entry(isUser: row.isUser, content: row.content, cards: row.cards);
}

class _ToolCall {
  _ToolCall(this.id, this.label, this.arguments);
  final String id;
  final String label;
  final String arguments;
  String? result;
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
          margin: const EdgeInsets.only(bottom: 10, left: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(AppRadius.r)),
          child: SelectableText(message.content),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message.status case final status?)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                  liveRegion: true,
                  child: Text(status,
                      style: const TextStyle(color: AppColors.text2))),
            ),
          if (message.tools.isNotEmpty)
            ExpansionTile(
              title: const Text('查询过程'),
              tilePadding: EdgeInsets.zero,
              initiallyExpanded: message.status != null,
              children: [
                for (final tool in message.tools)
                  ListTile(
                    dense: true,
                    title: Text(tool.label),
                    subtitle: Text([
                      if (tool.arguments.isNotEmpty) tool.arguments,
                      if (tool.result != null) tool.result!,
                    ].join(' · ')),
                  ),
              ],
            ),
          if (message.content.isNotEmpty) _AgentMarkdown(text: message.content),
          for (final card in message.cards)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SourcingCardView(card: card),
            ),
          if (message.notice case final notice?)
            Card(
              margin: const EdgeInsets.only(top: 6),
              child: ListTile(
                title: Text(notice),
                subtitle: message.limited
                    ? Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                            onPressed: onContact, child: const Text('联系平台客服')),
                      )
                    : null,
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
      blocks.add(SelectableText.rich(TextSpan(children: List.of(paragraph))));
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
        blocks.add(SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            border: TableBorder.all(color: AppColors.divider),
            defaultColumnWidth: const FixedColumnWidth(116),
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(children: [
                  for (var c = 0; c < header.length; c++)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        c < rows[r].length ? rows[r][c] : '',
                        style: r == 0
                            ? const TextStyle(fontWeight: FontWeight.w600)
                            : null,
                      ),
                    ),
                ]),
            ],
          ),
        ));
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
            style: const TextStyle(fontWeight: FontWeight.bold)));
        offset = match.end;
      }
      children.add(TextSpan(text: body.substring(offset)));
      if (i < lines.length - 1) children.add(const TextSpan(text: '\n'));
      paragraph.add(TextSpan(
          children: children,
          style:
              heading ? const TextStyle(fontWeight: FontWeight.w700) : null));
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
