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
/// 公开页，游客可读。四种 tab 即后端 type：热门（浏览量）/ 收藏 / 交易热度（销量）/ 评分。
class RankingPage extends ConsumerStatefulWidget {
  const RankingPage({super.key, this.type});

  /// 初始榜单类型（来自首页榜单预览的当前 tab）。
  final String? type;

  @override
  ConsumerState<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends ConsumerState<RankingPage> {
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
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('作品榜单')),
      body: Column(
        children: [
          Container(
            color: AppColors.card,
            child: FilterChipBar(
              items: [
                for (final type in RankingType.all)
                  FilterChipItem(
                    label: type.label,
                    selected: type.code == _type,
                    onTap: () => setState(() => _type = type.code),
                  ),
              ],
            ),
          ),
          Expanded(
            child: rankingAsync.when(
              loading: () => const LoadingView(message: '加载中'),
              error: (error, _) => ErrorView(
                message: error is ApiException ? error.message : '加载失败，请稍后重试',
                onRetry: () => ref.invalidate(rankingProvider(_type)),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return const EmptyView(message: '榜单暂无数据', icon: Icons.leaderboard_outlined);
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(rankingProvider(_type));
                    await ref.read(rankingProvider(_type).future);
                  },
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return RankingRow(
                        item: item,
                        scoreText: _scoreText(item),
                        onTap: () => context.push(RoutePath.workDetailUrl(item.workId)),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _scoreText(RankingItem item) =>
      _type == 'rating' ? '${item.score.toStringAsFixed(1)} 分' : '${item.score.toInt()}';
}