import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../data/income_models.dart';
import '../data/income_providers.dart';

/// 假绑定账户信息（本地模拟，非真实三方绑定）。
class _BoundAccount {
  const _BoundAccount({
    required this.accountName,
    required this.accountNo,
    this.bankName,
  });

  final String accountName;
  final String accountNo;
  final String? bankName;

  Map<String, dynamic> toJson() => {
        'accountName': accountName,
        'accountNo': accountNo,
        if (bankName != null) 'bankName': bankName,
      };

  factory _BoundAccount.fromJson(Map<String, dynamic> json) => _BoundAccount(
        accountName: json['accountName']?.toString() ?? '',
        accountNo: json['accountNo']?.toString() ?? '',
        bankName: json['bankName']?.toString(),
      );

  String get displayMask {
    final no = accountNo;
    if (no.length <= 4) return no;
    return '${'*' * (no.length - 4)}${no.substring(no.length - 4)}';
  }
}

/// 我的收益 · 提现子页（假绑定 + 申请 + 记录）。
class MyIncomeWithdrawPage extends ConsumerStatefulWidget {
  const MyIncomeWithdrawPage({super.key});

  @override
  ConsumerState<MyIncomeWithdrawPage> createState() =>
      _MyIncomeWithdrawPageState();
}

class _MyIncomeWithdrawPageState extends ConsumerState<MyIncomeWithdrawPage> {
  static const _prefsKey = 'income_withdraw_fake_binds';

  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();

  String _withdrawType = 'alipay';
  bool _submitting = false;
  bool _bindingBusy = false;
  Map<String, _BoundAccount> _binds = {};

