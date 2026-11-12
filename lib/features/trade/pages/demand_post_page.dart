import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/demand_genre.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../data/demand_providers.dart';
import '../data/trade_models.dart';

/// 发布任务页面（[demandId] 非空时为编辑模式，仅未托管未接单可编辑）。
class DemandPostPage extends ConsumerStatefulWidget {
  const DemandPostPage({super.key, this.demandId});

  /// 编辑模式下的任务 ID；为 null 时为新建发布。
  final int? demandId;

  @override
  ConsumerState<DemandPostPage> createState() => _DemandPostPageState();
}

class _DemandPostPageState extends ConsumerState<DemandPostPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _budgetCtrl = TextEditingController();
  final _requirementCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  final _episodesCtrl = TextEditingController();
  // 最后一轮验收（固定存在）：集数=总集数、金额=剩余均自动计算不可改，仅小时时限可填写
  final _lastHoursCtrl = TextEditingController();
  int? _genreId;
  DateTime? _deadline;
  bool _submitting = false;
  bool _loading = false;

  bool get _isEdit => widget.demandId != null;

  int? get _totalEpisodes => int.tryParse(_episodesCtrl.text.trim());

  /// 总集数填好后最后一轮验收卡片直接出现，无需先添加中间轮次。
  bool get _hasValidTotalEpisodes => (_totalEpisodes ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    // 预算/总集数变化动态刷新最后一轮的剩余金额展示与显隐
    _budgetCtrl.addListener(_onAmountsChanged);
    _episodesCtrl.addListener(_onAmountsChanged);
    if (_isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadForEdit());
    }
  }

  void _onAmountsChanged() {
    if (mounted) setState(() {});
  }

  /// 编辑模式：拉取任务详情与验收轮次回填表单。
  Future<void> _loadForEdit() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(demandRepositoryProvider);
      final id = widget.demandId!;
      final task = await repo.demandDetail(id);
      final stages = await repo.demandStages(id);
      if (!mounted) return;
      setState(() {
        _titleCtrl.text = task.title ?? '';
        _budgetCtrl.text = task.budget == null
            ? ''
            : (task.budget! / 100).toStringAsFixed(task.budget! % 100 == 0 ? 0 : 2);
        _requirementCtrl.text = task.requirement ?? '';
        _tagsCtrl.text = task.tags ?? '';
        _genreId = task.genreId;
        _deadline = task.deadline;
        _episodesCtrl.text = (task.totalEpisodes != null && task.totalEpisodes! > 0)
            ? '${task.totalEpisodes}'
            : '';
        for (final r in _stageRows) {
          r.dispose();
        }
        _stageRows.clear();
        // 末位轮视为固定的最后一轮验收：不进可编辑列表，仅回填其时限
        final editable = stages.isEmpty ? <DemandStage>[] : stages.sublist(0, stages.length - 1);
        if (stages.isNotEmpty) {
          final lastStage = stages.last;
          _lastHoursCtrl.text =
              '${((lastStage.durationDays ?? 0) * 24) + (lastStage.durationHours ?? 0)}';
        } else if ((task.durationHours ?? 0) > 0) {
          // 历史整单任务无轮次数据时，用整单时限回填最后一轮，避免编辑时必须重填
          _lastHoursCtrl.text = '${task.durationHours}';
        }
        for (final s in editable) {
          final row = _StageRow(order: _stageRows.length + 1, onChanged: _onAmountsChanged);
          row.episodeCtrl.text = '${s.episodeTo ?? 0}';
          row.amountCtrl.text = s.amount == null
              ? ''
              : (s.amount! / 100).toStringAsFixed(s.amount! % 100 == 0 ? 0 : 2);
          row.hoursCtrl.text =
              '${((s.durationDays ?? 0) * 24) + (s.durationHours ?? 0)}';
          _stageRows.add(row);
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showAppToast(context, '加载任务信息失败：$e');
    }
  }

  /// 动态验收轮次行：每行包含 [episodeCtrl, amountCtrl]
  final List<_StageRow> _stageRows = [];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _budgetCtrl.dispose();
    _requirementCtrl.dispose();
    _tagsCtrl.dispose();
    _episodesCtrl.dispose();
    _lastHoursCtrl.dispose();
    for (final r in _stageRows) { r.dispose(); }
    super.dispose();
  }

  void _addStageRow() {
    setState(() => _stageRows.add(_StageRow(order: _stageRows.length + 1, onChanged: _onAmountsChanged)));
  }

  void _removeStageRow(int index) {
    final r = _stageRows.removeAt(index);
    r.dispose();
    // 重新编号
    for (var i = 0; i < _stageRows.length; i++) {
      _stageRows[i].order = i + 1;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑任务' : '发布任务'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field('任务标题 *', _titleCtrl, validator: (v) => (v == null || v.trim().isEmpty) ? '请输入标题' : null),
            const SizedBox(height: 12),
            _genreDropdown(),
            const SizedBox(height: 12),
            _field('预算（元）*', _budgetCtrl, keyboardType: TextInputType.number,
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入预算' : null),
            const SizedBox(height: 12),
            _deadlineField(),
            const SizedBox(height: 12),
            _field('标签（逗号分隔）', _tagsCtrl),
            const SizedBox(height: 12),
            _multilineField('需求描述 *', _requirementCtrl,
                validator: (v) => (v == null || v.trim().isEmpty) ? '请输入需求描述' : null),
            const SizedBox(height: 20),
            // ==================== 验收设置 ====================
            _buildStageSection(),
            const SizedBox(height: 16),
            _buildEscrowHint(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(_submitting ? '提交中...' : (_isEdit ? '保存修改' : '发布任务')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 验收设置区块 ====================

  Widget _buildStageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.fact_check_outlined, color: AppColors.primary),
            const SizedBox(width: 4),
            Text('验收设置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.text1)),
            const SizedBox(width: 8),
            Expanded(
              child: Text('（总集数必填，最后一轮验收自动生成）',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field('总集数 *', _episodesCtrl,
            keyboardType: TextInputType.number,
            validator: (v) => (int.tryParse(v?.trim() ?? '') ?? 0) <= 0 ? '请输入总集数' : null),
        const SizedBox(height: 12),
        // 中间轮次（可选）
        ..._stageRows.asMap().entries.map((entry) => _buildStageRow(entry.key, entry.value)),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addStageRow,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加验收轮次'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.text1),
        ),
        const SizedBox(height: 4),
        Text('可不添加中间轮次，最后一轮验收会自动生成并验收到总集数。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        // 固定最后一轮验收：填好总集数后直接出现，集数/金额锁定，仅小时时限可填
        if (_hasValidTotalEpisodes) _buildLastStageCard(),
        // 分配对比
        if (_stageRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildAmountSummary(),
        ],
      ],
    );
  }

  Widget _buildStageRow(int index, _StageRow row) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('第${row.order}轮',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  onPressed: () => _removeStageRow(index),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: row.episodeCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '截止集数',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: row.amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '金额(元)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: row.hoursCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '本轮时限（小时）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEscrowHint() {
    final budget = double.tryParse(_budgetCtrl.text.trim()) ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              budget > 0
                  ? '发布后需在详情页扫码完成托管付款 ¥${budget.toStringAsFixed(2)}（全额进入平台第三方托管账户），托管完成前任务不在广场曝光、不可被接单。（支付宝沙箱收款，扫码后自动确认到账。）'
                  : '发布后需先在详情页扫码完成托管付款（全额进入平台第三方托管账户），托管完成前任务不可被接单。（支付宝沙箱收款，扫码后自动确认到账。）',
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountSummary() {
    final budgetFen = ((double.tryParse(_budgetCtrl.text.trim()) ?? 0) * 100).round();
    int allocatedFen = 0;
    for (final r in _stageRows) {
      allocatedFen += ((double.tryParse(r.amountCtrl.text.trim()) ?? 0) * 100).round();
    }
    final ok = allocatedFen <= budgetFen;
    final remainFen = budgetFen - allocatedFen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ok ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle : Icons.warning_amber, size: 16,
              color: ok ? Colors.green : Colors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              ok
                  ? '已填写 ¥${(allocatedFen / 100).toStringAsFixed(2)} / 预算 ¥${(budgetFen / 100).toStringAsFixed(2)}（不超过预算即可，剩余将自动作为最后一轮金额）'
                  : '已填写 ¥${(allocatedFen / 100).toStringAsFixed(2)}，超出预算 ¥${(-remainFen / 100).toStringAsFixed(2)}，请调减各轮金额',
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: ok ? Colors.green.shade800 : Colors.orange.shade800),
            ),
          ),
        ],
      ),
    );
  }

  /// 最后一轮验收（固定存在）：集数=总集数、金额=预算-已填写之和，均只读动态展示；仅时限可填写。
  Widget _buildLastStageCard() {
    final budgetFen = ((double.tryParse(_budgetCtrl.text.trim()) ?? 0) * 100).round();
    int allocatedFen = 0;
    for (final r in _stageRows) {
      allocatedFen += ((double.tryParse(r.amountCtrl.text.trim()) ?? 0) * 100).round();
    }
    final remainFen = budgetFen - allocatedFen;
    final totalEp = int.tryParse(_episodesCtrl.text.trim());
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lock_outline, size: 15, color: AppColors.primary),
              SizedBox(width: 4),
              Text('最后一轮验收（自动生成，集数与金额不可修改）',
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.text1)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '截止集数：第 ${totalEp != null && totalEp > 0 ? '$totalEp' : '？'} 集（=总集数） · '
            '金额：¥${((remainFen > 0 ? remainFen : 0) / 100).toStringAsFixed(2)}'
            '（=预算减已填写轮次，为 0 时本轮不另行放款）',
            style: const TextStyle(fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _lastHoursCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '最后一轮验收时限（小时）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 原有 widget ====================

  Widget _field(String label, TextEditingController ctrl, {TextInputType? keyboardType, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
    );
  }

  Widget _multilineField(String label, TextEditingController ctrl, {String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      validator: validator,
      maxLines: 5,
      decoration: InputDecoration(labelText: label, alignLabelWithHint: true, border: const OutlineInputBorder()),
    );
  }

  Widget _genreDropdown() {
    final genres = DemandGenre.labels;
    return DropdownButtonFormField<int>(
      value: _genreId,
      hint: const Text('选择分类 *'),
      decoration: const InputDecoration(labelText: '分类', border: OutlineInputBorder()),
      items: genres.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
      onChanged: (v) => setState(() => _genreId = v),
      validator: (v) => v == null ? '请选择分类' : null,
    );
  }

  Widget _deadlineField() {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: _deadline ?? now.add(const Duration(days: 30)),
          firstDate: now,
          lastDate: now.add(const Duration(days: 365)),
        );
        if (picked != null) setState(() => _deadline = picked);
      },
      child: InputDecorator(
        decoration: const InputDecoration(labelText: '截止日期 *', border: OutlineInputBorder()),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_deadline != null
                ? '${_deadline!.year}-${_deadline!.month.toString().padLeft(2, '0')}-${_deadline!.day.toString().padLeft(2, '0')}'
                : '请选择'),
            const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  // ==================== 提交 ====================

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_deadline == null) {
      showAppToast(context, '请选择截止日期');
      return;
    }
    final budgetYuan = double.tryParse(_budgetCtrl.text.trim());
    if (budgetYuan == null || budgetYuan <= 0) {
      showAppToast(context, '请输入有效预算金额');
      return;
    }

    // 总集数必填；无论是否添加中间轮次，都固定生成最后一轮验收
    final totalEpisodes = int.tryParse(_episodesCtrl.text.trim());
    if (totalEpisodes == null || totalEpisodes <= 0) {
      showAppToast(context, '请填写总集数');
      return;
    }
    int sumAmountFen = 0;
    int prevEp = 0;
    final stagesPayload = <Map<String, dynamic>>[];
    for (var i = 0; i < _stageRows.length; i++) {
      final row = _stageRows[i];
      final ep = int.tryParse(row.episodeCtrl.text.trim()) ?? 0;
      final amtFen = ((double.tryParse(row.amountCtrl.text.trim()) ?? 0) * 100).round();
      final hours = int.tryParse(row.hoursCtrl.text.trim()) ?? 0;
      if (ep <= prevEp) {
        showAppToast(context, '第${i + 1}轮集数必须大于上一轮');
        return;
      }
      if (ep >= totalEpisodes) {
        showAppToast(context, '第${i + 1}轮集数必须小于总集数（最后一轮验收固定验收到总集数）');
        return;
      }
      if (amtFen <= 0) {
        showAppToast(context, '第${i + 1}轮金额必须大于0');
        return;
      }
      if (hours <= 0) {
        showAppToast(context, '第${i + 1}轮验收时限（小时）必须大于0');
        return;
      }
      prevEp = ep;
      sumAmountFen += amtFen;
      stagesPayload.add({
        'stageOrder': i + 1,
        'episodeTo': ep,
        'amount': amtFen / 100.0,
        'durationDays': 0,
        'durationHours': hours,
      });
    }
    // 中间轮金额之和允许小于预算（剩余归最后一轮），但不允许超过
    final budgetFen = (budgetYuan * 100).round();
    if (sumAmountFen > budgetFen) {
      showAppToast(context, '各轮金额之和不能超过预算');
      return;
    }
    // 固定追加最后一轮验收：集数=总集数、金额=剩余，时限由发布者填写
    final lastHours = int.tryParse(_lastHoursCtrl.text.trim()) ?? 0;
    if (lastHours <= 0) {
      showAppToast(context, '请填写最后一轮验收时限（小时）');
      return;
    }
    stagesPayload.add({
      'stageOrder': _stageRows.length + 1,
      'episodeTo': totalEpisodes,
      'amount': (budgetFen - sumAmountFen) / 100.0,
      'durationDays': 0,
      'durationHours': lastHours,
    });

    setState(() => _submitting = true);
    try {
      final repo = ref.read(demandRepositoryProvider);
      final deadlineStr =
          '${_deadline!.year}-${_deadline!.month.toString().padLeft(2, '0')}-${_deadline!.day.toString().padLeft(2, '0')}';
      final tags = _tagsCtrl.text.trim();
      if (_isEdit) {
        await repo.updateDemand(
          demandId: widget.demandId!,
          title: _titleCtrl.text.trim(),
          genreId: _genreId,
          budget: budgetFen,
          deadline: deadlineStr,
          requirement: _requirementCtrl.text.trim(),
          tags: tags,
          totalEpisodes: totalEpisodes,
          stages: stagesPayload,
        );
        if (mounted) {
          ref.invalidate(demandDetailProvider(widget.demandId!));
          showAppToast(context, '已保存修改');
          context.pop();
        }
      } else {
        final created = await repo.createDemand(
          title: _titleCtrl.text.trim(),
          genreId: _genreId,
          budget: budgetFen,
          deadline: deadlineStr,
          requirement: _requirementCtrl.text.trim(),
          tags: tags.isEmpty ? null : tags,
          totalEpisodes: totalEpisodes,
          stages: stagesPayload,
        );
        if (mounted) {
          showAppToast(context, '发布成功，请在详情页扫码完成托管付款');
          // 跳详情页（详情页发布者可见“支付宝扫码付托管款”）
          final id = created.demandId;
          if (id != null) {
            context.pushReplacement(RoutePath.demandDetailUrl(id));
          } else {
            context.pop();
          }
        }
      }
    } catch (e) {
      if (mounted) showAppToast(context, '${_isEdit ? '保存' : '发布'}失败：$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

/// 辅助类：验收轮次行控制器
class _StageRow {
  int order; // display-only 序号
  final VoidCallback? onChanged;
  final TextEditingController episodeCtrl = TextEditingController();
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController hoursCtrl = TextEditingController();

  _StageRow({required this.order, this.onChanged}) {
    if (onChanged != null) {
      amountCtrl.addListener(onChanged!);
    }
  }

  void dispose() {
    episodeCtrl.dispose();
    amountCtrl.dispose();
    hoursCtrl.dispose();
  }
}
