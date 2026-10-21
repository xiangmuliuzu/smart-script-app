/// 版权申请统一表单页（App 端）- 支持新建/编辑/重新提交。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

  // 分类材料
  List<MaterialFile> _applicationMaterials = [];

  bool _loading = false;
  CopyrightApplication? _originalApplication;

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

    // 至少上传一份申请材料
    if (_applicationMaterials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少上传一份申请材料')),
      );
      return;
    }

    setState(() {
      _loading = true;
    });

    try {
      final provider = ref.read(copyrightProvider);

      switch (widget.mode) {
        case CopyrightFormMode.create:
          await _submitNewApplication(provider);
          break;
        case CopyrightFormMode.resubmit:
          await _submitResubmitApplication(provider);
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_getSuccessMessage())),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_getErrorPrefix()}失败：$e')),
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

  Future<void> _submitNewApplication(CopyrightProvider provider) async {
    final dto = CopyrightApplyDTO(
      workId: _selectedWork!.workId,
      workType: _workType,
      completeTime: _formatDate(_completeTime!),
      copyrightCenter: _selectedCenter!.centerCode,
      originalityProof: _applicationMaterials.isNotEmpty
          ? materialFilesToJson(_applicationMaterials)
          : null,
      authorIdentityDoc: null,
      creationProcess: null,
      otherProof: null,
      remark: _remarkController.text.trim().isEmpty
          ? null
          : _remarkController.text.trim(),
    );

    await provider.submitApplication(dto);
  }

  Future<void> _submitResubmitApplication(CopyrightProvider provider) async {
    final dto = CopyrightResubmitDTO(
      originalApplyId: widget.originalApplyId!,
      workType: _workType,
      completeTime: _formatDate(_completeTime!),
      originalityProof: _applicationMaterials.isNotEmpty
          ? materialFilesToJson(_applicationMaterials)
          : null,
      authorIdentityDoc: null,
      creationProcess: null,
      otherProof: null,
      remark: _remarkController.text.trim().isEmpty
          ? null
          : _remarkController.text.trim(),
    );

    await provider.resubmitApplication(dto);
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

  String _getSuccessMessage() {
    switch (widget.mode) {
      case CopyrightFormMode.create:
        return '申请提交成功';
      case CopyrightFormMode.resubmit:
        return '重新提交成功';
    }
  }

  String _getErrorPrefix() {
    switch (widget.mode) {
      case CopyrightFormMode.create:
        return '提交';
      case CopyrightFormMode.resubmit:
        return '重新提交';
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

              // 分类材料上传
              _buildMaterialsUploader(),
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
              },
            ),
          ],
        ),
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
        color: isSelected ? AppColors.primary : AppColors.text1,
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
                  '申请材料（分类上传）',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '请根据材料类型分类上传，支持图片（JPG/PNG）和 PDF 文档',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.text3,
              ),
            ),
            const Divider(height: 24),
            
            MaterialUploadSection(
              title: '申请材料',
              description: '支持上传图片（jpg、png）、文档（pdf、doc、docx）和文本文件（txt），最多上传20个文件',
              files: _applicationMaterials,
              onFilesChanged: (files) {
                setState(() => _applicationMaterials = files);
              },
              maxFiles: 20,
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
        return '提交申请';
      case CopyrightFormMode.resubmit:
        return '重新提交';
    }
  }
}
