import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/data/content_repository.dart';
import '../../bookstore/data/bookstore_models.dart';
import '../../bookstore/data/content_providers.dart';
import '../../create/data/author_work_repository.dart';
import '../../create/data/author_work_providers.dart';
import '../../trade/data/trade_repository.dart';
import '../../trade/data/trade_providers.dart';
import '../data/chat_models.dart';
import '../data/chat_providers.dart';
import '../data/chat_repository.dart';

/// 聊天会话列表页
///
/// 顶部 Tab 切换：全部 / 交易会话 / 咨询会话。
/// 会话按对方分组，可折叠/展开。
/// 排序规则：未读优先 > 最新消息时间。
class ChatSessionListPage extends ConsumerStatefulWidget {
  const ChatSessionListPage({super.key});

  @override
  ConsumerState<ChatSessionListPage> createState() => _ChatSessionListPageState();
}

class _ChatSessionListPageState extends ConsumerState<ChatSessionListPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  /// 展开的分组（peerId 集合）
  final Set<int> _expandedPeers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String? get _currentSessionType {
    switch (_tabController.index) {
      case 0: return null;  // 全部
      case 1: return SessionType.trade;
      case 2: return SessionType.admin;
      default: return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatUnreadCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('线上会话'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primary,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: '全部'),
            Tab(text: '交易会话'),
            Tab(text: '咨询会话'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSessionList(null),
          _buildSessionList(SessionType.trade),
          _buildSessionList(SessionType.admin),
        ],
      ),
      // 咨询会话 Tab 显示发起咨询按钮
      floatingActionButton: _tabController.index == 2
          ? const _AnimatedConsultButton()
          : null,
    );
  }

  Widget _buildSessionList(String? sessionType) {
    final params = SessionListParams(sessionType: sessionType);
    final asyncData = ref.watch(sessionListProvider(params));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sessionListProvider(params));
      },
      child: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载失败：$e', style: const TextStyle(color: AppColors.text3)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(sessionListProvider(params)),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
        data: (pagedData) {
          if (pagedData.isEmpty) {
            return const EmptyView(message: '暂无会话记录');
          }
          
          // 按对方分组
          final grouped = _groupByPeer(pagedData.list);
          
          // 排序分组：未读优先 > 最新消息时间
          grouped.sort((a, b) {
            // 有未读的排前面
            if (a.hasUnread && !b.hasUnread) return -1;
            if (!a.hasUnread && b.hasUnread) return 1;
            // 按最新消息时间排
            return b.latestTime.compareTo(a.latestTime);
          });
          
          return ListView.builder(
            itemCount: grouped.length,
            itemBuilder: (context, index) {
              final group = grouped[index];
              final isExpanded = _expandedPeers.contains(group.peerId);
              return _PeerGroupTile(
                group: group,
                isExpanded: isExpanded,
                onToggle: () {
                  setState(() {
                    if (isExpanded) {
                      _expandedPeers.remove(group.peerId);
                    } else {
                      _expandedPeers.add(group.peerId);
                    }
                  });
                },
              );
            },
          );
        },
      ),
    );
  }

  /// 按对方分组
  List<_PeerGroup> _groupByPeer(List<ChatSessionWithPeer> sessions) {
    final Map<int, _PeerGroup> groups = {};
    
    for (final session in sessions) {
      final peerId = session.peerId;
      if (!groups.containsKey(peerId)) {
        groups[peerId] = _PeerGroup(
          peerId: peerId,
          peerName: session.peerName ?? '未知用户',
          peerAvatar: session.peerAvatar,
        );
      }
      groups[peerId]!.addSession(session);
    }
    
    return groups.values.toList();
  }
}

/// 对方分组数据
class _PeerGroup {
  final int peerId;
  final String peerName;
  final String? peerAvatar;
  final List<ChatSessionWithPeer> sessions = [];
  
  _PeerGroup({
    required this.peerId,
    required this.peerName,
    this.peerAvatar,
  });
  
  void addSession(ChatSessionWithPeer session) {
    sessions.add(session);
  }
  
  /// 是否有未读消息
  bool get hasUnread => sessions.any((s) => s.unread > 0);
  
  /// 总未读数
  int get totalUnread => sessions.fold(0, (sum, s) => sum + s.unread);
  
  /// 最新消息时间
  DateTime get latestTime {
    DateTime? latest;
    for (final s in sessions) {
      if (s.session.lastMessageTime != null) {
        if (latest == null || s.session.lastMessageTime!.isAfter(latest)) {
          latest = s.session.lastMessageTime;
        }
      }
    }
    return latest ?? DateTime(2000);
  }
  
