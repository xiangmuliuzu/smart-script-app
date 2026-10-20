/// 版权申请材料分类上传组件
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/services/native_file_picker.dart';

/// 材料文件信息
class MaterialFile {
  const MaterialFile({
    required this.url,
    required this.filename,
    required this.fileType,
  });

  final String url;
  final String filename;
  final String fileType; // 'image' | 'pdf' | 'other'

  Map<String, dynamic> toJson() => {
        'url': url,
        'filename': filename,
        'fileType': fileType,
      };

  factory MaterialFile.fromJson(Map<String, dynamic> json) => MaterialFile(
        url: json['url'] as String,
        filename: json['filename'] as String,
        fileType: json['fileType'] as String? ?? 'other',
      );

  bool get isImage =>
      fileType == 'image' ||
      filename.toLowerCase().endsWith('.jpg') ||
      filename.toLowerCase().endsWith('.jpeg') ||
      filename.toLowerCase().endsWith('.png') ||
      filename.toLowerCase().endsWith('.bmp') ||
      filename.toLowerCase().endsWith('.gif') ||
      filename.toLowerCase().endsWith('.webp');

  bool get isPdf => fileType == 'pdf' || filename.toLowerCase().endsWith('.pdf');

  bool get isDocument =>
      fileType == 'document' ||
      filename.toLowerCase().endsWith('.doc') ||
      filename.toLowerCase().endsWith('.docx') ||
      filename.toLowerCase().endsWith('.txt');
}

/// 分类材料上传区域
class MaterialUploadSection extends StatefulWidget {
  const MaterialUploadSection({
    super.key,
    required this.title,
    required this.description,
    required this.files,
    required this.onFilesChanged,
    this.maxFiles = 5,
    this.onUploadFile,
  });

  final String title;
  final String description;
  final List<MaterialFile> files;
  final ValueChanged<List<MaterialFile>> onFilesChanged;
  final int maxFiles;
  final Future<String?> Function(PickedFile)? onUploadFile;

  @override
  State<MaterialUploadSection> createState() => _MaterialUploadSectionState();
}

class _MaterialUploadSectionState extends State<MaterialUploadSection> {
  bool _uploading = false;

  Future<void> _pickAndUploadFile() async {
    if (widget.files.length >= widget.maxFiles) {
      _showMessage('最多只能上传 ${widget.maxFiles} 个文件');
      return;
    }

    try {
      final result = await NativeFilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'],
      );

      if (result == null) return;

      setState(() => _uploading = true);

      // 调用上传回调
      String? url;
      if (widget.onUploadFile != null) {
        url = await widget.onUploadFile!(result);
      }

      if (url == null || url.isEmpty) {
        _showMessage('文件上传失败');
        return;
      }

      // 判断文件类型
      String fileType = 'other';
      final ext = result.filename.toLowerCase().split('.').last;
      if (['jpg', 'jpeg', 'png', 'bmp', 'gif', 'webp'].contains(ext)) {
        fileType = 'image';
      } else if (ext == 'pdf') {
        fileType = 'pdf';
      } else if (['doc', 'docx', 'txt'].contains(ext)) {
        fileType = 'document';
      }

      // 添加到列表
      final newFiles = List<MaterialFile>.from(widget.files)
        ..add(MaterialFile(
          url: url,
          filename: result.filename,
          fileType: fileType,
        ));

      widget.onFilesChanged(newFiles);
      _showMessage('文件上传成功');
    } catch (e) {
      _showMessage('文件上传失败：$e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  void _removeFile(int index) {
    final newFiles = List<MaterialFile>.from(widget.files)..removeAt(index);
    widget.onFilesChanged(newFiles);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.description,
          style: TextStyle(
            fontSize: 14,
            color: AppColors.text2,
          ),
        ),
        const SizedBox(height: 12),
        
        // 文件列表
        if (widget.files.isNotEmpty)
          ...widget.files.asMap().entries.map((entry) {
            final index = entry.key;
            final file = entry.value;
            return _FileItem(
              file: file,
              onRemove: () => _removeFile(index),
            );
          }),
        
        // 上传按钮
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _uploading ? null : _pickAndUploadFile,
          icon: _uploading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_uploading
              ? '上传中...'
              : widget.files.isEmpty
                  ? '选择文件上传'
                  : '继续添加文件 (${widget.files.length}/${widget.maxFiles})'),
        ),
      ],
    );
  }
}

/// 文件列表项
class _FileItem extends StatelessWidget {
  const _FileItem({
    required this.file,
    required this.onRemove,
  });

  final MaterialFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.fill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // 文件图标
          Icon(
            file.isImage
                ? Icons.image
                : file.isPdf
                    ? Icons.picture_as_pdf
                    : file.isDocument
                        ? Icons.description
                        : Icons.insert_drive_file,
            color: file.isImage
                ? Colors.green
                : file.isPdf
                    ? Colors.red
                    : file.isDocument
                        ? Colors.blue
                        : AppColors.text2,
          ),
          const SizedBox(width: 12),
          
          // 文件名
          Expanded(
            child: Text(
              file.filename,
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// 材料文件列表转 JSON 数组字符串
String materialFilesToJson(List<MaterialFile> files) {
  if (files.isEmpty) return '[]';
  return jsonEncode(files.map((f) => f.toJson()).toList());
}

/// JSON 数组字符串转材料文件列表
List<MaterialFile> materialFilesFromJson(String? jsonStr) {
  if (jsonStr == null || jsonStr.isEmpty) return [];
  try {
    final list = jsonDecode(jsonStr) as List;
    return list.map((item) => MaterialFile.fromJson(item as Map<String, dynamic>)).toList();
  } catch (e) {
    return [];
  }
}
