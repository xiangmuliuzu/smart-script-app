import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/trade_models.dart';
import '../data/trade_providers.dart';

void _showSuccess(BuildContext context, String msg) => showAppToast(context, msg);
void _showError(BuildContext context, String msg) => showAppToast(context, msg);

/// 发起询盘页（分工条目 3/9）
///
/// 从作品详情页进入，携带 workId 和作品基本信息；
/// 用户填写授权类型、用途、预算、留言后提交。
class InquiryCreatePage extends ConsumerStatefulWidget {
  const InquiryCreatePage({super.key, this.workId, this.workTitle});

  final int? workId;
  final String? workTitle;

  @override
  ConsumerState<InquiryCreatePage> createState() => _InquiryCreatePageState();
}

class _InquiryCreatePageState extends ConsumerState<InquiryCreatePage> {
  final _formKey = GlobalKey<FormState>();
  String? _licenseType = LicenseType.nonExclusive;
  final _intendedUseController = TextEditingController();
  final _budgetController = TextEditingController();
  final _messageController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _intendedUseController.dispose();
    _budgetController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('发起询盘'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (widget.workId == null) {
      return const ErrorView(
        message: '缺少作品信息',
        onRetry: null,
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 作品信息卡片
            _buildWorkInfoCard(),
            const SizedBox(height: 24),

            // 授权类型
            _buildSectionTitle('授权类型 *'),
            const SizedBox(height: 8),
            _buildLicenseTypeSelector(),
            const SizedBox(height: 16),

            // 预期用途
            _buildSectionTitle('预期用途 *'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _intendedUseController,
              decoration: const InputDecoration(
                hintText: '请描述您的使用场景，如：改编为短剧、影视化等',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return '请输入预期用途';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // 预算金额
            _buildSectionTitle('预算金额（元）'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _budgetController,
              decoration: const InputDecoration(
                hintText: '请输入您的预算金额',
                border: const OutlineInputBorder(),
                prefixText: '¥ ',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // 留言
            _buildSectionTitle('留言'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: '向作者说明您的合作意向...',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 24),

            // 提交按钮
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submitInquiry,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('提交询盘', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.fill,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.article, color: AppColors.text3, size: 32),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.workTitle ?? '作品',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '作品ID: ${widget.workId}',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.text1,
      ),
    );
  }

  Widget _buildLicenseTypeSelector() {
    final types = [
      (LicenseType.nonExclusive, '非独家授权'),
      (LicenseType.exclusive, '独家授权'),
      (LicenseType.transfer, '转让'),
    ];

    return Column(
      children: types.map((item) {
        final value = item.$1;
        final label = item.$2;
        return RadioListTile<String>(
          title: Text(label),
          value: value,
          groupValue: _licenseType,
          onChanged: (v) => setState(() => _licenseType = v),
          contentPadding: EdgeInsets.zero,
          activeColor: AppColors.primary,
        );
      }).toList(),
    );
  }

  Future<void> _submitInquiry() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);

    try {
      // 预算转为分
      int? budgetFen;
      if (_budgetController.text.isNotEmpty) {
        final yuan = double.tryParse(_budgetController.text);
        if (yuan != null) {
          budgetFen = (yuan * 100).round();
        }
      }

      final inquiry = Inquiry(
        workId: widget.workId,
        licenseType: _licenseType,
        intendedUse: _intendedUseController.text.trim(),
        budget: budgetFen,
        message: _messageController.text.trim().isEmpty ? null : _messageController.text.trim(),
      );

      await ref.read(tradeRepositoryProvider).createInquiry(inquiry);

      if (mounted) {
        _showSuccess(context, '询盘已提交');
        // 返回上一页并刷新
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showError(context, '提交失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }
}