  /// 最新消息内容
  String? get latestMessage {
    ChatSessionWithPeer? latest;
    for (final s in sessions) {
      if (s.session.lastMessageTime != null) {
        if (latest == null || s.session.lastMessageTime!.isAfter(latest.session.lastMessageTime!)) {
          latest = s;
        }
      }
    }
    return latest?.session.lastMessage;
  }
  
  /// 会话数量
  int get sessionCount => sessions.length;
}

/// 对方分组列表项（可折叠）
class _PeerGroupTile extends ConsumerWidget {
  const _PeerGroupTile({
    required this.group,
    required this.isExpanded,
    required this.onToggle,
  });

  final _PeerGroup group;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        // 分组头部
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isExpanded ? AppColors.fill : AppColors.card,
              border: Border(
                bottom: BorderSide(
                  color: isExpanded ? AppColors.divider : Colors.transparent,
                ),
              ),
            ),
            child: Row(
              children: [
                // 头像
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: (group.peerAvatar != null && group.peerAvatar!.isNotEmpty)
                      ? NetworkImage(group.peerAvatar!)
                      : null,
                  child: (group.peerAvatar == null || group.peerAvatar!.isEmpty)
                      ? Text(
                          group.peerName.characters.first,
                          style: const TextStyle(fontSize: 18, color: AppColors.primary),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                // 名称和最新消息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.peerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // 未读徽标
                          if (group.totalUnread > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.danger,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                group.totalUnread > 99 ? '99+' : '${group.totalUnread}',
                                style: const TextStyle(fontSize: 10, color: Colors.white),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        group.latestMessage ?? '',
                        style: const TextStyle(fontSize: 13, color: AppColors.text3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 展开/折叠图标
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppColors.text3,
                ),
              ],
            ),
          ),
        ),
        // 展开的会话列表
        if (isExpanded)
          ...group.sessions.map((session) => _SessionSubItem(
            session: session,
            peerName: group.peerName,
          )),
      ],
    );
  }
}

/// 展开后的单个会话项
class _SessionSubItem extends ConsumerWidget {
  const _SessionSubItem({
    required this.session,
    required this.peerName,
  });

  final ChatSessionWithPeer session;
  final String peerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push(RoutePath.chatDetail(session.session.sessionId)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: Row(
          children: [
            // 类型标签
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: SessionType.isAdminType(session.session.sessionType)
                    ? AppColors.primary.withOpacity(0.1)
                    : AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                SessionType.label(session.session.sessionType),
                style: TextStyle(
                  fontSize: 10,
                  color: SessionType.isAdminType(session.session.sessionType)
                      ? AppColors.primary
                      : AppColors.success,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            // 业务名称和最新消息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (session.session.businessName != null)
                    Text(
                      session.session.businessName!,
                      style: const TextStyle(fontSize: 13, color: AppColors.text1),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 2),
                  Text(
                    session.session.lastMessage ?? '',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // 时间和未读
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (session.session.lastMessageTime != null)
                  Text(
                    _formatTime(session.session.lastMessageTime!),
                    style: const TextStyle(fontSize: 11, color: AppColors.text3),
                  ),
                if (session.unread > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${session.unread}',
                      style: const TextStyle(fontSize: 9, color: Colors.white),
                    ),
                  ),
                ],
                if (session.session.isClosed) ...[
                  const SizedBox(height: 4),
                  const Text(
                    '已结束',
                    style: TextStyle(fontSize: 10, color: AppColors.text3),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inDays == 0) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else if (diff.inDays == 1) {
      return '昨天';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}天前';
    } else {
      return '${time.month}/${time.day}';
    }
  }
}

class _BizTypeOption {
  final String? value;
  final String label;
  final IconData icon;
  final bool direct;

  const _BizTypeOption({
    this.value,
    required this.label,
    required this.icon,
    required this.direct,
  });
}

/// 带动画效果的发起咨询按钮
class _AnimatedConsultButton extends StatefulWidget {
  const _AnimatedConsultButton();

  @override
  State<_AnimatedConsultButton> createState() => _AnimatedConsultButtonState();
}

class _AnimatedConsultButtonState extends State<_AnimatedConsultButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _heightScaleAnimation;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _heightScaleAnimation = Tween<double>(begin: 1.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _overlayEntry?.remove();
    super.dispose();
  }

  void _handleTap() {
    final RenderBox buttonBox = context.findRenderObject() as RenderBox;
    final buttonPosition = buttonBox.localToGlobal(Offset.zero);
    final buttonSize = buttonBox.size;
    final screenSize = MediaQuery.of(context).size;
    
    // 计算宽度和高度放大倍数（留边距）
    final margin = 16.0;
    final targetWidth = screenSize.width - margin * 2;
    final targetHeight = screenSize.height * 0.5;
    final targetWidthScale = targetWidth / buttonSize.width;
    final targetHeightScale = targetHeight / buttonSize.height;
    
    // 重新创建动画
    _heightScaleAnimation = Tween<double>(begin: 1.0, end: targetHeightScale).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final currentHeightScale = _heightScaleAnimation.value;
            final currentWidth = targetWidth;
            final currentHeight = buttonSize.height * currentHeightScale;
            
            // 从按钮位置向左右和向上扩展（留边距）
            final left = margin;
            final top = buttonPosition.dy + buttonSize.height - currentHeight;
            
            return Stack(
              children: [
                // 点击外部关闭
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _closeOverlay(),
                    behavior: HitTestBehavior.translucent,
                  ),
                ),
                // 从按钮位置扩展的表单
                Positioned(
                  left: left,
                  top: top,
                  child: Material(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      width: currentWidth,
                      height: currentHeight,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      // 只在动画完成后显示内容
                      child: _controller.value > 0.8
                          ? _ConsultFormContent(onClose: _closeOverlay)
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);

    _controller.forward().then((_) {
      // 动画完成后等待用户操作
    });
  }

  void _closeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _controller.reset();
  }

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: _handleTap,
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: const Text('发起咨询'),
    );
  }
}

