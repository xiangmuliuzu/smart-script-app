/// 「我的作品」写作链路页面模型（A 套接口 /api/v1/users/me/works）。
///
/// 字段与后端一一对应，不自行拼装：
///   - [AuthorWorkItem]    ← GET /users/me/works 列表元素
///   - [AuthorWorkDetail]  ← GET /users/me/works/{workId}（work + chapters + latestReview）
///   - [AuthorChapterItem] ← 章节元素（含正文 content）
///   - [ReviewRecordItem]  ← GET /users/me/works/{workId}/review-records 元素
///
/// 作品状态口径（A 套由最新审核记录派生，服务端下发）：
///   draft（无记录）/ reviewing（pending、ai_reviewing）/ revision（待修改）
///   rejected（已驳回）/ published（approved，已发布）。
/// 编辑闸门：仅 reviewing（审核中）锁定，其余状态均可编辑；已发布作品改动后需重新提交审核。
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

double? _doubleOrNull(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String && value.isNotEmpty) return double.tryParse(value);
  return null;
}

/// 作品状态中文标签（A 套口径）。
///
/// 未知取值原样返回，避免后端新增枚举时前端丢信息。
String workStatusLabel(String status) {
  switch (status) {
    case 'draft':
      return '草稿';
    case 'reviewing':
      return '审核中';
    case 'revision':
      return '待修改';
    case 'rejected':
      return '已驳回';
    case 'published':
      return '已发布';
    default:
      return status;
  }
}

/// 审核记录状态中文标签；未知取值原样返回。
String reviewStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return '待审核';
    case 'ai_reviewing':
      return 'AI 审核中';
    case 'revision':
      return '待修改';
    case 'rejected':
      return '已驳回';
    case 'approved':
      return '已通过';
    default:
      return status;
  }
}

/// 我的作品列表条目（A 套 GET /users/me/works）。
class AuthorWorkItem {
  const AuthorWorkItem({
    required this.workId,
    this.title = '',
    this.cover,
    this.summary,
    this.genreId,
    this.genreName,
    this.workType,
    this.wordCount = 0,
    this.price,
    this.status = 'draft',
    this.createTime,
    this.updateTime,
  });

  final int workId;
  final String title;

  /// 封面地址：列表接口不下发（恒为 null），详情接口下发。
  final String? cover;
  final String? summary;
  final int? genreId;
  final String? genreName;
  final String? workType;
  final int wordCount;

  /// 定价（后端下发，A 套列表/详情均携带）。
  final double? price;

  /// 审核派生状态（见库文档头注释）。
  final String status;
  final String? createTime;
  final String? updateTime;

  /// 状态中文标签。
  String get statusLabel => workStatusLabel(status);

  /// 仅「审核中」锁定，其余状态（含已发布）均可编辑；
  /// 已发布作品改动后需重新提交审核（与后端 requireEditable 一致）。
  bool get editable => status != 'reviewing';

  factory AuthorWorkItem.fromJson(Map<String, dynamic> json) => AuthorWorkItem(
        workId: _int(json['workId']),
        title: _text(json['title']),
        cover: _textOrNull(json['cover']),
        summary: _textOrNull(json['summary']),
        genreId: _intOrNull(json['genreId']),
        genreName: _textOrNull(json['genreName']),
        workType: _textOrNull(json['workType']),
        wordCount: _int(json['wordCount']),
        price: _doubleOrNull(json['price']),
        status: _text(json['status']).isEmpty ? 'draft' : _text(json['status']),
        createTime: _textOrNull(json['createTime']),
        updateTime: _textOrNull(json['updateTime']),
      );
}

/// 作者视角章节条目（A 套章节接口，含正文全文）。
///
/// isFree/status 为 tinyint，契约以字符串 "0"/"1" 下发（若依字典风格）。
class AuthorChapterItem {
  const AuthorChapterItem({
    required this.chapterId,
    this.chapterNo = 0,
    this.chapterTitle = '',
    this.content = '',
    this.wordCount = 0,
    this.isFree = false,
    this.status = '0',
  });

  final int chapterId;
  final int chapterNo;
  final String chapterTitle;
  final String content;
  final int wordCount;
  final bool isFree;

  /// 章节状态："0"=正常（目录可见），"1"=隐藏。
  final String status;

  bool get isHidden => status == '1';

  factory AuthorChapterItem.fromJson(Map<String, dynamic> json) => AuthorChapterItem(
        chapterId: _int(json['chapterId']),
        chapterNo: _int(json['chapterNo']),
        chapterTitle: _text(json['chapterTitle']),
        content: _text(json['content']),
        wordCount: _int(json['wordCount']),
        isFree: _flag(json['isFree']),
        status: _text(json['status']).isEmpty ? '0' : _text(json['status']),
      );
}

/// 审核记录条目（A 套 GET /users/me/works/{workId}/review-records）。
class ReviewRecordItem {
  const ReviewRecordItem({
    required this.reviewId,
    this.reviewNo = '',
    this.status = '',
    this.reviewResult,
    this.reviewOpinion,
    this.createdAt,
  });

  final int reviewId;
  final String reviewNo;

  /// 审核状态（pending/ai_reviewing/revision/rejected/approved）。
  final String status;

  /// 审核结果（approved/rejected/revision 等），未出结论时为 null。
  final String? reviewResult;

  /// 审核意见，可为空。
  final String? reviewOpinion;

  /// 提交时间（"yyyy-MM-dd HH:mm:ss"）。
  final String? createdAt;

  String get statusLabel => reviewStatusLabel(status);

  factory ReviewRecordItem.fromJson(Map<String, dynamic> json) => ReviewRecordItem(
        reviewId: _int(json['reviewId']),
        reviewNo: _text(json['reviewNo']),
        status: _text(json['status']),
        reviewResult: _textOrNull(json['reviewResult']),
        reviewOpinion: _textOrNull(json['reviewOpinion']),
        createdAt: _textOrNull(json['createdAt']),
      );
}

/// 作品工作台详情（A 套 GET /users/me/works/{workId}，一次拿全）。
class AuthorWorkDetail {
  const AuthorWorkDetail({
    required this.work,
    this.chapters = const [],
    this.latestReview,
  });

  final AuthorWorkItem work;
  final List<AuthorChapterItem> chapters;

  /// 最近一条审核记录；从未提交过审核时为 null。
  final ReviewRecordItem? latestReview;

  /// 章节总字数（各章 wordCount 之和）。
  int get totalWordCount =>
      chapters.fold(0, (sum, chapter) => sum + chapter.wordCount);

  factory AuthorWorkDetail.fromJson(Map<String, dynamic> json) {
    final rawWork = json['work'];
    final rawChapters = json['chapters'];
    final rawLatest = json['latestReview'];
    return AuthorWorkDetail(
      work: rawWork is Map
          ? AuthorWorkItem.fromJson(Map<String, dynamic>.from(rawWork))
          : const AuthorWorkItem(workId: 0),
      chapters: rawChapters is List
          ? rawChapters
              .whereType<Map>()
              .map((e) => AuthorChapterItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      latestReview: rawLatest is Map
          ? ReviewRecordItem.fromJson(Map<String, dynamic>.from(rawLatest))
          : null,
    );
  }
}