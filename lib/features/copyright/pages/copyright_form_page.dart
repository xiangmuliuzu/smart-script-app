/// 版权申请统一表单页（App 端）- 支持新建/编辑/重新提交。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/native_file_picker.dart';
import '../data/copyright_models.dart';
import '../data/copyright_providers.dart';
import '../providers/copyright_provider.dart';
import '../widgets/material_upload_section.dart';

/// 表单模式枚举
enum CopyrightFormMode {
  create,   // 新建申请
  resubmit, // 重新提交
}

/// 版权申请统一表单页
class CopyrightFormPage extends ConsumerStatefulWidget {
  final CopyrightFormMode mode;
  final CopyrightApplication? application; // 编辑/重新提交时需要
  final int? originalApplyId; // 重新提交时的原申请ID

  const CopyrightFormPage({
    super.key,
    CopyrightFormMode? mode,
    this.application,
    int? originalApplyId,
    int? applyId,
  })  : originalApplyId = originalApplyId ?? applyId,
        mode = mode ??
            ((applyId != null && applyId > 0)
                ? CopyrightFormMode.resubmit
                : CopyrightFormMode.create);

  /// 路由入口：带 `applyId` 时为重新提交，否则为新建。
  factory CopyrightFormPage.fromRoute({Key? key, int? applyId}) {
    if (applyId != null && applyId > 0) {
      return CopyrightFormPage(
        key: key,
        mode: CopyrightFormMode.resubmit,
        originalApplyId: applyId,
      );
    }
    return CopyrightFormPage(key: key, mode: CopyrightFormMode.create);
  }

  @override
  ConsumerState<CopyrightFormPage> createState() => _CopyrightFormPageState();
}

class _CopyrightFormPageState extends ConsumerState<CopyrightFormPage> {
  final _formKey = GlobalKey<FormState>();
  
  // 表单字段
  MyWorkBrief? _selectedWork;
  String _workType = 'literary';
  CopyrightCenter? _selectedCenter;
  DateTime? _completeTime;
  final TextEditingController _remarkController = TextEditingController();
  final TextEditingController _rightsHolderController = TextEditingController();
  final TextEditingController _idDocNoController = TextEditingController();
  String _idDocType = 'id_card';

  // 分类材料：作品样本 + 身份证明（首版必填）
  List<MaterialFile> _sampleMaterials = [];
  List<MaterialFile> _identityMaterials = [];

  bool _loading = false;
  CopyrightApplication? _originalApplication;
  CopyrightFeeQuote? _feeQuote;
  bool _feeLoading = false;
  String? _feeError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _remarkController.dispose();
    _rightsHolderController.dispose();
    _idDocNoController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    final provider = ref.read(copyrightProvider);

