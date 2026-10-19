import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/network/api_exception.dart';
import '../../core/services/native_file_picker.dart';
import '../../core/services/native_image_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../features/user_center/data/user_center_providers.dart';
import 'data/seal_providers.dart';

/// 印章上传页（首次提交印章）。
///
/// 功能：
/// 1. 输入印章名称
/// 2. 上传印章图片（调用真实上传接口）
/// 3. 上传审核材料（可选，调用真实上传接口）
/// 4. 提交印章申请
class SealUploadPage extends ConsumerStatefulWidget {
  const SealUploadPage({super.key});

  @override
  ConsumerState<SealUploadPage> createState() => _SealUploadPageState();
}

class _SealUploadPageState extends ConsumerState<SealUploadPage> {
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

  bool get _busy => _isSubmitting || _uploadingSeal || _uploadingMaterial || _pickingSeal || _pickingMaterial;

  @override
  void dispose() {
    _sealNameController.dispose();
    _clearSealPreview();
    for (final material in _materials) {
      material.preview?.evict();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackground,
      appBar: AppBar(
        title: const Text('上传印章'),
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
            const Row(
              children: [
                Text(
                  '印章图片',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppColors.text1),
                ),
                SizedBox(width: 4),
                Text('*', style: TextStyle(color: AppColors.danger)),
              ],
            ),
            const SizedBox(height: 12),
            if (_sealPreview == null)
              GestureDetector(
                onTap: _busy ? null : _pickSealImage,
                child: Container(
                  width: double.infinity,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppColors.fill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: _uploadingSeal
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 8),
                            Text('上传中...', style: TextStyle(fontSize: 14, color: AppColors.text3)),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate,
                              size: 48,
                              color: _busy ? AppColors.text3.withOpacity(0.5) : AppColors.text3,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '点击上传印章图片',
                              style: TextStyle(
                                fontSize: 14,
                                color: _busy ? AppColors.text3.withOpacity(0.5) : AppColors.text3,
                              ),
                            ),
                          ],
                        ),
                ),
              )
            else
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(
                      image: _sealPreview!,
                      width: double.infinity,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (_uploadingSeal)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black54,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                    ),
                  if (!_busy)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        onPressed: _removeSealImage,
                        icon: const Icon(Icons.close),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            if (_sealUploadError != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _sealUploadError!,
                      style: const TextStyle(fontSize: 12, color: AppColors.danger),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _uploadSealImage,
                    child: const Text('重试', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ],
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
              '支持上传图片、PDF、Word、Excel 等文件（可选）',
              style: TextStyle(fontSize: 12, color: AppColors.text3),
            ),
            const SizedBox(height: 12),
            if (_materials.isNotEmpty)
              ..._materials.asMap().entries.map((entry) {
                final index = entry.key;
                final material = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      // 显示预览或文件图标
                      if (material.preview != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: Image(
                            image: material.preview!,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppColors.fill,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(material.fileIcon, color: AppColors.text3, size: 28),
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              material.file.filename,
                              style: const TextStyle(fontSize: 14, color: AppColors.text2),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            if (material.uploading)
                              const Text(
                                '上传中...',
                                style: TextStyle(fontSize: 12, color: AppColors.text3),
                              )
                            else if (material.error != null)
                              Text(
                                material.error!,
                                style: const TextStyle(fontSize: 12, color: AppColors.danger),
                              )
                            else if (material.ref != null)
                              Text(
                                '已上传 · ${material.file.sizeFormatted}',
                                style: const TextStyle(fontSize: 12, color: AppColors.success),
                              )
                            else
                              Text(
                                material.file.sizeFormatted,
                                style: const TextStyle(fontSize: 12, color: AppColors.text3),
                              ),
                          ],
                        ),
                      ),
                      if (!_busy && material.error != null)
                        IconButton(
                          onPressed: () => _retryUploadMaterial(index),
                          icon: const Icon(Icons.refresh, size: 20, color: AppColors.warning),
                        ),
                      if (!_busy)
                        IconButton(
                          onPressed: () => _removeMaterial(index),
                          icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.danger),
                        ),
                    ],
                  ),
                );
              }),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickMaterial,
              icon: const Icon(Icons.upload_file),
              label: const Text('上传材料'),
            ),
          ],
        ),
      ),
    );
  }

  /// 提交按钮。
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _isSubmitting || _busy ? null : _submitSeal,
        child: _isSubmitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text('提交审核'),
      ),
    );
  }

  /// 帮助文本。
  Widget _buildHelpText() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryTint,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: AppColors.primary),
              SizedBox(width: 8),
              Text('温馨提示', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.primary)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            '1. 印章图片需清晰可见，建议使用 PNG 或 JPG 格式\n'
            '2. 审核材料支持上传图片、PDF、Word、Excel 等文件，单个文件不超过 20 MB\n'
            '3. 提交后将进入审核流程，请耐心等待\n'
            '4. 审核通过后印章即可用于版权认证',
            style: TextStyle(fontSize: 13, color: AppColors.text2, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// 选择印章图片。
  Future<void> _pickSealImage() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _pickingSeal = true);
    try {
      final image = await NativeImagePicker.pickImage(filenamePrefix: 'seal');
      if (image == null || !mounted) return;
      setState(() {
        _clearSealPreview();
        _sealImage = image;
        _sealPreview = MemoryImage(Uint8List.fromList(image.bytes));
        _sealImageRef = null;
        _sealUploadError = null;
      });
      await _uploadSealImage();
    } on NativeImageException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('无法选择图片，请重试');
    } finally {
      if (mounted) setState(() => _pickingSeal = false);
    }
  }

  /// 上传印章图片。
  Future<void> _uploadSealImage() async {
    final image = _sealImage;
    if (image == null || _uploadingSeal || _isSubmitting) return;
    setState(() {
      _uploadingSeal = true;
      _sealUploadError = null;
    });
    try {
      // 使用通用内容上传接口
      final url = await ref.read(sealRepositoryProvider).uploadMaterial(
            bytes: image.bytes,
            filename: image.filename,
          );
      if (mounted) setState(() => _sealImageRef = url);
    } on ApiException catch (e) {
      if (mounted) setState(() => _sealUploadError = e.message);
    } catch (_) {
      if (mounted) setState(() => _sealUploadError = '上传失败，请检查网络后重试');
    } finally {
      if (mounted) setState(() => _uploadingSeal = false);
    }
  }

  /// 移除印章图片。
  void _removeSealImage() {
    if (_busy) return;
    setState(() {
      _clearSealPreview();
      _sealImageRef = null;
      _sealUploadError = null;
    });
  }

  void _clearSealPreview() {
    unawaited(_sealPreview?.evict());
    _sealPreview = null;
    _sealImage = null;
  }

  /// 选择审核材料（支持图片、PDF、Word 等文件）。
  Future<void> _pickMaterial() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _pickingMaterial = true);
    try {
      print('[SealUpload] 开始选择审核材料文件...');
      final file = await NativeFilePicker.pickAny(filenamePrefix: 'seal_material');
      print('[SealUpload] 选择结果: ${file != null ? "已选择 ${file.filename} (${file.sizeFormatted})" : "用户取消"}');
      
      if (file == null || !mounted) {
        print('[SealUpload] 用户取消选择或页面已销毁');
        return;
      }
      
      // 如果是图片文件，尝试创建预览
      MemoryImage? preview;
      if (_isImageFile(file)) {
        try {
          preview = MemoryImage(Uint8List.fromList(file.bytes));
        } catch (e) {
          print('[SealUpload] 无法创建图片预览: $e');
        }
      }
      
      final materialItem = _MaterialItem(
        file: file,
        preview: preview,
        uploading: true,
      );
      
      print('[SealUpload] 添加材料到列表并开始上传');
      setState(() => _materials.add(materialItem));
      await _uploadMaterialItem(materialItem);
    } on NativeFileException catch (e) {
      print('[SealUpload] NativeFileException: ${e.message}');
      _toast(e.message);
    } catch (e) {
      print('[SealUpload] 选择文件异常: $e');
      _toast('无法选择文件，请重试');
    } finally {
      if (mounted) setState(() => _pickingMaterial = false);
    }
  }

  /// 判断是否为图片文件。
  bool _isImageFile(PickedFile file) {
    final ext = file.extension?.toLowerCase();
    return ext != null && ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }

  /// 上传审核材料。
  Future<void> _uploadMaterialItem(_MaterialItem item) async {
    if (_uploadingMaterial) return;
    setState(() => _uploadingMaterial = true);
    try {
      print('[SealUpload] 开始上传审核材料: ${item.file.filename}');
      // 使用通用内容上传接口，支持图片和文档
      final url = await ref.read(sealRepositoryProvider).uploadMaterial(
            bytes: item.file.bytes,
            filename: item.file.filename,
          );
      print('[SealUpload] 审核材料上传成功，URL: $url');
      if (mounted) {
        setState(() {
          item.ref = url;
          item.uploading = false;
          item.error = null;
        });
      }
    } on ApiException catch (e) {
      print('[SealUpload] 审核材料上传失败 (ApiException): ${e.message}');
      if (mounted) {
        setState(() {
          item.uploading = false;
          item.error = e.message;
        });
      }
    } catch (e) {
      print('[SealUpload] 审核材料上传失败 (未知错误): $e');
      if (mounted) {
        setState(() {
          item.uploading = false;
          item.error = '上传失败';
        });
      }
    } finally {
      if (mounted) setState(() => _uploadingMaterial = false);
    }
  }

  /// 重试上传材料。
  Future<void> _retryUploadMaterial(int index) async {
    if (_busy || index >= _materials.length) return;
    final item = _materials[index];
    setState(() {
      item.uploading = true;
      item.error = null;
    });
    await _uploadMaterialItem(item);
  }

  /// 移除审核材料。
  void _removeMaterial(int index) {
    if (_busy || index >= _materials.length) return;
    setState(() {
      final item = _materials.removeAt(index);
      item.preview?.evict();
    });
  }

  /// 提交印章。
  Future<void> _submitSeal() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_sealImageRef == null) {
      _toast('请先上传印章图片');
      return;
    }

    // 检查是否有材料上传失败
    final failedMaterials = _materials.where((m) => m.error != null).toList();
    if (failedMaterials.isNotEmpty) {
      _toast('请先处理上传失败的材料');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final repo = ref.read(sealRepositoryProvider);
      final materialRefs = _materials.where((m) => m.ref != null).map((m) => m.ref!).toList();
      
      await repo.submitSeal(
        sealName: _sealNameController.text.trim(),
        sealImageUrl: _sealImageRef!,
        materialUrls: materialRefs.isEmpty ? null : materialRefs.join(','),
      );

      if (mounted) {
        _toast('提交成功，请等待审核');
        ref.invalidate(mySealsProvider);
        context.pop();
      }
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('提交失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 审核材料项（支持图片和文档文件）。
class _MaterialItem {
  _MaterialItem({
    required this.file,
    this.preview,
    this.uploading = false,
    this.ref,
    this.error,
  });

  final PickedFile file;
  final MemoryImage? preview;
  bool uploading;
  String? ref;
  String? error;

  bool get isImage {
    final ext = file.extension?.toLowerCase();
    return ext != null && ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
  }

  IconData get fileIcon {
    final ext = file.extension?.toLowerCase();
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
}
