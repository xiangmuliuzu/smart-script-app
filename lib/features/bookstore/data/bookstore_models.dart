/// B 模块书城页面模型。
///
/// 字段与后端一一对应，不自行拼装：
///   - [BookItem]     ← AppWorkDto（sys_work）
///   - [BannerItem]   ← sys_banner
///   - [CategoryItem] ← sys_category
///   - [TagItem]      ← sys_tag
///   - [RankingItem]  ← AppRankingItem（sys_work 指标列）
///
/// tinyint 列在若依风格下以字符串 "0"/"1" 下发，这里统一转成 bool，
/// 页面不再接触原始取值。
library;

bool _flag(dynamic value) => value == '1' || value == 1 || value == true;

String _text(dynamic value) => value == null ? '' : value.toString();

int _int(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _intOrNull(dynamic value) {
  if (value is num) return value.toInt();
  if (value is String && value.isNotEmpty) return int.tryParse(value);
  return null;
}

double _decimal(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

/// 书城作品（列表与详情共用；详情才带 coreSetting/characterSetting）。
class BookItem {
  const BookItem({
    required this.workId,
    this.title = '',
    this.cover = '',
    this.authorName = '',
    this.genreName = '',
    this.workType = '',
    this.uploadType = '',
    this.lengthType = '',
    this.summary = '',
    this.coreSetting = '',
    this.characterSetting = '',
    this.price = 0,
    this.tradeEnabled = false,
    this.wordCount = 0,
    this.episodeCount = 0,
    this.duration = 0,
    this.isFree = false,
    this.previewEnabled = false,
    this.previewEpisodes = 0,
    this.qualityLevel = '',
    this.viewCount = 0,
    this.favoriteCount = 0,
    this.saleCount = 0,
    this.rating = 0,
    this.createTime,
  });

  final int workId;
  final String title;
  final String cover;
  final String authorName;
  final String genreName;
  final String workType;
  final String uploadType;
  final String lengthType;
  final String summary;
  final String coreSetting;
  final String characterSetting;
  final double price;
  final bool tradeEnabled;
  final int wordCount;
  final int episodeCount;
  final int duration;
  final bool isFree;
  final bool previewEnabled;
  final int previewEpisodes;
  final String qualityLevel;
  final int viewCount;
  final int favoriteCount;
  final int saleCount;
  final double rating;
  final String? createTime;

  /// 价格展示文案：免费作品不展示金额。
  String get priceLabel => isFree ? '免费' : '¥${price.toStringAsFixed(2)}';

  factory BookItem.fromJson(Map<String, dynamic> json) => BookItem(
        workId: _int(json['workId']),
        title: _text(json['title']),
        cover: _text(json['cover']),
        authorName: _text(json['authorName']),
        genreName: _text(json['genreName']),
        workType: _text(json['workType']),
        uploadType: _text(json['uploadType']),
        lengthType: _text(json['lengthType']),
        summary: _text(json['summary']),
        coreSetting: _text(json['coreSetting']),
        characterSetting: _text(json['characterSetting']),
        price: _decimal(json['price']),
        tradeEnabled: _flag(json['tradeEnabled']),
        wordCount: _int(json['wordCount']),
        episodeCount: _int(json['episodeCount']),
        duration: _int(json['duration']),
        isFree: _flag(json['isFree']),
        previewEnabled: _flag(json['previewEnabled']),
        previewEpisodes: _int(json['previewEpisodes']),
        qualityLevel: _text(json['qualityLevel']),
        viewCount: _int(json['viewCount']),
        favoriteCount: _int(json['favoriteCount']),
        saleCount: _int(json['saleCount']),
        rating: _decimal(json['rating']),
        createTime: json['createTime'] as String?,
      );
}

/// 首页轮播图（sys_banner）。
class BannerItem {
  const BannerItem({
    required this.bannerId,
    this.title = '',
    this.imageUrl = '',
    this.linkType = '',
    this.linkId,
    this.linkUrl = '',
    this.position = '',
    this.sortOrder = 0,
  });

  final int bannerId;
  final String title;
  final String imageUrl;
  final String linkType;
  final int? linkId;
  final String linkUrl;
  final String position;
  final int sortOrder;

  factory BannerItem.fromJson(Map<String, dynamic> json) => BannerItem(
        bannerId: _int(json['bannerId']),
        title: _text(json['title']),
        imageUrl: _text(json['imageUrl']),
        linkType: _text(json['linkType']),
        linkId: _intOrNull(json['linkId']),
        linkUrl: _text(json['linkUrl']),
        position: _text(json['position']),
        sortOrder: _int(json['sortOrder']),
      );
}

/// 剧本分类（sys_category）。
class CategoryItem {
  const CategoryItem({
    required this.categoryId,
    this.categoryName = '',
    this.categoryType = '',
    this.parentId,
    this.sort = 0,
  });

  final int categoryId;
  final String categoryName;
  final String categoryType;
  final int? parentId;
  final int sort;

  factory CategoryItem.fromJson(Map<String, dynamic> json) => CategoryItem(
        categoryId: _int(json['categoryId']),
        categoryName: _text(json['categoryName']),
        categoryType: _text(json['categoryType']),
        parentId: _intOrNull(json['parentId']),
        sort: _int(json['sort']),
      );
}

/// 作品标签（sys_tag）。
class TagItem {
  const TagItem({
    required this.tagId,
    this.tagName = '',
    this.tagType = '',
    this.useCount = 0,
    this.sort = 0,
  });

  final int tagId;
  final String tagName;
  final String tagType;
  final int useCount;
  final int sort;

  factory TagItem.fromJson(Map<String, dynamic> json) => TagItem(
        tagId: _int(json['tagId']),
        tagName: _text(json['tagName']),
        tagType: _text(json['tagType']),
        useCount: _int(json['useCount']),
        sort: _int(json['sort']),
      );
}

/// 榜单条目（rankNo 由服务端按排序结果生成）。
class RankingItem {
  const RankingItem({
    required this.rankNo,
    required this.workId,
    this.title = '',
    this.cover = '',
    this.authorName = '',
    this.genreName = '',
    this.score = 0,
    this.viewCount = 0,
    this.favoriteCount = 0,
    this.saleCount = 0,
    this.rating = 0,
    this.wordCount = 0,
    this.episodeCount = 0,
    this.price = 0,
    this.isFree = false,
  });

  final int rankNo;
  final int workId;
  final String title;
  final String cover;
  final String authorName;
  final String genreName;

  /// 榜单分数：等于当前榜单类型对应的指标值。
  final double score;
  final int viewCount;
  final int favoriteCount;
  final int saleCount;
  final double rating;
  final int wordCount;
  final int episodeCount;
  final double price;
  final bool isFree;

  String get priceLabel => isFree ? '免费' : '¥${price.toStringAsFixed(2)}';

  factory RankingItem.fromJson(Map<String, dynamic> json) => RankingItem(
        rankNo: _int(json['rankNo']),
        workId: _int(json['workId']),
        title: _text(json['title']),
        cover: _text(json['cover']),
        authorName: _text(json['authorName']),
        genreName: _text(json['genreName']),
        score: _decimal(json['score']),
        viewCount: _int(json['viewCount']),
        favoriteCount: _int(json['favoriteCount']),
        saleCount: _int(json['saleCount']),
        rating: _decimal(json['rating']),
        wordCount: _int(json['wordCount']),
        episodeCount: _int(json['episodeCount']),
        price: _decimal(json['price']),
        isFree: _flag(json['isFree']),
      );
}

/// 作品列表排序项（值与后端 `normalizeSort` 白名单一致）。
class WorkSortOption {
  const WorkSortOption(this.label, this.value);

  final String label;

  /// 传 null 表示不传 sort，由后端回落 `latest`。
  final String? value;

  static const List<WorkSortOption> all = <WorkSortOption>[
    WorkSortOption('最新', null),
    WorkSortOption('最热', 'view'),
    WorkSortOption('收藏', 'favorite'),
    WorkSortOption('销量', 'sale'),
    WorkSortOption('好评', 'rating'),
    WorkSortOption('价格从低到高', 'price_asc'),
    WorkSortOption('价格从高到低', 'price_desc'),
  ];
}

/// 榜单类型（值与后端 `normalizeRankingType` 白名单一致）。
class RankingType {
  const RankingType(this.code, this.label);

  final String code;
  final String label;

  static const List<RankingType> all = <RankingType>[
    RankingType('view', '人气榜'),
    RankingType('favorite', '收藏榜'),
    RankingType('sale', '销量榜'),
    RankingType('rating', '好评榜'),
  ];

  static RankingType of(String? code) =>
      all.firstWhere((type) => type.code == code, orElse: () => all.first);
}

/// 章节目录条目（AppChapterDto）。目录不下发正文。
class ChapterSummary {
  const ChapterSummary({
    required this.chapterId,
    this.chapterNo = 0,
    this.chapterTitle = '',
    this.wordCount = 0,
    this.isFree = false,
    this.readable = false,
  });

  final int chapterId;
  final int chapterNo;
  final String chapterTitle;
  final int wordCount;
  final bool isFree;

  /// 当前身份是否可读本章：由服务端判定（试读范围内 或 已获版权授权），
  /// 客户端不自行推算。
  final bool readable;

  factory ChapterSummary.fromJson(Map<String, dynamic> json) => ChapterSummary(
        chapterId: _int(json['chapterId']),
        chapterNo: _int(json['chapterNo']),
        chapterTitle: _text(json['chapterTitle']),
        wordCount: _int(json['wordCount']),
        isFree: _flag(json['isFree']),
        readable: _flag(json['readable']),
      );
}

/// 章节正文（AppChapterDetailDto）。[content] 仅可读章节下发。
class ChapterDetail {
  const ChapterDetail({
    required this.chapterId,
    required this.workId,
    this.chapterNo = 0,
    this.chapterTitle = '',
    this.wordCount = 0,
    this.content,
    this.readable = false,
  });

  final int chapterId;
  final int workId;
  final int chapterNo;
  final String chapterTitle;
  final int wordCount;

  /// 不可读时为 null（后端 403 分支的 data 不含 content）。
  final String? content;
  final bool readable;

  factory ChapterDetail.fromJson(Map<String, dynamic> json) => ChapterDetail(
        chapterId: _int(json['chapterId']),
        workId: _int(json['workId']),
        chapterNo: _int(json['chapterNo']),
        chapterTitle: _text(json['chapterTitle']),
        wordCount: _int(json['wordCount']),
        content: json['content'] as String?,
        readable: _flag(json['readable']),
      );
}

/// 作品章节目录 payload（含试读配置与当前身份的访问范围，目录页一次请求即可完成展示）。
class ChapterListPayload {
  const ChapterListPayload({
    required this.workId,
    this.previewEnabled = false,
    this.previewEpisodes = 0,
    this.accessScope = 'preview',
    this.unlocked = false,
    this.total = 0,
    this.chapters = const <ChapterSummary>[],
  });

  final int workId;
  final bool previewEnabled;
  final int previewEpisodes;

  /// 访问范围：preview（仅试读）/ full（已获授权全文），由服务端按当前身份下发。
  final String accessScope;

  /// 是否已获版权授权；等价于 [accessScope] == 'full'。
  final bool unlocked;
  final int total;
  final List<ChapterSummary> chapters;

  factory ChapterListPayload.fromJson(Map<String, dynamic> json) {
    final raw = json['list'];
    return ChapterListPayload(
      workId: _int(json['workId']),
      previewEnabled: _flag(json['previewEnabled']),
      previewEpisodes: _int(json['previewEpisodes']),
      accessScope: _text(json['accessScope']).isEmpty
          ? 'preview'
          : _text(json['accessScope']),
      unlocked: _flag(json['unlocked']),
      total: _int(json['total']),
      chapters: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => ChapterSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const <ChapterSummary>[],
    );
  }
}

/// 试读文件（AppWorkFileDto）。
class PreviewFile {
  const PreviewFile({
    required this.fileId,
    this.fileName = '',
    this.fileUrl = '',
    this.fileType = '',
    this.fileSize = 0,
  });

  final int fileId;
  final String fileName;
  final String fileUrl;
  final String fileType;
  final int fileSize;

  factory PreviewFile.fromJson(Map<String, dynamic> json) => PreviewFile(
        fileId: _int(json['fileId']),
        fileName: _text(json['fileName']),
        fileUrl: _text(json['fileUrl']),
        fileType: _text(json['fileType']),
        fileSize: _int(json['fileSize']),
      );
}

/// 版权合作联系方式（AppContactDto，接口 2.7.9）。
///
/// 后端只下发「是否登记」与「展示范围」，**不含明文联系方式**
/// （作者三列密文在服务端只用于判定是否登记，不解密不输出）。
/// 展示范围取值见接口文档 2.4.14 / 2.5.6。
class WorkContact {
  const WorkContact({
    required this.workId,
    this.hasContact = false,
    this.displayScope = '',
  });

  final int workId;

  /// 作者是否登记了联系方式。
  final bool hasContact;

  /// 展示范围：public / certified_partner / platform_forward / hidden。
  final String displayScope;

  /// 展示范围文案；未知取值回落为范围原值，避免后端新增范围时前端丢失信息。
  String get displayScopeLabel {
    switch (displayScope) {
      case 'public':
        return '公开展示';
      case 'certified_partner':
        return '认证合作方可见';
      case 'platform_forward':
        return '平台转接';
      case 'hidden':
        return '不公开';
      default:
        return displayScope;
    }
  }

  factory WorkContact.fromJson(Map<String, dynamic> json) => WorkContact(
        workId: _int(json['workId']),
        hasContact: _flag(json['hasContact']),
        displayScope: _text(json['displayScope']),
      );
}

/// 作品试读包（AppPreviewDto）：可读章节 + 试读文件。
class PreviewPayload {
  const PreviewPayload({
    required this.workId,
    this.previewEnabled = false,
    this.previewEpisodes = 0,
    this.previewChapters = const <ChapterSummary>[],
    this.previewFiles = const <PreviewFile>[],
  });

  final int workId;
  final bool previewEnabled;
  final int previewEpisodes;
  final List<ChapterSummary> previewChapters;
  final List<PreviewFile> previewFiles;

  factory PreviewPayload.fromJson(Map<String, dynamic> json) {
    final chapters = json['previewChapters'];
    final files = json['previewFiles'];
    return PreviewPayload(
      workId: _int(json['workId']),
      previewEnabled: _flag(json['previewEnabled']),
      previewEpisodes: _int(json['previewEpisodes']),
      previewChapters: chapters is List
          ? chapters
              .whereType<Map>()
              .map((e) => ChapterSummary.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const <ChapterSummary>[],
      previewFiles: files is List
          ? files
              .whereType<Map>()
              .map((e) => PreviewFile.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const <PreviewFile>[],
    );
  }
}