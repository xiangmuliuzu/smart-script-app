import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/services/native_file_picker.dart';
import '../../core/services/native_image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../features/user_center/data/user_center_providers.dart';
import 'data/seal_providers.dart';

/// 印章编辑页（编辑已有印章）。
///
/// 功能：
/// 1. 加载现有印章信息
/// 2. 修改印章名称
/// 3. 更换印章图片（调用真实上传接口）
/// 4. 更换审核材料（调用真实上传接口）
/// 5. 提交更新（修改后重置审核状态为 pending）
class SealEditPage extends ConsumerStatefulWidget {
  const SealEditPage({
    super.key,
    required this.sealId,
  });

  final int sealId;

  @override
  ConsumerState<SealEditPage> createState() => _SealEditPageState();
}

class _SealEditPageState extends ConsumerState<SealEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _sealNameController = TextEditingController();
  
  // 印章图片
  PickedImage? _sealImage;
  MemoryImage? _sealPreview;
  String? _sealImageRef;
  bool _uploadingSeal = false;
  String? _sealUploadError;
  
  // 审核材料
  final List<_MaterialItem> _materials = [];
  bool _uploadingMaterial = false;
  bool _pickingSeal = false;
  bool _pickingMaterial = false;
  
  bool _isSubmitting = false;
  bool _isLoading = true;
  String? _loadError;

  bool get _busy => _isSubmitting || _uploadingSeal || _uploadingMaterial || _pickingSeal || _pickingMaterial;

  @override
  void initState() {
    super.initState();
    _loadSealData();
  }

  @override
  void dispose() {
    _sealNameController.dispose();
    _clearSealPreview();
    for (final material in _materials) {
      material.preview?.evict();
    }
    super.dispose();
  }

  /// 加载印章数据
  Future<void> _loadSealData() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });

    try {
      final detail = await ref.read(sealDetailProvider(widget.sealId).future);
      if (detail == null) {
        setState(() {
          _loadError = '印章不存在或无权限访问';
          _isLoading = false;
        });
        return;
      }

      // 填充数据
      _sealNameController.text = detail.sealName;
      _sealImageRef = AppConfig.resolveAssetUrl(detail.sealImageUrl);

      // 解析材料URL列表
      final materialUrls = detail.materialUrlList;
      for (final url in materialUrls) {
        _materials.add(_MaterialItem(
          ref: url,
          uploading: false,
        ));
      }

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _loadError = '加载失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('编辑印章'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('编辑印章'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_loadError!, style: const TextStyle(color: AppColors.text3)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('编辑印章'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSealNameInput(),
            const SizedBox(height: 16),
            _buildSealImageUpload(),
            const SizedBox(height: 16),
            _buildMaterialsUpload(),
            const SizedBox(height: 24),
            _buildSubmitButton(),
            const SizedBox(height: 24),
            _buildHelpText(),
          ],
        ),
      ),
    );
  }

  /// 印章名称输入。
  Widget _buildSealNameInput() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '印章名称',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _sealNameController,
              decoration: const InputDecoration(
                hintText: '请输入印章名称（如：张三个人印章）',
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return '请输入印章名称';
                }
                if (value.trim().length > 100) {
                  return '印章名称不能超过 100 个字符';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 印章图片上传。
  Widget _buildSealImageUpload() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '印章图片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1),
                ),
                const SizedBox(width: 4),
                const Text('*', style: TextStyle(color: Colors.red)),
              ],
            ),
            const SizedBox(height: 12),
            // 当前印章图片或上传按钮
            if (_sealPreview != null || _sealImageRef != null)
              _buildSealImagePreview()
            else
              _buildSealImageUploadButton(),
            // 上传状态提示
            if (_uploadingSeal)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text('上传中...', style: TextStyle(color: AppColors.text3)),
                  ],
                ),
              ),
            if (_sealUploadError != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _sealUploadError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 印章图片预览（显示当前印章图片 + 更换按钮）。
  Widget _buildSealImagePreview() {
    return Column(
      children: [
        Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: _sealPreview != null
                ? Image(image: _sealPreview!, fit: BoxFit.cover)
                : (_sealImageRef != null
                    ? Image.network(_sealImageRef!, fit: BoxFit.cover)
                    : const SizedBox()),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pickSealImage,
          icon: const Icon(Icons.image, size: 20),
          label: const Text('更换图片'),
        ),
      ],
    );
  }

  /// 印章图片上传按钮。
  Widget _buildSealImageUploadButton() {
    return InkWell(
      onTap: _busy ? null : _pickSealImage,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 200,
        height: 200,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade50,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('点击上传印章图片', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  /// 审核材料上传。
  Widget _buildMaterialsUpload() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '审核材料',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1),
            ),
            const SizedBox(height: 4),
            const Text(
              '可选，支持上传图片、PDF、Word等文档，单个文件不超过20MB',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
            const SizedBox(height: 12),
            // 已上传的材料列表
            if (_materials.isNotEmpty) ...[
              ..._materials.asMap().entries.map((entry) {
                final index = entry.key;
                final material = entry.value;
                return _buildMaterialItem(material, index);
              }),
              const SizedBox(height: 12),
            ],
            // 添加材料按钮
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickMaterial,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('添加材料'),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个材料项。
  Widget _buildMaterialItem(_MaterialItem material, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Row(
        children: [
          // 预览或图标
          if (material.preview != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image(
                image: material.preview!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            )
          else if (material.file != null)
            Icon(_getFileIcon(material.file!.extension), size: 48, color: Colors.grey.shade600)
          else
            Icon(Icons.insert_drive_file, size: 48, color: Colors.grey.shade600),
          const SizedBox(width: 12),
          // 文件信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.file?.filename ?? '已上传的材料',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (material.file != null)
                  Text(
                    material.file!.sizeFormatted,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                if (material.uploading)
                  const Text('上传中...', style: TextStyle(fontSize: 12, color: AppColors.primary))
                else if (material.error != null)
                  Text(material.error!, style: const TextStyle(fontSize: 12, color: Colors.red))
                else if (material.ref != null)
                  const Text('上传成功', style: TextStyle(fontSize: 12, color: Colors.green)),
              ],
            ),
          ),
          // 删除按钮
          if (!material.uploading)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _removeMaterial(index),
            ),
        ],
      ),
    );
  }

  /// 提交按钮。
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _busy ? null : _handleSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
            : const Text('提交修改', style: TextStyle(fontSize: 16)),
      ),
    );
  }

  /// 帮助提示。
  Widget _buildHelpText() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                '温馨提示',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. 修改印章后需要重新审核\n'
            '2. 审核通过前无法使用该印章\n'
            '3. 请确保印章图片清晰完整\n'
            '4. 审核材料可帮助加快审核速度',
            style: TextStyle(fontSize: 13, color: Colors.blue.shade900, height: 1.5),
          ),
        ],
      ),
    );
  }

  void _clearSealPreview() {
    _sealPreview?.evict();
    _sealPreview = null;
  }

  /// 获取文件图标。
  IconData _getFileIcon(String? extension) {
    final ext = extension?.toLowerCase();
    if (ext == null) return Icons.insert_drive_file;
    
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'txt':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'bmp':
      case 'webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  /// 选择印章图片。
  Future<void> _pickSealImage() async {
    setState(() => _pickingSeal = true);
    try {
      final image = await NativeImagePicker.pickImage();
      if (image == null) return;

      // 更新预览
      _clearSealPreview();
      _sealPreview = MemoryImage(Uint8List.fromList(image.bytes));
      _sealImage = image;
      _sealImageRef = null;
      _sealUploadError = null;

      setState(() {});

      // 立即上传
      await _uploadSealImage();
    } finally {
      if (mounted) setState(() => _pickingSeal = false);
    }
  }

  /// 上传印章图片。
  Future<void> _uploadSealImage() async {
    if (_sealImage == null) return;

    setState(() {
      _uploadingSeal = true;
      _sealUploadError = null;
    });

    try {
      final repo = ref.read(sealRepositoryProvider);
      final url = await repo.uploadMaterial(
        bytes: _sealImage!.bytes,
        filename: _sealImage!.filename,
      );
      
      _sealImageRef = url;
    } catch (e) {
      _sealUploadError = '上传失败: $e';
      _sealImageRef = null;
    } finally {
      if (mounted) setState(() => _uploadingSeal = false);
    }
  }

  /// 选择审核材料。
  Future<void> _pickMaterial() async {
    setState(() => _pickingMaterial = true);
    try {
      final file = await NativeFilePicker.pickAny(filenamePrefix: 'seal_material');
      if (file == null) return;

      // 生成预览（仅图片）
      MemoryImage? preview;
      final ext = file.extension?.toLowerCase();
      if (ext != null && ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
        try {
          preview = MemoryImage(Uint8List.fromList(file.bytes));
        } catch (e) {
          // 预览失败不影响上传
        }
      }

      // 添加到列表
      final material = _MaterialItem(
        file: file,
        preview: preview,
        uploading: true,
      );
      _materials.add(material);
      setState(() {});

      // 立即上传
      await _uploadMaterial(material);
    } catch (e) {
      _toast('无法选择文件，请重试');
    } finally {
      if (mounted) setState(() => _pickingMaterial = false);
    }
  }

  /// 上传单个材料。
  Future<void> _uploadMaterial(_MaterialItem material) async {
    if (material.file == null) return;

    try {
      final repo = ref.read(sealRepositoryProvider);
      final url = await repo.uploadMaterial(
        bytes: material.file!.bytes,
        filename: material.file!.filename,
      );
      
      material.ref = url;
      material.error = null;
    } catch (e) {
      material.error = '上传失败: $e';
      material.ref = null;
    } finally {
      material.uploading = false;
      if (mounted) setState(() {});
    }
  }

  /// 移除材料。
  void _removeMaterial(int index) {
    if (index < 0 || index >= _materials.length) return;
    final material = _materials[index];
    material.preview?.evict();
    _materials.removeAt(index);
    setState(() {});
  }

  /// 提交表单。
  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    // 检查印章图片
    if (_sealImageRef == null && _sealImage == null) {
      _toast('请上传印章图片');
      return;
    }

    // 检查印章图片是否正在上传
    if (_uploadingSeal) {
      _toast('请等待印章图片上传完成');
      return;
    }

    // 检查印章图片上传是否失败
    if (_sealUploadError != null) {
      _toast('印章图片上传失败，请重新上传');
      return;
    }

    // 检查是否有材料正在上传
    if (_materials.any((m) => m.uploading)) {
      _toast('请等待所有材料上传完成');
      return;
    }

    // 检查是否有上传失败的材料
    if (_materials.any((m) => m.error != null)) {
      _toast('请移除上传失败的材料或重新上传');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final materialUrls = _materials
          .where((m) => m.ref != null)
          .map((m) => m.ref!)
          .join(',');

      await ref.read(sealRepositoryProvider).updateSeal(
            sealId: widget.sealId,
            sealName: _sealNameController.text.trim(),
            sealImageUrl: _sealImageRef,
            materialUrls: materialUrls.isNotEmpty ? materialUrls : null,
          );

      if (mounted) {
        _toast('印章已更新，等待重新审核');
        // 刷新数据
        ref.invalidate(mySealsProvider);
        ref.invalidate(sealDetailProvider(widget.sealId));
        // 返回详情页
        context.pop();
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('提交失败: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

/// 材料项数据。
class _MaterialItem {
  _MaterialItem({
    this.file,
    this.preview,
    this.ref,
    this.uploading = false,
    this.error,
  });

  final PickedFile? file;
  final MemoryImage? preview;
  String? ref;
  bool uploading;
  String? error;
}
