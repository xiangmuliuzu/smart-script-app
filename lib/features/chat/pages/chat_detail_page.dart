import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../trade/data/trade_models.dart';
import '../../trade/data/trade_providers.dart';
import '../../user_center/data/paged_data.dart';
import '../data/chat_models.dart';
import '../data/chat_providers.dart';
import '../widgets/negotiation_status_bar.dart';
import '../widgets/quote_input_card.dart';
import '../widgets/quote_message_bubble.dart';
import '../widgets/trade_template_sheet.dart';

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
  final _amountController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSending = false;
  int? _lastSentAmount; // 上次发送的报价金额（分），用于判断金额是否变化
  _TradeContext? _tradeContext; // 交易会话上下文

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
    _amountController.dispose();
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

    // 检查报价金额是否变化（仅 TRADE 会话）
    final int? newAmountFen = _parseAmountFen(_amountController.text.trim());
    final bool amountChanged = newAmountFen != null && newAmountFen != _lastSentAmount;

    setState(() => _isSending = true);
    try {
      // 金额变化时先发送报价
      if (amountChanged && _tradeContext != null) {
        final ctx = _tradeContext!;
        final repo = ref.read(tradeRepositoryProvider);
        final quote = Quote(
          inquiryId: ctx.inquiryId,
          amount: newAmountFen,
          // 无版权询盘不带授权类型：直接透传空值，后端沿用询盘口径，不注入默认脏数据
          licenseType: ctx.licenseType,
          role: ctx.isSeller ? 'seller' : 'buyer',
        );
        if (ctx.isSeller) {
          await repo.appCreateQuote(quote);
        } else {
          await repo.appCounterOffer(quote);
        }
        _lastSentAmount = newAmountFen;
        ref.invalidate(latestQuoteProvider(ctx.inquiryId));
      }

      final chatRepo = ref.read(chatRepositoryProvider);
      await chatRepo.sendMessage(widget.sessionId, content);
      _inputController.clear();
      // 刷新消息列表
      ref.invalidate(messagesProvider(widget.sessionId));
      // 标记已读
      await _markAsRead();
    } catch (e) {
      if (mounted) {
        showAppToast(context, '发送失败：$e');
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  int? _parseAmountFen(String text) {
    if (text.isEmpty) return null;
    final yuan = double.tryParse(text);
    if (yuan == null || yuan <= 0) return null;
    return (yuan * 100).round();
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
    final sessionAsync = ref.watch(sessionDetailProvider(widget.sessionId));

    // 提取会话信息
    final isTrade = sessionAsync.whenOrNull(
      data: (s) => s.session.sessionType == SessionType.trade,
    ) ?? false;
    final isDemand = sessionAsync.whenOrNull(
      data: (s) => s.session.sessionType == SessionType.demand,
    ) ?? false;
    final demandId = sessionAsync.whenOrNull(
      data: (s) => s.session.businessId,
    );
    final inquiryId = sessionAsync.whenOrNull(
      data: (s) => s.session.inquiryId,
    );

    // 对 TRADE 会话，加载询盘以确定买卖角色 + 预算/授权类型
    bool isBuyer = false;
    bool isSeller = false;
    int? budget;
    String? licenseType;
    if (isTrade && inquiryId != null) {
      final inquiryAsync = ref.watch(inquiryDetailProvider(inquiryId));
      inquiryAsync.whenOrNull(
        data: (inquiry) {
          isBuyer = inquiry.buyerId == currentUserId;
          isSeller = inquiry.sellerId == currentUserId;
          budget = inquiry.budget;
          licenseType = inquiry.licenseType;
          // 缓存交易上下文供发送消息时使用
          _tradeContext = _TradeContext(
            inquiryId: inquiryId,
            isBuyer: isBuyer,
            isSeller: isSeller,
            licenseType: licenseType,
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(sessionAsync),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        actions: [
          // 任务会话：右上角跳转任务详情
          if (isDemand && demandId != null)
            IconButton(
              icon: const Icon(Icons.assignment_outlined),
              tooltip: '查看任务详情',
              onPressed: () => context.push(RoutePath.demandDetailUrl(demandId)),
            ),
          // 交易会话：右上角跳转询盘详情
          if (isTrade && inquiryId != null)
            IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: '查看询盘详情',
              onPressed: () => context.push('${RoutePath.inquiryDetail}?id=$inquiryId'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 顶部议价状态栏（仅 TRADE 会话显示）
          if (isTrade && inquiryId != null)
            NegotiationStatusBar(
              inquiryId: inquiryId,
              currentUserId: currentUserId,
              isBuyer: isBuyer,
              isSeller: isSeller,
              budget: budget,
            ),
          // 消息列表
          Expanded(child: _buildMessageList(messagesAsync, currentUserId)),
          // 底部报价输入卡片（仅 TRADE 会话显示）
          if (isTrade && inquiryId != null)
            QuoteInputCard(
              inquiryId: inquiryId,
              amountController: _amountController,
              budget: budget,
            ),
          // 输入区（TRADE 会话用定型文按钮，ADMIN 会话用文本输入）
          _buildInputArea(sessionAsync, messagesAsync, isTrade, inquiryId, isBuyer, isSeller, licenseType),
        ],
      ),
    );
  }

  Widget _buildTitle(AsyncValue<ChatSessionWithPeer> sessionAsync) {
    final peerName = sessionAsync.whenOrNull(data: (s) => s.peerName);
    final subtitle = sessionAsync.whenOrNull(
      data: (s) => _sessionSourceLabel(s.session),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(peerName ?? '聊天', style: const TextStyle(fontSize: 17)),
        if (subtitle != null)
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
              maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }

  /// 根据会话类型与业务名称生成来源描述小字，显示具体是哪个交易/任务。
  String _sessionSourceLabel(ChatSession session) {
    final name = session.businessName;
    switch (session.sessionType) {
      case SessionType.trade:
        if (name != null && name.isNotEmpty) return '交易：《$name》';
        return '交易沟通';
      case SessionType.demand:
        if (name != null && name.isNotEmpty) return '任务：《$name》';
        return '任务沟通';
      case SessionType.admin:
      case SessionType.chat:
        if (name != null && name.isNotEmpty) return name;
        return '平台客服';
      default:
        if (name != null && name.isNotEmpty) return name;
        return '会话沟通';
    }
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
        if (pagedData.isEmpty) {
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
            // 报价/议价类系统消息渲染为卡片
            if (QuoteMessageBubble.isQuoteMessage(message)) {
              return QuoteMessageBubble(message: message);
            }
            return _MessageBubble(
              message: message,
              isMine: message.isMine(currentUserId),
            );
          },
        );
      },
    );
  }

  Widget _buildInputArea(
    AsyncValue<ChatSessionWithPeer> sessionAsync,
    AsyncValue<PagedData<ChatMessage>> messagesAsync,
    bool isTrade,
    int? inquiryId,
    bool isBuyer,
    bool isSeller,
    String? licenseType,
  ) {
    // 从会话详情判断是否已结束
    final isClosed = sessionAsync.whenOrNull(
      data: (s) => s.session.isClosed,
    ) ?? false;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        child: isClosed
            ? _buildClosedSessionBar()
            : isTrade
                ? _buildTradeInputArea(inquiryId, isBuyer, isSeller, licenseType)
                : _buildInputRow(),
      ),
    );
  }

  /// TRADE 会话输入区：左下角圆角「定型文」按钮（附加功能）+ 自由打字输入行
  Widget _buildTradeInputArea(
    int? inquiryId,
    bool isBuyer,
    bool isSeller,
    String? licenseType,
  ) {
    return Row(
      children: [
        // 左下角圆角「定型文」按钮：打开定型文选择面板（保留为附加功能）
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextButton.icon(
            onPressed: () {
              TradeTemplateSheet.show(
                context,
                sessionId: widget.sessionId,
                inquiryId: inquiryId ?? 0,
                isBuyer: isBuyer,
                isSeller: isSeller,
                licenseType: licenseType,
                onSent: () {
                  // 发送成功后刷新消息列表
                  ref.invalidate(messagesProvider(widget.sessionId));
                },
              );
            },
            icon: const Icon(Icons.notes, size: 18),
            label: const Text('定型文'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              backgroundColor: AppColors.primary.withOpacity(0.08),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
        // 自由打字输入行（与非交易会话同款：TextField + 发送）
        Expanded(child: _buildInputRow()),
      ],
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

/// 交易会话上下文（缓存询盘ID和角色信息，供发送消息时判断是否需要更新报价）
class _TradeContext {
  final int inquiryId;
  final bool isBuyer;
  final bool isSeller;
  final String? licenseType;

  const _TradeContext({
    required this.inquiryId,
    required this.isBuyer,
    required this.isSeller,
    this.licenseType,
  });
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
    return _buildChatBubble(context);
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

  Widget _buildChatBubble(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) _buildAvatar(context),
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
          if (isMine) _buildAvatar(context),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final avatar = CircleAvatar(
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
    if (message.senderId <= 0) return avatar;
    // 点击头像进入发送者个人主页（自己则进入自己的主页）
    return GestureDetector(
      onTap: () => context.push(RoutePath.userProfileUrl(message.senderId)),
      child: avatar,
    );
  }
}
