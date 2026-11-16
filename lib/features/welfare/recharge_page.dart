import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/auth_providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import 'data/recharge_models.dart';
import 'data/welfare_providers.dart';

/// 积分充值页（App 端 E 模块）。
///
/// 页面结构（本轮只做「充值与积分换算 + 付费方式选择」）：
///   1. 当前积分余额
///   2. 固定档位（6/30/68/128/328/648 元）+ 自定义金额（必须 1 元整数倍）
///   3. 换算展示：1 元 = N 积分（N 由后端配置返回，不在前端写死）
///   4. 支付方式：微信支付 / 支付宝（真实对接由支付组接入）
///   5. 模拟支付：确认后积分立即真实入账（走 sys_points_account / sys_points_record）
///   6. 最近充值记录
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});

  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  final TextEditingController _customController = TextEditingController();

  /// 选中的固定档位（元）；自定义输入时置空。
  int? _selectedYuan;
  String _channel = 'WECHAT';
  bool _submitting = false;

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  /// 当前待支付金额（元）。
  int get _yuan {
    if (_selectedYuan != null) return _selectedYuan!;
    return int.tryParse(_customController.text.trim()) ?? 0;
  }

  void _pickPlan(int yuan) {
    setState(() {
      _selectedYuan = yuan;
      _customController.clear();
    });
  }

  void _onCustomChanged(String _) {
    setState(() {
      _selectedYuan = null;
    });
  }

  /// 支付流程：创建订单 → 模拟收银台确认 → 入账 → 刷新余额。
  Future<void> _pay(RechargeConfig config) async {
    final yuan = _yuan;
    if (yuan < config.minYuan || yuan > config.maxYuan) {
      showAppToast(context, '充值金额需在 ${config.minYuan}–${config.maxYuan} 元之间');
      return;
    }
    final userId = ref.read(authControllerProvider).user?.userId ?? 0;
    if (userId == 0) {
      showAppToast(context, '请先登录');
      return;
    }
    setState(() => _submitting = true);
    try {
      final order = await ref
          .read(welfareRepositoryProvider)
          .createRechargeOrder(userId: userId, yuan: yuan, channel: _channel);
      if (!mounted) return;
      final confirmed = await _confirmMockPay(order);
      if (confirmed != true) return;
      final result = await ref
          .read(welfareRepositoryProvider)
          .payRecharge(userId: userId, orderNo: order.orderNo);
      ref.invalidate(rechargeConfigProvider);
      ref.invalidate(rechargeRecordsProvider);
      ref.invalidate(welfareAssetProvider);
      ref.invalidate(pointsBalanceProvider);
      if (!mounted) return;
      showAppToast(context, '充值成功 +${result.points} 积分，当前余额 ${result.balance}');
      setState(() {
        _selectedYuan = null;
        _customController.clear();
      });
    } catch (error) {
      if (mounted) showAppToast(context, _messageOf(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _messageOf(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  /// 模拟收银台：真实微信/支付宝由支付组替换为渠道 SDK/收银台。
  Future<bool?> _confirmMockPay(RechargePayResult order) {
    final yuan = order.amountFen ~/ 100;
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认支付'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('支付金额：¥$yuan', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text('到账积分：${order.points}'),
            Text('支付方式：${_channelName(_channel)}'),
            const SizedBox(height: 12),
            const Text(
              '当前为模拟支付：确认后积分立即入账，微信/支付宝真实通道稍后接入。',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认支付'),
          ),
        ],
      ),
    );
  }

  String _channelName(String code) => code == 'ALIPAY' ? '支付宝' : '微信支付';

  @override
  Widget build(BuildContext context) {
    final configAsync = ref.watch(rechargeConfigProvider);
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('积分充值'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Retry(
          onRetry: () => ref.invalidate(rechargeConfigProvider),
        ),
        data: (config) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(rechargeConfigProvider);
            ref.invalidate(rechargeRecordsProvider);
            await ref.read(rechargeConfigProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              _BalanceCard(config: config),
              const SizedBox(height: 16),
              const _SectionTitle('选择充值金额'),
              const SizedBox(height: 8),
              _PlanGrid(
                config: config,
                selectedYuan: _selectedYuan,
                onPick: _pickPlan,
              ),
              const SizedBox(height: 12),
              _CustomInput(
                config: config,
                controller: _customController,
                enabled: _selectedYuan == null,
                currentYuan: _yuan,
                onChanged: _onCustomChanged,
              ),
              const SizedBox(height: 16),
              const _SectionTitle('支付方式'),
              const SizedBox(height: 8),
              _ChannelList(
                config: config,
                selected: _channel,
                onPick: (code) => setState(() => _channel = code),
              ),
              const SizedBox(height: 16),
              const _SectionTitle('最近充值'),
              const SizedBox(height: 8),
              const _RecordList(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: configAsync.maybeWhen(
        data: (config) => _PayBar(
          config: config,
          yuan: _yuan,
          submitting: _submitting,
          onPay: () => _pay(config),
        ),
        orElse: () => const SizedBox.shrink(),
      ),
    );
  }
}

/// 顶部余额卡：当前积分 + 换算比例说明。
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.config});

  final RechargeConfig config;

  @override
  Widget build(BuildContext context) {
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
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('当前积分', style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
              const SizedBox(height: 4),
              Text(
                '${config.balance}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x22FFFFFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '1 元 = ${config.pointsPerYuan} 积分',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// 固定档位网格（3 列）。
class _PlanGrid extends StatelessWidget {
  const _PlanGrid({
    required this.config,
    required this.selectedYuan,
    required this.onPick,
  });

  final RechargeConfig config;
  final int? selectedYuan;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.45,
      children: [
        for (final plan in config.plans)
          InkWell(
            borderRadius: BorderRadius.circular(AppRadius.rSmall),
            onTap: () => onPick(plan.yuan),
            child: Container(
              decoration: BoxDecoration(
                color: selectedYuan == plan.yuan ? AppColors.primaryTint : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
                border: Border.all(
                  color: selectedYuan == plan.yuan ? AppColors.primary : AppColors.divider,
                  width: selectedYuan == plan.yuan ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '¥${plan.yuan}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${plan.points} 积分',
                    style: const TextStyle(fontSize: 12, color: AppColors.text3),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 自定义金额输入（必须 1 元的整数倍）。
class _CustomInput extends StatelessWidget {
  const _CustomInput({
    required this.config,
    required this.controller,
    required this.enabled,
    required this.currentYuan,
    required this.onChanged,
  });

  final RechargeConfig config;
  final TextEditingController controller;
  final bool enabled;
  final int currentYuan;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.rSmall),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('自定义金额', style: TextStyle(fontSize: 13, color: AppColors.text2)),
              const Spacer(),
              Text(
                '${config.minYuan}–${config.maxYuan} 元，1 元整数倍',
                style: const TextStyle(fontSize: 11, color: AppColors.text3),
              ),
            ],
          ),
          TextField(
            controller: controller,
            enabled: enabled,
            onChanged: onChanged,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              prefixText: '¥ ',
              suffixText: '元',
              hintText: enabled ? '想充多少填多少' : '已选固定档位，点输入框可自定义',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.placeholder),
              border: InputBorder.none,
              isDense: true,
            ),
          ),
          if (currentYuan > 0) ...[
            const SizedBox(height: 4),
            Text(
              '预计到账 ${config.pointsOf(currentYuan)} 积分',
              style: const TextStyle(fontSize: 12, color: AppColors.text1),
            ),
          ],
        ],
      ),
    );
  }
}

/// 支付方式列表（微信 / 支付宝）。
class _ChannelList extends StatelessWidget {
  const _ChannelList({
    required this.config,
    required this.selected,
    required this.onPick,
  });

  final RechargeConfig config;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final channels = config.channels.isEmpty
        ? const [
            RechargeChannel(code: 'WECHAT', name: '微信支付'),
            RechargeChannel(code: 'ALIPAY', name: '支付宝'),
          ]
        : config.channels;
    return Column(
      children: [
        for (final channel in channels)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
              onTap: channel.enabled ? () => onPick(channel.code) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadius.rSmall),
                  border: Border.all(
                    color: selected == channel.code ? AppColors.primary : AppColors.divider,
                    width: selected == channel.code ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      channel.code == 'ALIPAY'
                          ? Icons.account_balance_wallet_outlined
                          : Icons.chat_bubble_outline,
                      size: 20,
                      color: channel.code == 'ALIPAY' ? AppColors.primary : AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    Text(channel.name, style: const TextStyle(fontSize: 15)),
                    const Spacer(),
                    Icon(
                      selected == channel.code
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: selected == channel.code ? AppColors.primary : AppColors.text3,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 最近充值记录（最多 5 条）。
class _RecordList extends ConsumerWidget {
  const _RecordList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(rechargeRecordsProvider);
    return recordsAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(12),
        child: Center(child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))),
      ),
      error: (_, __) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('充值记录加载失败', style: TextStyle(fontSize: 12, color: AppColors.text3)),
      ),
      data: (records) {
        if (records.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
            ),
            child: const Center(
              child: Text('还没有充值记录', style: TextStyle(fontSize: 12, color: AppColors.text3)),
            ),
          );
        }
        final shown = records.take(5).toList();
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.rSmall),
          ),
          child: Column(
            children: [
              for (final record in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      Text(
                        '¥${(record.amountFen / 100).toStringAsFixed(record.amountFen % 100 == 0 ? 0 : 2)}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '+${record.points} 积分',
                        style: const TextStyle(fontSize: 12, color: AppColors.text1),
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${record.channelLabel} · ${record.statusLabel}',
                            style: const TextStyle(fontSize: 11, color: AppColors.text3),
                          ),
                          if (record.createTime != null)
                            Text(
                              record.createTime!,
                              style: const TextStyle(fontSize: 11, color: AppColors.text3),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 底部支付条。
class _PayBar extends StatelessWidget {
  const _PayBar({
    required this.config,
    required this.yuan,
    required this.submitting,
    required this.onPay,
  });

  final RechargeConfig config;
  final int yuan;
  final bool submitting;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final valid = yuan >= config.minYuan && yuan <= config.maxYuan;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(
                  valid ? '应付 ¥$yuan' : '请选择充值金额',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: valid ? AppColors.text1 : AppColors.text3,
                  ),
                ),
                const Spacer(),
                if (valid)
                  Text(
                    '到账 ${config.pointsOf(yuan)} 积分',
                    style: const TextStyle(fontSize: 13, color: AppColors.text1),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton(
                onPressed: (valid && !submitting) ? onPay : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(23),
                  ),
                ),
                child: submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Text(valid ? '立即支付 ¥$yuan' : '立即支付'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.text1,
      ),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('充值信息加载失败', style: TextStyle(color: AppColors.text2)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
