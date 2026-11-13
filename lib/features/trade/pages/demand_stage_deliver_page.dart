import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/demand_task_type.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';

/// 提交本轮交付物（全屏页）。
///
/// 剧本类：选定本人未上架作品 + 交付说明，提交后先走 AI 审核再进平台验收。
/// 分镜类（storyboard）：作品可不选，交付说明与文件链接至少填一项，
/// 后端跳过 AI 剧本审核直接进入人工验收（分镜不是剧本正文，AI 剧本评分无意义）。
class DemandStageDeliverPage extends ConsumerStatefulWidget {
  const DemandStageDeliverPage({
    super.key,
    required this.demandId,
    required this.stageId,
    required this.stageOrder,
  });

  final int demandId;
  final int stageId;
  final int stageOrder;

  @override
  ConsumerState<DemandStageDeliverPage> createState() => _DemandStageDeliverPageState();
}

class _DemandStageDeliverPageState extends ConsumerState<DemandStageDeliverPage> {
  List<DeliverableWork> _works = const [];
  bool _loading = true;
  String? _loadError;
  int? _selectedWorkId;
  bool _submitting = false;
  String? _submitError;
  final TextEditingController _descCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final works = await ref.read(demandRepositoryProvider).deliverableWorks();
      if (!mounted) return;
      setState(() {
        _works = works;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e is ApiException && e.message.isNotEmpty ? e.message : '加载作品失败';
        _loading = false;
      });
    }
  }

  Future<void> _submit({required bool isStoryboard}) async {
    final desc = _descCtrl.text.trim();
    final url = _urlCtrl.text.trim();
    if (!isStoryboard && _selectedWorkId == null) {
      setState(() => _submitError = '请先选择一个交付作品');
      return;
    }
    // 不关联作品时，本轮交付至少要能落到文件或说明上，否则平台无从验收
    if (isStoryboard && _selectedWorkId == null && desc.isEmpty && url.isEmpty) {
      setState(() => _submitError = '请交付分镜作品，或填写交付说明 / 粘贴分镜文件链接');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref.read(demandRepositoryProvider).deliverStage(
            widget.demandId,
            widget.stageId,
            workId: _selectedWorkId,
            deliverableDesc: desc.isEmpty ? null : desc,
            deliverableUrl: url.isEmpty ? null : url,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = e is ApiException && e.message.isNotEmpty ? e.message : '提交失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 任务类型由详情页已缓存的详情取，交付页路由不必多带参数
    final taskType = DemandTaskType.normalize(
        ref.watch(demandDetailProvider(widget.demandId)).valueOrNull?.taskType);
    final isStoryboard = DemandTaskType.isStoryboard(taskType);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('提交交付物')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildStageBanner(taskType),
                const SizedBox(height: 20),
                Text(isStoryboard ? '交付作品（可选）' : '选择交付作品',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  isStoryboard
                      ? '分镜成果可不关联作品，只交文件链接与说明也可；关联的作品须是本人未上架售卖的'
                      : '仅可交付本人、未上架售卖的作品',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 10),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (_loadError != null)
                  _buildErrorBar(_loadError!, onRetry: _load)
                else if (_works.isEmpty)
                  _buildEmptyHint(isStoryboard)
                else
                  ..._works.map(_buildWorkCard),
                const SizedBox(height: 20),
                const Text('交付说明',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: _descCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: isStoryboard
                        ? '本轮分镜覆盖的集数、场次拆分口径与待确认事项…'
                        : '补充说明本轮交付内容（可选）',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    fillColor: Colors.grey.shade50,
                    filled: true,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Text('交付物链接（${isStoryboard ? '与说明至少填一项' : '可选'}）',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                TextField(
                  controller: _urlCtrl,
                  decoration: InputDecoration(
                    hintText: '网盘/文档链接',
                    hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    fillColor: Colors.grey.shade50,
                    filled: true,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 12),
                Text(
                  isStoryboard
                      ? '分镜类任务不做 AI 剧本审核，提交后直接进入平台人工验收，本轮计时暂停至验收出结果。'
                      : '提交后先由 AI 审核（60 分以上自动进入平台验收，低于 60 分直接打回重交），'
                          'AI 审核与验收期间本轮计时均暂停。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.5),
                ),
              ],
            ),
          ),
          _buildBottomBar(isStoryboard),
        ],
      ),
    );
  }

  /// 顶部轮次说明条。
  Widget _buildStageBanner(String taskType) {
    final storyboard = DemandTaskType.isStoryboard(taskType);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '第${widget.stageOrder}轮交付 · ${DemandTaskType.labelOf(taskType)}'
              ' · ${storyboard ? '提交后进入平台人工验收' : '提交后先走 AI 审核，审核期间本轮计时暂停'}',
              style: const TextStyle(fontSize: 12, color: AppColors.text1, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// 作品选择卡片：选中态用主色边框+浅底，不加多余图标。
  Widget _buildWorkCard(DeliverableWork w) {
    final selected = _selectedWorkId == w.workId;
    return GestureDetector(
      onTap: () => setState(() => _selectedWorkId = w.workId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.05) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.grey.shade300,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(w.title ?? '作品${w.workId}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('${w.statusLabel} · ID ${w.workId}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Text(
              selected ? '已选择' : '选择',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: selected ? AppColors.text1 : Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  /// 无可交付作品空态。
  Widget _buildEmptyHint(bool isStoryboard) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(isStoryboard ? '暂无可关联的作品' : '暂无可交付作品',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54)),
          const SizedBox(height: 4),
          Text(
            isStoryboard
                ? '没有作品也可以，直接填写交付说明或粘贴分镜文件链接提交'
                : '只能交付本人未上架售卖的作品，请先在“我的作品”中完成创作',
            style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBar(String text, {VoidCallback? onRetry}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: Colors.red.shade600, height: 1.4)),
          ),
          if (onRetry != null)
            TextButton(onPressed: onRetry, child: const Text('重试', style: TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  /// 底部提交栏：错误提示常驻可见，避免一闪而过的 toast。
  Widget _buildBottomBar(bool isStoryboard) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_submitError != null) ...[
            Text(_submitError!,
                style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              // 剧本类必须有作品才能提交；分镜类作品可空，故只挡加载中
              onPressed: _submitting || (!isStoryboard && _works.isEmpty)
                  ? null
                  : () => _submit(isStoryboard: isStoryboard),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                _submitting ? '提交中...' : '提交交付物',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
