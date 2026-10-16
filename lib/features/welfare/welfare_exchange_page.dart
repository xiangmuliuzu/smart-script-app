import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../ai/data/ai_providers.dart';
import 'data/welfare_providers.dart';
import 'data/welfare_models.dart';
import '../../core/providers/auth_providers.dart';

/// AI 次数兑换页（App 端 E 模块）。
///
/// 页面结构（按用户确认方案）：
///   上方：灵活兑换表单（输入积分数，10 积分 = 1 次，只能积分换次数）
///   下方：兑换记录列表，兑换成功后实时刷新
class WelfareExchangePage extends ConsumerStatefulWidget {
  const WelfareExchangePage({super.key});

  @override
  ConsumerState<WelfareExchangePage> createState() => _WelfareExchangePageState();
}

class _WelfareExchangePageState extends ConsumerState<WelfareExchangePage> {
  final TextEditingController _pointsController = TextEditingController();
  bool _submitting = false;

  int get _enteredPoints => int.tryParse(_pointsController.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    // 每次进入兑换页都重拉 AI 余额/兑换比例，保证管理员改比例后 App 实时跟随
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(aiBalanceProvider);
    });
  }

  @override
  void dispose() {
    _pointsController.dispose();
    super.dispose();
  }

  Future<void> _exchange() async {
    final rate = ref.read(aiBalanceProvider).valueOrNull?.rate ?? 10;
    final points = _enteredPoints;
    if (points < rate) {
      showAppToast(context, '至少需要 $rate 积分才能兑换');
      return;
    }
    final quota = points ~/ rate;
    if (quota < 1) {
      showAppToast(context, '积分数不足，无法兑换');
      return;
    }
    setState(() => _submitting = true);
    try {
      final userId = ref.read(authControllerProvider).user?.userId ?? 0;
      final repo = ref.read(aiRepositoryProvider);
      final balance = await repo.exchange(
        userId: userId,
        points: points,
        idempotencyKey: 'app-exchange-$userId-${DateTime.now().millisecondsSinceEpoch}',
      );
      if (!mounted) return;
      showAppToast(context, '兑换成功，获得 $quota 次机会，剩余 $balance 次');
      // 实时刷新：兑换记录 + 资产栏 + 积分
      ref.invalidate(exchangeRecordsProvider);
      ref.invalidate(aiBalanceProvider);
      ref.invalidate(welfareAssetProvider);
      ref.invalidate(pointsBalanceProvider);
      _pointsController.clear();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '兑换失败：${_friendly(e)}');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = ref.watch(welfareAssetProvider);
    final records = ref.watch(exchangeRecordsProvider);
    final rate = ref.watch(aiBalanceProvider).valueOrNull?.rate ?? 10;
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('AI次数兑换'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([
          ref.refresh(exchangeRecordsProvider.future),
          ref.refresh(welfareAssetProvider.future),
        ]),
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            _balanceCard(asset),
            const SizedBox(height: 12),
            _exchangeCard(rate),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('兑换记录',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text1)),
                TextButton.icon(
                  onPressed: () =>
                      ref.refresh(exchangeRecordsProvider.future),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            records.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('记录加载失败，下拉重试')),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.history, size: 44, color: AppColors.text3),
                          SizedBox(height: 8),
                          Text('暂无兑换记录',
                              style: TextStyle(color: AppColors.text3)),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final r in list) ...[
                      _RecordTile(record: r),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// 兑换表单卡片。
  Widget _exchangeCard(int rate) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('兑换数量',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1)),
          const SizedBox(height: 12),
          TextField(
            controller: _pointsController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              hintText: '输入积分数',
              suffixText: '积分',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Text(
            '可兑换 AI 机会：${_enteredPoints ~/ rate} 次（$rate 积分 = 1 次，只能积分换次数）',
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              onPressed: _submitting || _enteredPoints ~/ rate < 1 ? null : _exchange,
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('立即兑换'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard(AsyncValue<({PointsBalance points, int aiAvailable})> asset) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
      ),
      child: asset.when(
        loading: () => const Text('资产加载中…',
            style: TextStyle(color: AppColors.text3)),
        error: (_, __) => const Text('资产加载失败',
            style: TextStyle(color: AppColors.text3)),
        data: (value) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _balanceItem('当前积分', '${value.points.balance}'),
            _balanceItem('AI 机会', '${value.aiAvailable}'),
            _balanceItem('累计获得', '${value.points.totalEarned}'),
          ],
        ),
      ),
    );
  }

  Widget _balanceItem(String label, String value) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.text1)),
        const SizedBox(height: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.text3)),
      ],
    );
  }
}

/// 兑换记录单条。
class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final ExchangeRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.cyanTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.swap_horiz,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.remark.isEmpty ? '积分兑换 AI 机会' : record.remark,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text1),
                ),
                const SizedBox(height: 2),
                Text(
                  record.createTime ?? '',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${record.amount} 次',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text('余额 ${record.balanceAfter} 次',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.text3)),
            ],
          ),
        ],
      ),
    );
  }
}

String _friendly(Object error) {
  final text = error.toString();
  if (text.contains('401') || text.contains('未登录')) return '登录已失效，请重新登录';
  if (text.contains('SocketException')) return '网络异常';
  return text.replaceAll('Exception: ', '').replaceAll('ApiException: ', '');
}
