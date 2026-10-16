import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../data/trade_models.dart';
import '../data/trade_repository.dart';
import '../data/trade_providers.dart';

/// 报价页（分工条目 9）：卖方提交报价、设置有效期。
///
/// 入参：inquiryId（询盘ID）、workTitle（作品名称，展示用）。
/// 表单字段：报价金额（元）、授权类型、有效天数、备注。
class QuoteCreatePage extends ConsumerStatefulWidget {
  const QuoteCreatePage({
    super.key,
    required this.inquiryId,
    this.workTitle,
  });

  final int inquiryId;
  final String? workTitle;

  @override
  ConsumerState<QuoteCreatePage> createState() => _QuoteCreatePageState();
}

class _QuoteCreatePageState extends ConsumerState<QuoteCreatePage> {
  final _formKey = GlobalKey<FormState>();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  String _licenseType = 'non_exclusive';
  int _validDays = 7;
  bool _submitting = false;

  static const _licenseTypes = [
    ('exclusive', '独家授权'),
    ('non_exclusive', '非独家授权'),
    ('adaptation', '改编授权'),
  ];

  @override
  void dispose() {
    _priceController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('提交报价'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 作品信息
              if (widget.workTitle != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.menu_book, size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.workTitle!,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // 报价金额
              const Text('报价金额', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  prefixText: '¥ ',
                  hintText: '请输入报价金额',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return '请输入报价金额';
                  final n = double.tryParse(v);
                  if (n == null || n <= 0) return '请输入有效金额';
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // 授权类型
              const Text('授权类型', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _licenseType,
                    isExpanded: true,
                    items: _licenseTypes.map((e) => DropdownMenuItem(
                      value: e.$1,
                      child: Text(e.$2),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _licenseType = v);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 有效期
              const Text('有效期（天）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Row(
                children: [7, 14, 30, 60].map((d) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('$d天'),
                    selected: _validDays == d,
                    onSelected: (_) => setState(() => _validDays = d),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),

              // 备注
              const Text('备注说明', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextFormField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: '可选：补充说明报价内容',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 32),

              // 提交按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('提交报价', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      final priceYuan = double.parse(_priceController.text);
      final priceFen = (priceYuan * 100).round();

      final quote = Quote(
        inquiryId: widget.inquiryId,
        amount: priceFen,
        licenseType: _licenseType,
        validDays: _validDays,
        message: _descController.text.isEmpty ? null : _descController.text,
        role: 'seller',
      );

      await ref.read(tradeRepositoryProvider).appCreateQuote(quote);

      if (mounted) {
        showAppToast(context, '报价提交成功');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '提交失败：$e');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
