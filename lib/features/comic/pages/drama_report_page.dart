import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../user_center/widgets/user_center_widgets.dart';
import '../data/drama_models.dart';
import '../data/drama_providers.dart';

/// 内容举报（B 模块，接口文档 2.8.17）。
///
/// 受登录守卫保护（[RoutePath.dramaReport]）：归属取服务端身份，不接收 userId。
/// 举报对象固定为外部视频（target_type='external_drama'，与表名 sys_external_drama 对齐）。
class DramaReportPage extends ConsumerStatefulWidget {
  const DramaReportPage({super.key, required this.dramaId});

  final int dramaId;

  @override
  ConsumerState<DramaReportPage> createState() => _DramaReportPageState();
}

class _DramaReportPageState extends ConsumerState<DramaReportPage> {
  /// sys_report.reason 上限 50；界面固定选项长度远小于上限。
  static const int _descriptionMax = 500;

  String? _reason;
  final TextEditingController _description = TextEditingController();
  bool _busy = false;
  String? _reasonError;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_reason == null) {
      setState(() => _reasonError = '请选择举报原因');
      return;
    }
    setState(() {
      _reasonError = null;
      _busy = true;
    });
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final result = await ref.read(dramaRepositoryProvider).report(
            targetType: ReportTargetType.externalDrama,
            targetId: widget.dramaId,
            reason: _reason!,
            description: _description.text.trim(),
          );
      messenger.showSnackBar(
        SnackBar(content: Text('举报已提交（受理号 ${result.reportId}）')),
      );
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : '提交失败，请稍后重试'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('举报')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          UserCard(
            children: [
              UserInfoLine(label: '举报对象', value: '外部视频 #${widget.dramaId}'),
              const Padding(
                padding: EdgeInsets.only(left: 16, right: 16, bottom: 12),
                child: Text(
                  '请选择举报原因，可补充说明。平台会尽快核实处理。',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          UserCard(
            children: [
              for (final reason in ReportReason.all)
                RadioListTile<String>(
                  value: reason.label,
                  groupValue: _reason,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _reason = value;
                            _reasonError = null;
                          }),
                  title: Text(reason.label, style: const TextStyle(fontSize: 15)),
                  activeColor: AppColors.primary,
                  dense: true,
                ),
            ],
          ),
          if (_reasonError != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _reasonError!,
                style: const TextStyle(color: AppColors.error, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          UserCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _description,
                  enabled: !_busy,
                  maxLines: 4,
                  maxLength: _descriptionMax,
                  decoration: const InputDecoration(
                    hintText: '补充说明（可选）',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: UserSubmitButton(
              label: '提交举报',
              busy: _busy,
              onPressed: _submit,
            ),
          ),
        ],
      ),
    );
  }
}