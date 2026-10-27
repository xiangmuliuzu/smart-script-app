import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/chat_models.dart';
import '../data/chat_providers.dart';

/// 交易会话列表页
///
/// 只显示交易类型的会话。
class TradeSessionListPage extends ConsumerStatefulWidget {
  const TradeSessionListPage({super.key});

  @override
  ConsumerState<TradeSessionListPage> createState() => _TradeSessionListPageState();
}

class _TradeSessionListPageState extends ConsumerState<TradeSessionListPage> {
  final Set<int> _expandedPeers = {};
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _keyword = _searchController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(chatUnreadCountProvider);
    final params = SessionListParams(sessionType: SessionType.trade);
    final asyncData = ref.watch(sessionListProvider(params));

    return Scaffold(
      appBar: AppBar(
        title: const Text('交易会话'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(54),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: '搜索会话/对方/消息',
                prefixIcon: const Icon(Icons.search, size: 20, color: AppColors.text3),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: AppColors.fill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(sessionListProvider(params)),
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
              return const EmptyView(message: '暂无交易会话');
            }
            final grouped = _groupByPeer(pagedData.list);
            grouped.sort((a, b) {
              if (a.hasUnread && !b.hasUnread) return -1;
              if (!a.hasUnread && b.hasUnread) return 1;
              return b.latestTime.compareTo(a.latestTime);
            });
            final kw = _keyword.toLowerCase();
            final visible = kw.isEmpty
                ? grouped
                : grouped.where((g) => g.matches(kw)).toList();
            if (visible.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [SizedBox(height: 80), EmptyView(message: '无匹配会话')],
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final group = visible[index];
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
      ),
    );
  }

  List<_PeerGroup> _groupByPeer(List<ChatSessionWithPeer> sessions) {
    final Map<int, _PeerGroup> groups = {};
    for (final s in sessions) {
      if (!groups.containsKey(s.peerId)) {
        groups[s.peerId] = _PeerGroup(
          peerId: s.peerId,
          peerName: s.peerName ?? '未知用户',
          peerAvatar: s.peerAvatar,
        );
      }
      groups[s.peerId]!.addSession(s);
    }
    return groups.values.toList();
  }
}

class _PeerGroup {
  final int peerId;
  final String peerName;
  final String? peerAvatar;
  final List<ChatSessionWithPeer> sessions = [];

  _PeerGroup({required this.peerId, required this.peerName, this.peerAvatar});

  void addSession(ChatSessionWithPeer s) => sessions.add(s);
  bool get hasUnread => sessions.any((s) => s.unread > 0);
  int get totalUnread => sessions.fold(0, (sum, s) => sum + s.unread);
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

  /// 客户端搜索匹配：对方昵称 / 会话业务名 / 最后一条消息，任一命中即保留（kw 已转小写）。
  bool matches(String kw) {
    if (peerName.toLowerCase().contains(kw)) return true;
    for (final s in sessions) {
      final biz = s.session.businessName?.toLowerCase();
      if (biz != null && biz.contains(kw)) return true;
      final last = s.session.lastMessage?.toLowerCase();
      if (last != null && last.contains(kw)) return true;
    }
    return false;
  }
}

class _PeerGroupTile extends StatelessWidget {
  final _PeerGroup group;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _PeerGroupTile({required this.group, required this.isExpanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isExpanded ? AppColors.fill : AppColors.card,
              border: Border(
                bottom: BorderSide(color: isExpanded ? AppColors.divider : Colors.transparent),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  backgroundImage: (group.peerAvatar != null && group.peerAvatar!.isNotEmpty)
                      ? NetworkImage(group.peerAvatar!)
                      : null,
                  child: (group.peerAvatar == null || group.peerAvatar!.isEmpty)
                      ? Text(group.peerName.characters.first,
                          style: const TextStyle(fontSize: 18, color: AppColors.primary))
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(group.peerName,
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
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
                      Text(group.latestMessage ?? '',
                          style: const TextStyle(fontSize: 13, color: AppColors.text3),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: AppColors.text3),
              ],
            ),
          ),
        ),
        if (isExpanded)
          ...group.sessions.map((s) => _SessionSubItem(session: s)),
      ],
    );
  }
}

class _SessionSubItem extends StatelessWidget {
  final ChatSessionWithPeer session;

  const _SessionSubItem({required this.session});

  @override
  Widget build(BuildContext context) {
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
            Container(
              width: 48,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                SessionType.label(session.session.sessionType),
                style: const TextStyle(fontSize: 10, color: AppColors.success),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (session.session.businessName != null)
                    Text(session.session.businessName!,
                        style: const TextStyle(fontSize: 13, color: AppColors.text1),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(session.session.lastMessage ?? '',
                      style: const TextStyle(fontSize: 12, color: AppColors.text3),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (session.session.lastMessageTime != null)
                  Text(_formatTime(session.session.lastMessageTime!),
                      style: const TextStyle(fontSize: 11, color: AppColors.text3)),
                if (session.unread > 0) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.danger,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('${session.unread}',
                        style: const TextStyle(fontSize: 9, color: Colors.white)),
                  ),
                ],
                if (session.session.isClosed) ...[
                  const SizedBox(height: 4),
                  const Text('已结束', style: TextStyle(fontSize: 10, color: AppColors.text3)),
                ],
              ],
            ),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }
}