/// 咨询表单内容（放大后显示）
class _ConsultFormContent extends ConsumerStatefulWidget {
  const _ConsultFormContent({required this.onClose});

  final VoidCallback onClose;

  @override
  ConsumerState<_ConsultFormContent> createState() => _ConsultFormContentState();
}

class _ConsultFormContentState extends ConsumerState<_ConsultFormContent> {
  String? _businessType = 'GENERAL';
  int? _businessId;
  String? _businessName;
  bool _isDropdownOpen = false;

  static const _businessTypes = [
    _BizTypeOption(value: 'GENERAL', label: '通用咨询', icon: Icons.help_outline, direct: true),
    _BizTypeOption(value: 'WORK', label: '作品相关', icon: Icons.menu_book_outlined, direct: false),
    _BizTypeOption(value: 'INQUIRY', label: '询盘相关', icon: Icons.receipt_long_outlined, direct: false),
    _BizTypeOption(value: 'ORDER', label: '订单相关', icon: Icons.shopping_bag_outlined, direct: false),
    _BizTypeOption(value: 'ACCOUNT', label: '账号问题', icon: Icons.person_outline, direct: true),
  ];

  bool get _canSubmit {
    final typeOpt = _businessTypes.firstWhere((t) => t.value == _businessType);
    if (typeOpt.direct) return true;
    return _businessId != null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '咨询类型',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 16),
          // 下拉框
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 下拉框头部
                InkWell(
                  onTap: () => setState(() => _isDropdownOpen = !_isDropdownOpen),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Icon(
                          _businessTypes.firstWhere((t) => t.value == _businessType).icon,
                          size: 20,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _businessTypes.firstWhere((t) => t.value == _businessType).label,
                            style: const TextStyle(fontSize: 15),
                          ),
                        ),
                        Icon(
                          _isDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          size: 24,
                        ),
                      ],
                    ),
                  ),
                ),
                // 下拉选项
                if (_isDropdownOpen)
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: Colors.grey[200]!)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _businessTypes.map((opt) {
                        final isSelected = opt.value == _businessType;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _businessType = opt.value;
                              _businessId = null;
                              _businessName = null;
                              _isDropdownOpen = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.primary.withOpacity(0.05) : null,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  opt.icon,
                                  size: 20,
                                  color: isSelected ? AppColors.primary : Colors.grey[600],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    opt.label,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: isSelected ? AppColors.primary : Colors.black87,
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check, color: AppColors.primary, size: 20),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          // 业务对象选择器（作品/询盘/订单）——下拉框展开时隐藏
          if (!_isDropdownOpen && (_businessType == 'WORK' || _businessType == 'INQUIRY' || _businessType == 'ORDER'))
            _BusinessObjectSelector(
              businessType: _businessType!,
              selectedId: _businessId,
              selectedName: _businessName,
              onSelected: (id, name) {
                setState(() {
                  _businessId = id;
                  _businessName = name;
                });
              },
            ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _canSubmit ? () => _submit() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                disabledBackgroundColor: Colors.white24,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('发起', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() async {
    try {
      final chatRepo = ref.read(chatRepositoryProvider);
      final session = await chatRepo.createAdminSession(
        businessType: _businessType,
        businessId: _businessId,
        businessName: _businessName,
      );
      if (mounted) {
        widget.onClose(); // 先关闭弹窗
        context.push(RoutePath.chatDetail(session.session.sessionId));
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '发起咨询失败：$e');
      }
    }
  }
}

/// 业务对象选择器（作品/询盘/订单）
class _BusinessObjectSelector extends ConsumerWidget {
  final String businessType;
  final int? selectedId;
  final String? selectedName;
  final void Function(int id, String name) onSelected;

  const _BusinessObjectSelector({
    required this.businessType,
    required this.selectedId,
    required this.selectedName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _getSelectorTitle(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 8),
          _buildSelectorContent(context, ref),
        ],
      ),
    );
  }

  String _getSelectorTitle() {
    switch (businessType) {
      case 'WORK':
        return '选择作品';
      case 'INQUIRY':
        return '选择询盘';
      case 'ORDER':
        return '选择订单';
      default:
        return '选择';
    }
  }

  Widget _buildSelectorContent(BuildContext context, WidgetRef ref) {
    switch (businessType) {
      case 'WORK':
        return _buildWorkSelector(context, ref);
      case 'INQUIRY':
        return _buildInquirySelector(context, ref);
      case 'ORDER':
        return _buildOrderSelector(context, ref);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWorkSelector(BuildContext context, WidgetRef ref) {
    final worksAsync = ref.watch(myWorksProvider('all'));
    return worksAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      )),
      error: (e, _) => Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('加载失败：$e', style: const TextStyle(color: Colors.red, fontSize: 13)),
      )),
      data: (works) {
        if (works.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('暂无作品', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
          ));
        }
        return _buildItemList(
          items: works.map((w) => _SelectorItem(id: w.workId, title: w.title, subtitle: w.status)).toList(),
          selectedId: selectedId,
          onSelected: onSelected,
        );
      },
    );
  }

  Widget _buildInquirySelector(BuildContext context, WidgetRef ref) {
    final inquiryAsync = ref.watch(inquiryListProvider(const InquiryListParams(
      role: 'buyer', pageNum: 1, pageSize: 50,
    )));
    return inquiryAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      )),
      error: (e, _) => Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('加载失败：$e', style: const TextStyle(color: Colors.red, fontSize: 13)),
      )),
      data: (pagedData) {
        final inquiries = pagedData.list;
        if (inquiries.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('暂无询盘', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
          ));
        }
        return _buildItemList(
          items: inquiries.where((i) => i.inquiryId != null).map((i) => _SelectorItem(
            id: i.inquiryId!,
            title: i.workTitle ?? '询盘#${i.inquiryId}',
            subtitle: i.status,
          )).toList(),
          selectedId: selectedId,
          onSelected: onSelected,
        );
      },
    );
  }

  Widget _buildOrderSelector(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(appOrderListProvider(const AppOrderListParams(
      role: 'buyer', pageNum: 1, pageSize: 50,
    )));
    return orderAsync.when(
      loading: () => const Center(child: Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      )),
      error: (e, _) => Center(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text('加载失败：$e', style: const TextStyle(color: Colors.red, fontSize: 13)),
      )),
      data: (pagedData) {
        final orders = pagedData.list;
        if (orders.isEmpty) {
          return Center(child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('暂无订单', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 13)),
          ));
        }
        return _buildItemList(
          items: orders.where((o) => o.orderId != null).map((o) => _SelectorItem(
            id: o.orderId!,
            title: o.workTitle ?? '订单#${o.orderId}',
            subtitle: o.status,
          )).toList(),
          selectedId: selectedId,
          onSelected: onSelected,
        );
      },
    );
  }

  Widget _buildItemList({
    required List<_SelectorItem> items,
    required int? selectedId,
    required void Function(int id, String name) onSelected,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 180),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = item.id == selectedId;
          return InkWell(
            onTap: () => onSelected(item.id, item.title),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.25) : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
                border: isSelected ? Border.all(color: Colors.white.withOpacity(0.5), width: 1.5) : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.subtitle ?? '',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7)),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: Colors.white, size: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SelectorItem {
  final int id;
  final String title;
  final String? subtitle;

  const _SelectorItem({required this.id, required this.title, this.subtitle});
}
