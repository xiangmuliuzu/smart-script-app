import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/route_paths.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../core/providers/auth_providers.dart';
import 'data/welfare_models.dart';
import 'data/welfare_providers.dart';

/// 福利中心（App 端 E 模块）。
///
/// 布局（对标番茄小说「赚钱」页）：
///   顶部资产栏：积分余额 + AI 机会
///   右上角：积分明细 / AI 次数兑换
///   下方：福利任务列表 + 广告任务列表
class WelfareCenterPage extends ConsumerWidget {
  const WelfareCenterPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('福利中心'),
        backgroundColor: Colors.white,
        elevation: 0.5,
        actions: [
          TextButton.icon(
            onPressed: () => context.push(RoutePath.welfarePointsDetail),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('积分明细'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(welfareAssetProvider.future),
          ref.refresh(welfareTasksProvider.future),
          ref.refresh(adListProvider.future),
        ]),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: const [
            _AssetBar(),
            SizedBox(height: 12),
            _SectionTitle('福利任务'),
            _TaskList(),
            SizedBox(height: 12),
            _SectionTitle('广告任务'),
            _AdList(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

/// 顶部资产栏：积分余额 + AI 机会 + 兑换按钮。
class _AssetBar extends ConsumerWidget {
  const _AssetBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(welfareAssetProvider);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: asset.when(
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
        error: (_, __) => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text('资产加载失败，下拉刷新重试', style: TextStyle(color: Colors.white)),
          ),
        ),
        data: (value) => Row(
          children: [
            _AssetItem(label: '积分', value: '${value.points.balance}'),
          ],
        ),
      ),
    );
  }
}

class _AssetItem extends StatelessWidget {
  const _AssetItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(title,
          style: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text1)),
    );
  }
}

/// 福利任务列表。
class _TaskList extends ConsumerWidget {
  const _TaskList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(welfareTasksProvider);
    return tasks.when(
      loading: () => const _LoadingCard(),
      error: (_, __) => const _ErrorCard('任务加载失败'),
      data: (list) {
        if (list.isEmpty) return const _EmptyCard('暂无福利任务');
        return Column(
          children: [
            for (final task in list) _TaskCard(task: task),
          ],
        );
      },
    );
  }
}

class _TaskCard extends ConsumerStatefulWidget {
  const _TaskCard({required this.task});

  final WelfareTask task;

  @override
  ConsumerState<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends ConsumerState<_TaskCard> {
  bool _submitting = false;

  Future<void> _claim() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final userId = ref.read(authControllerProvider).user?.userId ?? 0;
      final repo = ref.read(welfareRepositoryProvider);
      final balance = await repo.claimTask(
        userId: userId,
        taskCode: widget.task.taskCode,
      );
      if (!mounted) return;
      showAppToast(context, '领取成功，积分 ${widget.task.rewardPoints}，当前余额 $balance');
      // 刷新资产与任务进度
      ref.invalidate(welfareAssetProvider);
      ref.invalidate(welfareTasksProvider);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '领取失败：${_friendly(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(task.taskName,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text1)),
                    const SizedBox(width: 8),
                    _TypeTag(task.typeLabel),
                  ],
                ),
                if (task.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(task.description,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.text3)),
                ],
                const SizedBox(height: 6),
                Text('奖励 +${task.rewardPoints} 积分',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.success)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _claimButton(task),
        ],
      ),
    );
  }

  Widget _claimButton(WelfareTask task) {
    final claimed = task.isClaimed == 1;
    final completed = task.isCompleted == 1 || task.progress >= task.targetCount;
    if (claimed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.fill,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text('已领取',
            style: TextStyle(fontSize: 12, color: AppColors.text3)),
      );
    }
    if (!completed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryTint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text('${task.progress}/${task.targetCount}',
            style:
                const TextStyle(fontSize: 12, color: AppColors.primary)),
      );
    }
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        minimumSize: const Size(64, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 13),
      ),
      onPressed: _submitting ? null : _claim,
      child: _submitting
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : const Text('领取'),
    );
  }
}

/// 广告任务列表。
class _AdList extends ConsumerWidget {
  const _AdList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ads = ref.watch(adListProvider);
    return ads.when(
      loading: () => const _LoadingCard(),
      error: (_, __) => const _ErrorCard('广告加载失败'),
      data: (list) {
        if (list.isEmpty) return const _EmptyCard('暂无广告任务');
        return Column(
          children: [
            for (final ad in list) _AdCard(ad: ad),
          ],
        );
      },
    );
  }
}

class _AdCard extends ConsumerStatefulWidget {
  const _AdCard({required this.ad});

  final AdTask ad;

  @override
  ConsumerState<_AdCard> createState() => _AdCardState();
}

class _AdCardState extends ConsumerState<_AdCard> {
  bool _submitting = false;

  Future<void> _watch() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final userId = ref.read(authControllerProvider).user?.userId ?? 0;
      final repo = ref.read(welfareRepositoryProvider);
      final result = await repo.adReward(userId: userId, adId: widget.ad.adId);
      if (!mounted) return;
      showAppToast(
          context, '奖励 ${result.rewardPoints} 积分，当前余额 ${result.balance}');
      ref.invalidate(welfareAssetProvider);
      ref.invalidate(adListProvider);
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '领取失败：${_friendly(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final remaining = ad.remainingToday;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.cyanTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.play_circle_outline,
                color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ad.adName,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
                const SizedBox(height: 4),
                Text(
                  '${ad.typeLabel} · 奖励 +${ad.rewardPoints} 积分 · 今日剩余 $remaining 次',
                  style: const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.warning,
              minimumSize: const Size(72, 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(fontSize: 13),
            ),
            onPressed: remaining <= 0 || _submitting ? null : _watch,
            child: _submitting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Text(remaining <= 0 ? '已达上限' : '看广告'),
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        boxShadow: AppColors.cardShadow,
      ),
      child: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        boxShadow: AppColors.cardShadow,
      ),
      child: Center(
        child: Text(text,
            style: const TextStyle(color: AppColors.text3, fontSize: 13)),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        boxShadow: AppColors.cardShadow,
      ),
      child: Center(
        child: Text(text,
            style: const TextStyle(color: AppColors.text3, fontSize: 13)),
      ),
    );
  }
}

class _TypeTag extends StatelessWidget {
  const _TypeTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(fontSize: 10, color: AppColors.primary)),
    );
  }
}

String _friendly(Object error) {
  final text = error.toString();
  if (text.contains('401') || text.contains('未登录')) return '登录已失效，请重新登录';
  if (text.contains('已领取') || text.contains('已达')) return text;
  if (text.contains('SocketException') || text.contains('连接失败')) return '网络异常';
  return text.replaceAll('Exception: ', '').replaceAll('ApiException: ', '');
}
