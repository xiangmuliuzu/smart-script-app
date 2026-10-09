/// B 模块创作（上传 / 草稿 / 版本 / 审核）页面模型与解析辅助。
///
/// 字段与后端一一对应，不自行拼装：
///   - [UploadResult]       ← 接口 2.9.1（fileId 恒为 null）
///   - [DraftWorkItem]      ← 接口 2.9.5 草稿箱元素
///   - [ReviewStatus]       ← 接口 2.9.6
///   - [WorkVersionItem]    ← 接口 2.9.7 版本列表元素（不含 content）
///   - [WorkVersionDetail]  ← 接口 2.9.9 单版本详情（含 content）
///   - [AuthorChapterItem]  ← 章节管理（接口文档无 CRUD 规格，按模块约定补齐）
library;

bool _flag(dynamic value) => value == '1' || value == 1 || value == true;

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

double? _decimalOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String && value.isNotEmpty) return double.tryParse(value);
  return null;
}

/// 文件上传结果（接口 2.9.1，data={fileId, url, fileName}）。
///
/// 契约中 fileId 恒为 null（当前上传不落库），保留字段以对齐响应。
class UploadResult {
  const UploadResult({this.fileId, this.url = '', this.fileName = ''});

  final String? fileId;
  final String url;
  final String fileName;

  factory UploadResult.fromJson(Map<String, dynamic> json) => UploadResult(
        fileId: _textOrNull(json['fileId']),
        url: _text(json['url']),
        fileName: _text(json['fileName']),
      );
}

/// 草稿箱条目（接口 2.9.5，status 恒为 draft）。
class DraftWorkItem {
  const DraftWorkItem({
    required this.workId,
    this.title = '',
    this.cover,
    this.genreId,
    this.genreName,
    this.summary,
    this.price,
    this.status = '',
    this.createTime,
  });

  final int workId;
  final String title;
  final String? cover;
  final int? genreId;
  final String? genreName;
  final String? summary;
  final double? price;
  final String status;

  /// 创建时间（"yyyy-MM-dd HH:mm:ss"）。
  final String? createTime;

  /// 价格展示文案：未定价时展示「未定价」。
  String get priceLabel => price == null ? '未定价' : '¥${price!.toStringAsFixed(2)}';

  factory DraftWorkItem.fromJson(Map<String, dynamic> json) => DraftWorkItem(
        workId: _int(json['workId']),
        title: _text(json['title']),
        cover: _textOrNull(json['cover']),
        genreId: _intOrNull(json['genreId']),
        genreName: _textOrNull(json['genreName']),
        summary: _textOrNull(json['summary']),
        price: _decimalOrNull(json['price']),
        status: _text(json['status']),
        createTime: _textOrNull(json['createTime']),
      );
}

/// 作品审核状态（接口 2.9.6：status / reviewResult / reviewComment）。
///
/// status 为作品状态枚举（PRD），reviewResult 为最近一次审核结论。
class ReviewStatus {
  const ReviewStatus({
    required this.status,
    this.reviewResult = '',
    this.reviewComment,
  });

  final String status;
  final String reviewResult;

  /// 审核意见；无意见时为 null。
  final String? reviewComment;

  bool get isApproved => reviewResult == 'approved';
  bool get isRejected => reviewResult == 'rejected';
  bool get isPending => reviewResult == 'pending';

  /// 作品状态枚举的中文标签；未知取值原样返回，避免后端新增枚举时前端丢信息。
  String get statusLabel {
    switch (status) {
      case 'draft':
        return '草稿';
      case 'reviewing':
        return '审核中';
      case 'approved':
        return '已通过';
      case 'rejected':
        return '已驳回';
      case 'revision_required':
        return '需修改';
      case 'published':
        return '已发布';
      case 'offline':
        return '已下架';
      default:
        return status;
    }
  }

  /// 审核结论的中文标签；未知取值原样返回。
  String get reviewResultLabel {
    switch (reviewResult) {
      case 'approved':
        return '通过';
      case 'rejected':
        return '驳回';
      case 'pending':
        return '待审核';
      default:
        return reviewResult;
    }
  }

  factory ReviewStatus.fromJson(Map<String, dynamic> json) => ReviewStatus(
        status: _text(json['status']),
        reviewResult: _text(json['reviewResult']),
        reviewComment: _textOrNull(json['reviewComment']),
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

/// 作者视角章节条目（接口文档无章节 CRUD 规格，按模块约定补齐）。
///
/// 与书城目录的 ChapterSummary 区别：作者视角不过滤 status（隐藏章节也在列，
/// 便于恢复），故带 status。isFree/status 为 tinyint，契约以字符串 "0"/"1" 下发。
class AuthorChapterItem {
  const AuthorChapterItem({
    required this.chapterId,
    this.chapterNo = 0,
    this.chapterTitle = '',
    this.wordCount = 0,
    this.isFree = false,
    this.status = '0',
  });

  final int chapterId;
  final int chapterNo;
  final String chapterTitle;
  final int wordCount;
  final bool isFree;

  /// 章节状态："0"=正常（目录可见），"1"=隐藏。
  final String status;

  bool get isHidden => status == '1';

  factory AuthorChapterItem.fromJson(Map<String, dynamic> json) => AuthorChapterItem(
        chapterId: _int(json['chapterId']),
        chapterNo: _int(json['chapterNo']),
        chapterTitle: _text(json['chapterTitle']),
        wordCount: _int(json['wordCount']),
        isFree: _flag(json['isFree']),
        status: _text(json['status']).isEmpty ? '0' : _text(json['status']),
      );
}