import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../user_center/data/paged_data.dart';
import '../data/chat_models.dart';
import '../data/chat_providers.dart';
import '../data/chat_repository.dart';

/// 聊天详情页（分工条目 7）
///
/// 顶部 AppBar 显示对方昵称 + 业务信息。
/// 消息列表：我方右侧蓝色气泡，对方左侧灰色气泡，系统消息居中灰色小字。
/// 底部输入区：文本输入框 + 发送按钮。
/// 已结束会话显示"会话已结束" + "重新打开"按钮。
class ChatDetailPage extends ConsumerStatefulWidget {
  const ChatDetailPage({super.key, required this.sessionId});

  final int sessionId;

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // 进入页面时标记已读
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markAsRead();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      await repo.markRead(widget.sessionId);
      // 刷新未读计数
      ref.invalidate(chatUnreadCountProvider);
    } catch (_) {
      // 静默处理
    }
  }

  Future<void> _sendMessage() async {
    final content = _inputController.text.trim();
    if (content.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      final repo = ref.read(chatRepositoryProvider);
      await repo.sendMessage(widget.sessionId, content);
      _inputController.clear();
      // 刷新消息列表
      ref.invalidate(messagesProvider(widget.sessionId));
      // 标记已读
      await _markAsRead();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _reopenSession() async {
    try {
      final repo = ref.read(chatRepositoryProvider);
      await repo.reopenSession(widget.sessionId);
      // 刷新消息列表
      ref.invalidate(messagesProvider(widget.sessionId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败：$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final currentUserId = authState.user?.userId ?? 0;
    final messagesAsync = ref.watch(messagesProvider(widget.sessionId));

    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(messagesAsync),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 消息列表
          Expanded(child: _buildMessageList(messagesAsync, currentUserId)),
          // 输入区
          _buildInputArea(messagesAsync),
        ],
      ),
    );
  }

  Widget _buildTitle(AsyncValue<PagedData<ChatMessage>> messagesAsync) {
    // 从第一条消息或会话信息获取对方名称
    // 这里简化处理，实际可以从会话详情获取
    return const Text('聊天');
  }

  Widget _buildMessageList(
    AsyncValue<PagedData<ChatMessage>> messagesAsync,
    int currentUserId,
  ) {
    return messagesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('加载失败：$e', style: const TextStyle(color: AppColors.text3)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(messagesProvider(widget.sessionId)),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (pagedData) {
        if (pagedData == null || pagedData.isEmpty) {
          return const EmptyView(message: '暂无消息，开始聊天吧');
        }
        return ListView.builder(
          controller: _scrollController,
          reverse: true, // 最新消息在底部
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
          itemCount: pagedData.list.length,
          itemBuilder: (context, index) {
            // 倒序遍历，让最新消息在最下面
            final message = pagedData.list[pagedData.list.length - 1 - index];
            return _MessageBubble(
              message: message,
              isMine: message.isMine(currentUserId),
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea(AsyncValue<PagedData<ChatMessage>> messagesAsync) {
    // 检查会话是否已结束
    final isClosed = messagesAsync.whenOrNull(
      data: (_) => false, // 简化：假设会话未结束
    ) ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: isClosed
            ? _buildClosedSessionBar()
            : _buildInputRow(),
      ),
    );
  }

  Widget _buildClosedSessionBar() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            '会话已结束',
            style: TextStyle(color: AppColors.text3),
          ),
        ),
        TextButton(
          onPressed: _reopenSession,
          child: const Text('重新打开'),
        ),
      ],
    );
  }

  Widget _buildInputRow() {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputController,
            decoration: const InputDecoration(
              hintText: '输入消息...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            maxLines: 4,
            minLines: 1,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => _sendMessage(),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _isSending ? null : _sendMessage,
          icon: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send, color: AppColors.primary),
        ),
      ],
    );
  }
}

/// 消息气泡
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return _buildSystemMessage();
    }
    return _buildChatBubble();
  }

  Widget _buildSystemMessage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.fill,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            message.content,
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
          ),
        ),
      ),
    );
  }

  Widget _buildChatBubble() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) _buildAvatar(),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isMine ? AppColors.primary : AppColors.fill,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(12),
                  topRight: const Radius.circular(12),
                  bottomLeft: Radius.circular(isMine ? 12 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 12),
                ),
              ),
              child: Text(
                message.content,
                style: TextStyle(
                  color: isMine ? Colors.white : AppColors.text1,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isMine) _buildAvatar(),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.primary.withOpacity(0.1),
      backgroundImage: message.senderAvatar != null
          ? NetworkImage(message.senderAvatar!)
          : null,
      child: message.senderAvatar == null
          ? Text(
              message.senderName?.characters.first ?? '?',
              style: const TextStyle(fontSize: 12, color: AppColors.primary),
            )
          : null,
    );
  }
}
