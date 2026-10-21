import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';
import '../widgets/bookstore_widgets.dart';

/// 作品榜单（B 模块，接口 2.7.7 作品榜单）。
///
/// 公开页，游客可读。五个 tab 即后端 type：热门（近 7 天阅读）/ 收藏（近 7 天收藏）/
/// 交易热度（近 7 天订单）/ 评分（贝叶斯加权）/ 新书（近 30 天上架）。
class RankingPage extends ConsumerStatefulWidget {
  const RankingPage({super.key, this.type});

  /// 初始榜单类型（来自首页榜单预览的当前 tab）。
  final String? type;

  @override
  ConsumerState<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends ConsumerState<RankingPage> {
  /// 与 content_providers.dart 中 rankingProvider 请求的 limit 保持一致；
  /// 后端榜单接口仅支持 limit、无分页，故前端不做伪分页，仅在页脚提示展示范围。
  static const int _rankingLimit = 20;

  late String _type;

  @override
  void initState() {
    super.initState();
    _type = RankingType.of(widget.type).code;
  }

  @override
  Widget build(BuildContext context) {
    final rankingAsync = ref.watch(rankingProvider(_type));
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(title: const Text('作品榜单')),
      body: Column(
        children: [
          // 筛选条不再铺白色通栏：顶栏透明后，白色色块会在渐变上形成割裂感，
          // 直接让胶囊浮在页面背景上（与首页榜单卡片内的胶囊视觉一致）。
          FilterChipBar(
            items: [
              for (final type in RankingType.all)
                FilterChipItem(
                  label: type.label,
                  selected: type.code == _type,
                  onTap: () => setState(() => _type = type.code),
                ),
            ],
          ),
          Expanded(
            child: rankingAsync.when(
              loading: () => const LoadingView(message: '加载中'),
              error: (error, _) => ErrorView(
                message: error is ApiException ? error.message : '加载失败，请稍后重试',
                onRetry: () => ref.invalidate(rankingProvider(_type)),
              ),
              data: (payload) {
                final items = payload.list;
                if (items.isEmpty) {
                  return const EmptyView(message: '榜单暂无数据', icon: Icons.leaderboard_outlined);
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(rankingProvider(_type));
                    await ref.read(rankingProvider(_type).future);
                  },
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      // 前三名领奖台
                      if (items.isNotEmpty)
                        _Top3Podium(
                          items: items.take(3).toList(),
                          scoreText: _scoreText,
                          onTap: (item) =>
                              context.push(RoutePath.workDetailUrl(item.workId)),
                        ),
                      // 第 4 名以后
                      for (var i = 3; i < items.length; i++)
                        RankingRow(
                          item: items[i],
                          scoreText: _scoreText(items[i]),
                          onTap: () => context
                              .push(RoutePath.workDetailUrl(items[i].workId)),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Text(
                          payload.updatedAt.isEmpty
                              ? '榜单仅展示热度前 $_rankingLimit 名'
                              : '榜单仅展示热度前 $_rankingLimit 名\n更新时间：${payload.updatedAt}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.text3),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _scoreText(RankingItem item) => _type == 'rating'
      ? '${item.score.toStringAsFixed(1)} 分'
      : _formatThousands(item.score);

  /// 千分位分隔：1234567 → 1,234,567（项目未引入 intl，手写分隔避免新增依赖）。
  String _formatThousands(num value) {
    final digits = value.toInt().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '$buffer';
  }
}

/// 前三名领奖台：2 - 1 - 3 横向排列，冠军居中且更大。
class _Top3Podium extends StatelessWidget {
  const _Top3Podium({
    required this.items,
    required this.scoreText,
    required this.onTap,
  });

  final List<RankingItem> items;
  final String Function(RankingItem) scoreText;
  final ValueChanged<RankingItem> onTap;

  static const List<int> _order = [1, 0, 2]; // 显示顺序：2、1、3

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withOpacity(0.08),
            AppColors.card,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final idx in _order)
            if (idx < items.length)
              Expanded(
                child: _PodiumColumn(
                  item: items[idx],
                  isChampion: items[idx].rankNo == 1,
                  scoreText: scoreText(items[idx]),
                  onTap: () => onTap(items[idx]),
                ),
              ),
        ],
      ),
    );
  }
}

/// 领奖台单列（封面 + 排名徽章 + 标题信息）。
class _PodiumColumn extends StatelessWidget {
  const _PodiumColumn({
    required this.item,
    required this.isChampion,
    required this.scoreText,
    required this.onTap,
  });

  final RankingItem item;
  final bool isChampion;
  final String scoreText;
  final VoidCallback onTap;

  Color get _medalColor {
    switch (item.rankNo) {
      case 1:
        return const Color(0xFFFFB300); // 金
      case 2:
        return const Color(0xFF9E9E9E); // 银
      default:
        return const Color(0xFFCD7F32); // 铜
    }
  }

  @override
  Widget build(BuildContext context) {
    final coverW = isChampion ? 82.0 : 66.0;
    final coverH = isChampion ? 114.0 : 92.0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 封面 + 排名徽章
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: WorkCover(
                    url: item.cover,
                    width: coverW,
                    height: coverH,
                  ),
                ),
                Positioned(
                  top: -2,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: _medalColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _medalColor.withOpacity(0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${item.rankNo}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title.isEmpty ? '未命名作品' : item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isChampion ? 14 : 13,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.authorName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11, color: AppColors.text3),
            ),
            const SizedBox(height: 4),
            Text(
              scoreText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: isChampion ? 13 : 12,
                fontWeight: FontWeight.w700,
                color: _medalColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}