    switch (widget.mode) {
      case CopyrightFormMode.create:
        // 新建模式：加载作品列表和版权中心
        await Future.wait([
          provider.loadMyWorks(),
          provider.loadActiveCenters(),
        ]);
        break;

      case CopyrightFormMode.resubmit:
        // 重新提交模式：加载原申请数据
        if (widget.originalApplyId != null) {
          await provider.loadApplicationDetail(widget.originalApplyId!);
          if (mounted && provider.currentApplication != null) {
            setState(() {
              _originalApplication = provider.currentApplication;
            });
            await _refreshFeeQuote();
          }
        }
        break;
    }
  }

  Future<String?> _uploadFile(PickedFile file) async {
    try {
      final apiService = ref.read(copyrightProvider).apiService;
      final url = await apiService.uploadMaterialFileBytes(
        bytes: file.bytes,
        fileName: file.filename,
      );
      return url;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('文件上传失败：$e')),
        );
      }
      return null;
    }
  }

  Future<void> _selectCompleteTime() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _completeTime ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    
    if (picked != null) {
      setState(() {
        _completeTime = picked;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 新建模式的额外校验
    if (widget.mode == CopyrightFormMode.create) {
      if (_selectedWork == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择要申请版权的作品')),
        );
        return;
      }

      if (_selectedCenter == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请选择版权登记中心')),
        );
        return;
      }
    }

    if (_completeTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择作品完成时间')),
      );
      return;
    }

    if (_rightsHolderController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写权利人姓名')),
      );
      return;
    }
    if (_idDocNoController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写证件号码')),
      );
      return;
    }
    if (_sampleMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请上传作品样本/原创性证明材料')),
      );
      return;
    }
    if (_identityMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请上传作者身份证明材料')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final provider = ref.read(copyrightProvider);
      final CopyrightPayOrder payOrder;
      switch (widget.mode) {
        case CopyrightFormMode.create:
          payOrder = await _submitNewApplication(provider);
          break;
        case CopyrightFormMode.resubmit:
          payOrder = await _submitResubmitApplication(provider);
          break;
      }

      if (mounted) {
        context.push(
          RoutePath.copyrightPayUrl(
            payOrder.payOrderId,
            feeAmount: payOrder.feeAmount,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_getErrorPrefix()}失败：${e.toString().replaceFirst('Exception: ', '')}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<CopyrightPayOrder> _submitNewApplication(
      CopyrightProvider provider) async {
    final dto = CopyrightApplyDTO(
      workId: _selectedWork!.workId,
      workType: _workType,
      completeTime: _formatDate(_completeTime!),
      copyrightCenter: _selectedCenter!.centerCode,
      originalityProof: materialFilesToJson(_sampleMaterials),
      authorIdentityDoc: materialFilesToJson(_identityMaterials),
      creationProcess: null,
      otherProof: null,
      rightsHolderName: _rightsHolderController.text.trim(),
      idDocType: _idDocType,
      idDocNo: _idDocNoController.text.trim(),
      remark: _remarkController.text.trim().isEmpty
          ? null
          : _remarkController.text.trim(),
    );

    return provider.createPayOrder(dto);
  }

  Future<CopyrightPayOrder> _submitResubmitApplication(
      CopyrightProvider provider) async {
    final dto = CopyrightResubmitDTO(
      originalApplyId: widget.originalApplyId!,
      workType: _workType,
      completeTime: _formatDate(_completeTime!),
      originalityProof: materialFilesToJson(_sampleMaterials),
      authorIdentityDoc: materialFilesToJson(_identityMaterials),
      creationProcess: null,
      otherProof: null,
      remark: _remarkController.text.trim().isEmpty
          ? '驳回后重新申请'
          : _remarkController.text.trim(),
    );

    return provider.createResubmitPayOrder(dto);
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _getTitle() {
    switch (widget.mode) {
      case CopyrightFormMode.create:
        return '版权登记申请';
      case CopyrightFormMode.resubmit:
        return '重新提交申请';
    }
  }

  String _getErrorPrefix() {
    switch (widget.mode) {
      case CopyrightFormMode.create:
        return '下单';
      case CopyrightFormMode.resubmit:
        return '重新下单';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Container(
        color: AppColors.pageBackground,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 新建模式：显示作品选择和版权中心选择
              if (widget.mode == CopyrightFormMode.create) ...[
                _buildWorkSelector(),
                const SizedBox(height: 16),
                _buildCenterSelector(),
                const SizedBox(height: 16),
              ],

              // 编辑/重新提交模式：显示作品信息（只读）
              if (widget.mode != CopyrightFormMode.create) ...[
                _buildWorkInfoCard(),
                const SizedBox(height: 16),
              ],

              // 作品类型
              _buildWorkTypeSelector(),
              const SizedBox(height: 16),

              // 完成时间
              _buildCompleteTimeSelector(),
              const SizedBox(height: 16),

              // 权利人信息
              _buildRightsHolderCard(),
              const SizedBox(height: 16),

              // 分类材料上传
              _buildMaterialsUploader(),
              const SizedBox(height: 16),

              // 登记费用
              _buildFeeCard(),
              const SizedBox(height: 16),

              // 备注
              _buildRemarkField(),
              const SizedBox(height: 24),

              // 提交按钮
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkSelector() {
    final provider = ref.watch(copyrightProvider);
    final works = provider.myWorks;
    final loading = provider.worksLoading;
    final error = provider.worksError;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.article_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  '选择作品',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ' *',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '作品列表加载失败，请重试',
                    style: TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: () => ref.read(copyrightProvider).loadMyWorks(),
                    child: const Text('重新加载'),
                  ),
                ],
              )
            else if (works.isEmpty)
              const Text(
                '暂无可选作品。请先在「创作」中创建作品后再来申请版权。',
                style: TextStyle(color: AppColors.text3, fontSize: 13),
              )
            else
              DropdownButtonFormField<MyWorkBrief>(
                value: _selectedWork != null &&
                        works.any((w) => w.workId == _selectedWork!.workId)
                    ? works.firstWhere((w) => w.workId == _selectedWork!.workId)
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  hintText: '请选择要申请版权的作品',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: works
                    .map((work) => DropdownMenuItem(
                          value: work,
                          child: Text(
                            work.workName.isEmpty ? '作品 #${work.workId}' : work.workName,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (work) {
                  setState(() {
                    _selectedWork = work;
                  });
                  _refreshFeeQuote();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterSelector() {
    final provider = ref.watch(copyrightProvider);
    final centers = provider.centers;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.location_city_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  '版权登记中心',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  ' *',
                  style: TextStyle(color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CopyrightCenter>(
              value: _selectedCenter,
              decoration: const InputDecoration(
                hintText: '请选择版权登记中心',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: centers
                  .map((center) => DropdownMenuItem(
                        value: center,
                        child: Text(
                          center.centerName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ))
                  .toList(),
              onChanged: (center) {
                setState(() {
                  _selectedCenter = center;
                });
                _refreshFeeQuote();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refreshFeeQuote() async {
    if (widget.mode == CopyrightFormMode.resubmit) {
      final app = _originalApplication;
      if (app == null || app.workId <= 0 || app.copyrightCenter.isEmpty) {
        return;
      }
      await _loadFeeQuote(workId: app.workId, centerCode: app.copyrightCenter);
      return;
    }
    if (_selectedWork == null || _selectedCenter == null) {
      setState(() {
        _feeQuote = null;
        _feeError = null;
      });
      return;
    }
    await _loadFeeQuote(
      workId: _selectedWork!.workId,
      centerCode: _selectedCenter!.centerCode,
    );
  }

  Future<void> _loadFeeQuote({
    required int workId,
    required String centerCode,
  }) async {
    setState(() {
      _feeLoading = true;
      _feeError = null;
    });
    try {
      final quote = await ref.read(copyrightProvider).feeQuote(
            workId: workId,
            copyrightCenter: centerCode,
          );
      if (!mounted) return;
      setState(() {
        _feeQuote = quote;
        _feeLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _feeQuote = null;
        _feeLoading = false;
        _feeError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _buildFeeCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.payments_outlined, color: AppColors.primary),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '登记费用',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: _showFeeExplanation,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    '费用说明',
                    style: TextStyle(fontSize: 13, color: AppColors.text1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_feeLoading)
              const Text('费用计算中…', style: TextStyle(color: AppColors.text3))
            else if (_feeError != null)
              Text(_feeError!, style: const TextStyle(color: Colors.red))
            else if (_feeQuote == null)
              const Text(
                '请先选择作品和版权中心',
                style: TextStyle(color: AppColors.text3),
              )
            else ...[
              Text(
                '¥${_feeQuote!.feeAmount.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.text1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '正文字数 ${_feeQuote!.wordCount} 字 · 费用交给版权登记中心，平台不另收服务费',
                style: const TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFeeExplanation() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '费用说明',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1,
                  ),
                ),
                const SizedBox(height: 14),
                _buildFeeRuleItem('费用交给所选版权登记中心，平台不另收服务费。'),
                _buildFeeRuleItem('国版中心：按作品正文字数分档计价。'),
                _buildFeeRuleItem('地方中心：按中心一口价计费。'),
                _buildFeeRuleItem('选完作品和版权中心后显示应付金额。'),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('知道了'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeeRuleItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 7),
            child: Icon(Icons.circle, size: 6, color: AppColors.text3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 14,
                height: 1.45,
                color: AppColors.text2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkInfoCard() {
    final app = _originalApplication;

    if (app == null) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.article_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  '作品信息',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              app.workName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '申请编号：${app.applyNo}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.text3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkTypeSelector() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.category_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  '作品类型',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTypeChip('剧本', 'script'),
                _buildTypeChip('小说', 'novel'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String label, String value) {
    final isSelected = _workType == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() {
            _workType = value;
          });
        }
      },
      selectedColor: AppColors.primary.withOpacity(0.2),
      labelStyle: TextStyle(
        color: AppColors.text1,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _buildCompleteTimeSelector() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: InkWell(
        onTap: _selectCompleteTime,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined, color: AppColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '作品完成时间',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.text2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _completeTime != null
                          ? _formatDate(_completeTime!)
                          : '请选择作品完成时间',
                      style: TextStyle(
                        fontSize: 16,
                        color: _completeTime != null
                            ? AppColors.text1
                            : AppColors.text3,
                        fontWeight: _completeTime != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightsHolderCard() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.badge_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  '权利人信息',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(' *', style: TextStyle(color: Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _rightsHolderController,
              decoration: const InputDecoration(
                labelText: '权利人姓名',
                hintText: '与证件一致的姓名',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写权利人姓名' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _idDocType,
              decoration: const InputDecoration(
                labelText: '证件类型',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              items: const [
                DropdownMenuItem(value: 'id_card', child: Text('居民身份证')),
                DropdownMenuItem(value: 'passport', child: Text('护照')),
                DropdownMenuItem(
                    value: 'hk_macau_pass', child: Text('港澳居民来往内地通行证')),
                DropdownMenuItem(
                    value: 'taiwan_pass', child: Text('台湾居民来往大陆通行证')),
                DropdownMenuItem(value: 'other', child: Text('其他')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _idDocType = v);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _idDocNoController,
              decoration: const InputDecoration(
                labelText: '证件号码',
                hintText: '请填写证件号码',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? '请填写证件号码' : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialsUploader() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.upload_file_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  '申请材料（必填）',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(' *', style: TextStyle(color: Colors.red)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '须分别上传作品样本与身份证明，支持图片（JPG/PNG）和 PDF',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text3,
              ),
            ),
            const Divider(height: 24),
            MaterialUploadSection(
              title: '作品样本 / 原创性证明',
              description: '作品全文、样本稿或原创性说明，最多 10 个文件',
              files: _sampleMaterials,
              onFilesChanged: (files) {
                setState(() => _sampleMaterials = files);
              },
              maxFiles: 10,
              onUploadFile: _uploadFile,
            ),
            const SizedBox(height: 16),
            MaterialUploadSection(
              title: '作者身份证明',
              description: '身份证正反面或护照等，最多 5 个文件',
              files: _identityMaterials,
              onFilesChanged: (files) {
                setState(() => _identityMaterials = files);
              },
              maxFiles: 5,
              onUploadFile: _uploadFile,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRemarkField() {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.note_outlined, color: AppColors.primary),
                SizedBox(width: 12),
                Text(
                  '备注说明',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.text2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remarkController,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: '请输入备注信息（选填）',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _loading ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                _getSubmitButtonText(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  String _getSubmitButtonText() {
    switch (widget.mode) {
      case CopyrightFormMode.create:
        return _feeQuote == null
            ? '去支付'
            : '去支付 ¥${_feeQuote!.feeAmount.toStringAsFixed(2)}';
      case CopyrightFormMode.resubmit:
        return _feeQuote == null
            ? '重新缴费'
            : '重新缴费 ¥${_feeQuote!.feeAmount.toStringAsFixed(2)}';
    }
  }
}
