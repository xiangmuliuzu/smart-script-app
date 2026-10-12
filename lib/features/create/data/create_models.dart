/// B 模块创作（上传 / 版本）页面模型与解析辅助。
///
/// 字段与后端一一对应，不自行拼装：
///   - [UploadResult]       ← 接口 2.9.1（fileId 恒为 null）
///   - [WorkVersionItem]    ← 接口 2.9.7 版本列表元素（不含 content）
///   - [WorkVersionDetail]  ← 接口 2.9.9 单版本详情（含 content）
///
/// 「我的作品」写作链路（列表 / 详情 / 章节 / 审核）的模型见
/// `author_work_models.dart`（A 套 /users/me/works）。
library;

String _text(dynamic value) => value == null ? '' : value.toString();

String? _textOrNull(dynamic value) => value?.toString();

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _intOrNull(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) return int.tryParse(value);
  return null;
}

/// 文件上传结果（接口 2.9.1，data={fileId, url, fileName, size}）。
///
/// 契约中 fileId 恒为 null（当前上传不落库），保留字段以对齐响应；
/// size 用于创建作品时一并上送，落 sys_work_file.file_size（NOT NULL）。
class UploadResult {
  const UploadResult({this.fileId, this.url = '', this.fileName = '', this.size});

  final String? fileId;
  final String url;
  final String fileName;
  final int? size;

  factory UploadResult.fromJson(Map<String, dynamic> json) => UploadResult(
        fileId: _textOrNull(json['fileId']),
        url: _text(json['url']),
        fileName: _text(json['fileName']),
        size: _intOrNull(json['size']),
      );
}

/// 作品版本列表条目（接口 2.9.7，列表不下发 content）。
class WorkVersionItem {
  const WorkVersionItem({
    required this.versionId,
    this.versionNo = '',
    this.changeLog,
    this.isCurrent,
    this.createTime,
  });

  final int versionId;
  final String versionNo;
  final String? changeLog;

  /// tinyint 列以字符串 "0"/"1" 下发。
  final String? isCurrent;
  final String? createTime;

  bool get isCurrentVersion => isCurrent == '1';

  factory WorkVersionItem.fromJson(Map<String, dynamic> json) => WorkVersionItem(
        versionId: _int(json['versionId']),
        versionNo: _text(json['versionNo']),
        changeLog: _textOrNull(json['changeLog']),
        isCurrent: _textOrNull(json['isCurrent']),
        createTime: _textOrNull(json['createTime']),
      );
}

/// 单版本详情（接口 2.9.9，含 content 全文）。
class WorkVersionDetail {
  const WorkVersionDetail({
    required this.versionId,
    this.versionNo = '',
    this.content,
    this.changeLog,
    this.createTime,
  });

  final int versionId;
  final String versionNo;
  final String? content;
  final String? changeLog;
  final String? createTime;

  factory WorkVersionDetail.fromJson(Map<String, dynamic> json) => WorkVersionDetail(
        versionId: _int(json['versionId']),
        versionNo: _text(json['versionNo']),
        content: _textOrNull(json['content']),
        changeLog: _textOrNull(json['changeLog']),
        createTime: _textOrNull(json['createTime']),
      );
}