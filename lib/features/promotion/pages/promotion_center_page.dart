import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/promotion_models.dart';
import '../data/promotion_providers.dart';
import '../widgets/promotion_widgets.dart';

/// 作品推广中心：投放概览 + 状态筛选记录 + 底部「申请推广」。
class PromotionCenterPage extends ConsumerStatefulWidget {
  const PromotionCenterPage({super.key});

  @override
  ConsumerState<PromotionCenterPage> createState() =>
      _PromotionCenterPageState();
}

class _PromotionCenterPageState extends ConsumerState<PromotionCenterPage> {
  /// 状态 Tab（本地按派生文案筛选，避免多次请求）。
  static const List<_StatusTab> _tabs = [
    _StatusTab('全部', 'all'),
    _StatusTab('待审核', '待审核'),
    _StatusTab('待支付', '待支付'),
    _StatusTab('待生效', '待生效'),
    _StatusTab('投放中', '投放中'),
    _StatusTab('已结束', '已结束'),
  ];

  String _tab = 'all';

  /// 待支付锁坑倒计时每秒刷新（剩余时间按 lockExpireAt 实时计算）。
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myPromotionsProvider('all'));

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('作品推广'),
        actions: [
          TextButton(
            onPressed: () => showPromotionRulesSheet(context),
            child: const Text(
              '规则',
              style: TextStyle(fontSize: 13, color: AppColors.text2),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const LoadingView(message: '加载推广记录…'),
        error: (error, _) => ErrorView(
          message: error is ApiException ? error.message : '加载推广记录失败',
          onRetry: () => ref.invalidate(myPromotionsProvider),
        ),
        data: (page) => _buildContent(page.list),
      ),
      bottomNavigationBar: _buildApplyBar(),
    );
  }

  Widget _buildContent(List<PromotionApplication> all) {
    final filtered = _tab == 'all'
        ? all
        : all.where((item) => item.displayStatus == _tab).toList();

    return Column(
      children: [
        _buildHero(all),
        _buildTabs(),
        Expanded(
          child: RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _refresh,
            child: filtered.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 70),
                      EmptyView(
                        icon: Icons.campaign_outlined,
                        message: _tab == 'all'
                            ? '暂无推广记录，先申请一个推广位试试'
                            : '暂无「$_tab」的推广记录',
                      ),
                    ],
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 18),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return PromotionOrderCard(
                        item: item,
                        onTap: () => _openDetail(item.applyId),
                        onPay: item.canPay ? () => _pay(item.applyId) : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// 投放概览：投放中 / 待支付 / 已结束（与设计稿 Hero 一致）。
  Widget _buildHero(List<PromotionApplication> all) {
    int count(String status) =>
        all.where((item) => item.displayStatus == status).length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF254E90), Color(0xFF3E6FB5)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E254E90),
            offset: Offset(0, 8),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '我的推广',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              const Spacer(),
              Text(
                '共 ${all.length} 条',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _HeroStat(value: count('投放中'), label: '投放中'),
              const SizedBox(width: 26),
              _HeroStat(value: count('待支付'), label: '待支付'),
              const SizedBox(width: 26),
              _HeroStat(value: count('已结束'), label: '已结束'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final tab in _tabs)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = tab.value),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Column(
                    children: [
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: _tab == tab.value
                              ? FontWeight.w700
                              : FontWeight.w400,
                          color: _tab == tab.value
                              ? AppColors.text1
                              : AppColors.text3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: _tab == tab.value ? 18 : 0,
                        height: 3,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 9),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildApplyBar() {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        boxShadow: [
          BoxShadow(
            color: Color(0x14183A6E),
            offset: Offset(0, -2),
            blurRadius: 12,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton(
            onPressed: _openCreate,
            style: FilledButton.styleFrom(
              shape: const StadiumBorder(),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 18),
                SizedBox(width: 4),
                Text('申请推广'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(myPromotionsProvider);
    try {
      await ref.read(myPromotionsProvider('all').future);
    } catch (_) {
      // 失败由 provider 的 error 态展示。
    }
  }

  Future<void> _openCreate() async {
    await context.push(RoutePath.promotionCreate);
    if (mounted) ref.invalidate(myPromotionsProvider);
  }

  Future<void> _openDetail(int applyId) async {
    await context.push(RoutePath.promotionDetailUrl(applyId));
    if (mounted) ref.invalidate(myPromotionsProvider);
  }

  Future<void> _pay(int applyId) async {
    await context.push<bool>(RoutePath.promotionPayUrl(applyId));
    if (!mounted) return;
    ref.invalidate(myPromotionsProvider);
    ref.invalidate(promotionDetailProvider(applyId));
  }
}

class _StatusTab {
  const _StatusTab(this.label, this.value);

  final String label;
  final String value;
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white70),
        ),
      ],
    );
  }
}