  @override
  void initState() {
    super.initState();
    _loadBinds();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBinds() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final next = <String, _BoundAccount>{};
      for (final e in map.entries) {
        if (e.value is Map) {
          next[e.key] =
              _BoundAccount.fromJson(Map<String, dynamic>.from(e.value as Map));
        }
      }
      if (mounted) setState(() => _binds = next);
    } catch (_) {
      // ignore corrupt local cache
    }
  }

  Future<void> _saveBinds() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      for (final e in _binds.entries) e.key: e.value.toJson(),
    };
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  _BoundAccount? get _currentBind => _binds[_withdrawType];

  String get _typeLabel {
    switch (_withdrawType) {
      case 'wechat':
        return '微信';
      case 'bank':
        return '银行卡';
      default:
        return '支付宝';
    }
  }

  Future<void> _openBindSheet() async {
    final nameCtrl = TextEditingController(text: _currentBind?.accountName ?? '');
    final accountCtrl = TextEditingController(text: _currentBind?.accountNo ?? '');
    final bankCtrl = TextEditingController(text: _currentBind?.bankName ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<_BoundAccount>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '绑定$_typeLabel（模拟）',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '当前为演示绑定流程，不会调用真实支付渠道。',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '姓名 / 账户名',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入姓名' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: accountCtrl,
                  decoration: InputDecoration(
                    labelText: _withdrawType == 'bank' ? '银行卡号' : '账号 / 手机号',
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入账号' : null,
                ),
                if (_withdrawType == 'bank') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bankCtrl,
                    decoration: const InputDecoration(
                      labelText: '开户行',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入开户行' : null,
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () {
                      if (!(formKey.currentState?.validate() ?? false)) return;
                      Navigator.pop(
                        ctx,
                        _BoundAccount(
                          accountName: nameCtrl.text.trim(),
                          accountNo: accountCtrl.text.trim(),
                          bankName: _withdrawType == 'bank'
                              ? bankCtrl.text.trim()
                              : null,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('确认绑定'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;
    setState(() => _bindingBusy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _binds[_withdrawType] = result;
    await _saveBinds();
    if (!mounted) return;
    setState(() => _bindingBusy = false);
    _toast('$_typeLabel已绑定（模拟）');
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final bind = _currentBind;
    if (bind == null) {
      _toast('请先绑定$_typeLabel账户');
      return;
    }
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _toast('请输入有效提现金额');
      return;
    }

    setState(() => _submitting = true);
    try {
      final token =
          'wd_${DateTime.now().millisecondsSinceEpoch}_${amount.toStringAsFixed(2)}';
      await ref.read(incomeRepositoryProvider).applyWithdraw(
            amount: amount,
            withdrawType: _withdrawType,
            accountName: bind.accountName,
            accountNo: bind.accountNo,
            bankName: _withdrawType == 'bank' ? bind.bankName : null,
            clientToken: token,
          );
      if (!mounted) return;
      _toast('提现申请已提交');
      _amountCtrl.clear();
      ref.invalidate(myIncomeOverviewProvider);
      ref.invalidate(withdrawListProvider(const WithdrawListParams()));
    } on ApiException catch (e) {
      if (mounted) _toast(e.message);
    } catch (e) {
      if (mounted) _toast('提交失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(myIncomeOverviewProvider);
    final records = ref.watch(withdrawListProvider(const WithdrawListParams()));
    final available = overview.maybeWhen(
      data: (d) => d.availableAmount,
      orElse: () => 0.0,
    );
    final bind = _currentBind;

    return Scaffold(
      appBar: AppBar(
        title: const Text('提现'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myIncomeOverviewProvider);
            ref.invalidate(withdrawListProvider(const WithdrawListParams()));
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _AvailableBanner(available: available),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '提现申请',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _withdrawType,
                        decoration: const InputDecoration(
                          labelText: '提现方式',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'alipay', child: Text('支付宝')),
                          DropdownMenuItem(value: 'wechat', child: Text('微信')),
                          DropdownMenuItem(value: 'bank', child: Text('银行卡')),
                        ],
                        onChanged: _submitting
                            ? null
                            : (v) {
                                if (v != null) {
                                  setState(() => _withdrawType = v);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      _BindStatusRow(
                        typeLabel: _typeLabel,
                        bound: bind,
                        busy: _bindingBusy,
                        onBind: _openBindSheet,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _amountCtrl,
                        enabled: !_submitting,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d+\.?\d{0,2}'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: '提现金额（元）',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return '请输入金额';
                          final n = double.tryParse(v.trim());
                          if (n == null || n <= 0) return '金额须大于 0';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('提交申请'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '提现记录',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(height: 12),
              records.when(
                data: (paged) {
                  if (paged.list.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          '暂无提现记录',
                          style: TextStyle(color: AppColors.text3),
                        ),
                      ),
                    );
                  }
                  return Column(
                    children:
                        paged.list.map((r) => _WithdrawTile(record: r)).toList(),
                  );
                },
                loading: () => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('加载失败：$e'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BindStatusRow extends StatelessWidget {
  const _BindStatusRow({
    required this.typeLabel,
    required this.bound,
    required this.busy,
    required this.onBind,
  });

  final String typeLabel;
  final _BoundAccount? bound;
  final bool busy;
  final VoidCallback onBind;

  @override
  Widget build(BuildContext context) {
    final isBound = bound != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.pageBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E6EB)),
      ),
      child: Row(
        children: [
          Icon(
            isBound ? Icons.check_circle : Icons.link_off,
            size: 18,
            color: isBound ? const Color(0xFF52C41A) : AppColors.text3,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isBound
                  ? '$typeLabel已绑定 · ${bound!.accountName} ${bound!.displayMask}'
                  : '$typeLabel未绑定',
              style: const TextStyle(fontSize: 13, color: AppColors.text2),
            ),
          ),
          TextButton(
            onPressed: busy ? null : onBind,
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(isBound ? '更换' : '去绑定'),
          ),
        ],
      ),
    );
  }
}

class _AvailableBanner extends StatelessWidget {
  const _AvailableBanner({required this.available});

  final double available;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '可提现余额  ¥${available.toStringAsFixed(2)}',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _WithdrawTile extends StatelessWidget {
  const _WithdrawTile({required this.record});

  final WithdrawRecord record;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.withdrawNo ?? '提现申请',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
              ),
              Text(
                record.statusLabel,
                style: TextStyle(
                  color: record.isFailed ? Colors.red : AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${record.typeLabel} · ${record.amountYuan}',
            style: const TextStyle(fontSize: 14, color: AppColors.text2),
          ),
          if (record.createdAt != null)
            Text(
              '申请时间：${record.createdAt}',
              style: const TextStyle(fontSize: 12, color: AppColors.text3),
            ),
          if (record.isFailed &&
              record.reviewOpinion != null &&
              record.reviewOpinion!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '失败原因：${record.reviewOpinion}',
                style: const TextStyle(fontSize: 13, color: Color(0xFFCF1322)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
