import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// 通用文件选择器（支持图片、PDF、Word、Excel 等）。
///
/// 用于上传审核材料等场景，支持多种文件类型。
class NativeFilePicker {
  NativeFilePicker._();

  static const int maxFileBytes = 20 * 1024 * 1024; // 20 MB

  /// 选择文件（支持图片、PDF、Word、Excel 等）。
  ///
  /// 返回所选文件的字节与文件名；用户取消返回 null。
  static Future<PickedFile?> pickFile({
    String filenamePrefix = 'material',
    FileType type = FileType.any,
    List<String>? allowedExtensions,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        return null;
      }

      final platformFile = result.files.first;
      
      // 优先使用 bytes（Web 平台）
      if (platformFile.bytes != null) {
        final bytes = platformFile.bytes!;
        if (bytes.isEmpty) {
          throw NativeFileException('文件不能为空');
        }
        if (bytes.length > maxFileBytes) {
          throw NativeFileException('文件不能超过 20 MB');
        }
        return PickedFile(
          bytes: bytes,
          filename: platformFile.name,
          extension: platformFile.extension,
          size: bytes.length,
        );
      }

      // 使用 path（移动平台）
      if (platformFile.path != null) {
        final file = File(platformFile.path!);
        if (!await file.exists()) {
          throw NativeFileException('文件不存在');
        }

        final size = await file.length();
        if (size == 0) {
          throw NativeFileException('文件不能为空');
        }
        if (size > maxFileBytes) {
          throw NativeFileException('文件不能超过 20 MB');
        }

        final bytes = await file.readAsBytes();
        return PickedFile(
          bytes: bytes,
          filename: platformFile.name,
          extension: platformFile.extension,
          size: size,
        );
      }

      throw NativeFileException('无法读取文件');
    } catch (e) {
      if (e is NativeFileException) rethrow;
      throw NativeFileException('选择文件失败: ${e.toString()}');
    }
  }

  /// 选择图片文件。
  static Future<PickedFile?> pickImage({String filenamePrefix = 'image'}) {
    return pickFile(
      filenamePrefix: filenamePrefix,
      type: FileType.image,
    );
  }

  /// 选择文档文件（PDF、Word、Excel 等）。
  static Future<PickedFile?> pickDocument({String filenamePrefix = 'document'}) {
    return pickFile(
      filenamePrefix: filenamePrefix,
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'],
    );
  }

  /// 选择任意文件（用于审核材料等场景）。
  static Future<PickedFile?> pickAny({String filenamePrefix = 'file'}) {
    return pickFile(
      filenamePrefix: filenamePrefix,
      type: FileType.any,
    );
  }
}

/// 已选择的文件。
class PickedFile {
  const PickedFile({
    required this.bytes,
    required this.filename,
    this.extension,
    required this.size,
  });

  final List<int> bytes;
  final String filename;
  final String? extension;
  final int size;

  int get sizeInBytes => bytes.length;

  String get sizeFormatted {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get displayName {
    if (extension != null && extension!.isNotEmpty) {
      return filename;
    }
    return filename;
  }
}

class NativeFileException implements Exception {
  NativeFileException(this.message);

  final String message;

  @override
  String toString() => message;
}
