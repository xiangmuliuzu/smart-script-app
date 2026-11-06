/// B 模块书城页面模型。
///
/// 字段与后端一一对应，不自行拼装：
///   - [BookItem]     ← AppWorkDto（sys_work）
///   - [BannerItem]   ← sys_banner
///   - [TagItem]      ← sys_tag
///   - [RankingItem]  ← AppRankingItem（sys_work 指标列）
///
/// 标签墙体系下作品只按标签归属，不再有分类模型；频道仍由 sys_category 顶层记录提供。
///
/// tinyint 列在若依风格下以字符串 "0"/"1" 下发，这里统一转成 bool，
/// 页面不再接触原始取值。
library;

import '../../../core/config/app_config.dart';

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

/// 标签数组解析：非数组或元素非对象时按空集合处理，页面无需判空。
List<TagItem> _tags(dynamic value) {
  if (value is! List) return const <TagItem>[];
  return value
      .whereType<Map>()
      .map((e) => TagItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

/// 分类页导航各级数组解析：非数组或元素非对象时按空集合处理。
List<T> _navList<T>(dynamic value, T Function(Map<String, dynamic>) parser) {
  if (value is! List) return <T>[];
  return value
      .whereType<Map>()
      .map((e) => parser(Map<String, dynamic>.from(e)))
      .toList();
}

/// 书城作品（列表与详情共用）。
class BookItem {
  const BookItem({
    required this.workId,
    this.title = '',
    this.cover = '',
    this.authorName = '',
    this.tags = const <TagItem>[],
    this.workType = '',
    this.uploadType = '',
    this.lengthType = '',
    this.summary = '',
    this.price = 0,
    this.tradeEnabled = false,
    this.wordCount = 0,
    this.episodeCount = 0,
    this.duration = 0,
    this.isFree = false,
    this.previewEnabled = false,
    this.previewEpisodes = 0,
    this.freeChapterCount = 0,
    this.qualityLevel = '',
    this.viewCount = 0,
    this.favoriteCount = 0,
    this.saleCount = 0,
    this.rating = 0,
    this.createTime,
    this.lastReadChapterId,
    this.lastReadChapterNo,
    this.lastReadAt,
  });

  final int workId;
  final String title;
  final String cover;
  final String authorName;

  /// 作品标签（sys_work_tag 关联 sys_tag，仅启用标签）。
  final List<TagItem> tags;
  final String workType;
  final String uploadType;
  final String lengthType;
  final String summary;
  final double price;
  final bool tradeEnabled;
  final int wordCount;
  final int episodeCount;
  final int duration;
  final bool isFree;
  final bool previewEnabled;
  final int previewEpisodes;

  /// 可试读（作者逐章标记的免费）章节数，后端派生字段。
  /// 平台试读范围（[previewEnabled]/[previewEpisodes]）当前无写入方，
  /// 故作品级「试读」展示需与本值合并判定。
  final int freeChapterCount;
  final String qualityLevel;
  final int viewCount;
  final int favoriteCount;
  final int saleCount;
  final double rating;
  final String? createTime;

  /// 最近阅读章节ID（书架列表专属，接口 2.7.12；未读或非书架场景为 null）。
  final int? lastReadChapterId;

  /// 最近阅读章节序号（书架列表专属；章节被删时为 null）。
  final int? lastReadChapterNo;

  /// 最近阅读时间（书架列表专属，"yyyy-MM-dd HH:mm:ss"）。
  final String? lastReadAt;

  /// 价格展示文案：免费作品不展示金额。
  String get priceLabel => isFree ? '免费' : '¥${price.toStringAsFixed(2)}';

  /// 阅读进度文案；未产生进度（无 lastReadChapterId）时为 null，页面据此隐藏该行。
  String? get readingProgressLabel {
    if (lastReadChapterId == null) return null;
    final where = lastReadChapterNo == null ? '上次阅读' : '读到第 $lastReadChapterNo 章';
    final when = lastReadAt;
    return (when == null || when.isEmpty) ? where : '$where · $when';
  }

  factory BookItem.fromJson(Map<String, dynamic> json) => BookItem(
        workId: _int(json['workId']),
        title: _text(json['title']),
        cover: AppConfig.resolveAssetUrl(_text(json['cover'])),
        authorName: _text(json['authorName']),
        tags: _tags(json['tags']),
        workType: _text(json['workType']),
        uploadType: _text(json['uploadType']),
        lengthType: _text(json['lengthType']),
        summary: _text(json['summary']),
        price: _decimal(json['price']),
        tradeEnabled: _flag(json['tradeEnabled']),
        wordCount: _int(json['wordCount']),
        episodeCount: _int(json['episodeCount']),
        duration: _int(json['duration']),
        isFree: _flag(json['isFree']),
        previewEnabled: _flag(json['previewEnabled']),
        previewEpisodes: _int(json['previewEpisodes']),
        freeChapterCount: _int(json['freeChapterCount']),
        qualityLevel: _text(json['qualityLevel']),
        viewCount: _int(json['viewCount']),
        favoriteCount: _int(json['favoriteCount']),
        saleCount: _int(json['saleCount']),
        rating: _decimal(json['rating']),
        createTime: json['createTime'] as String?,
        lastReadChapterId: _intOrNull(json['lastReadChapterId']),
        lastReadChapterNo: _intOrNull(json['lastReadChapterNo']),
        lastReadAt: json['lastReadAt'] as String?,
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
        imageUrl: AppConfig.resolveAssetUrl(_text(json['imageUrl'])),
        linkType: _text(json['linkType']),
        linkId: _intOrNull(json['linkId']),
        linkUrl: _text(json['linkUrl']),
        position: _text(json['position']),
        sortOrder: _int(json['sortOrder']),
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
    this.groupName,
    this.channelId,
  });

  final int tagId;
  final String tagName;
  final String tagType;
  final int useCount;
  final int sort;

  /// 所属分组名（分类页导航下发；其它接口可能为空）。
  final String? groupName;

  /// 所属频道ID（分类页导航下发；其它接口可能为空）。
  final int? channelId;

  factory TagItem.fromJson(Map<String, dynamic> json) => TagItem(
        tagId: _int(json['tagId']),
        tagName: _text(json['tagName']),
        tagType: _text(json['tagType']),
        useCount: _int(json['useCount']),
        sort: _int(json['sort']),
        groupName: json['groupName']?.toString(),
        channelId: _intOrNull(json['channelId']),
      );
}

/// 分类页导航（接口 `/content/categories/nav` 的 data）。
///
/// 频道列表 + 四维度（热门标签 / 主题 / 角色 / 情节，顺序由后端固定）。
class CategoryNav {
  const CategoryNav({
    this.channelId,
    this.channels = const <NavChannel>[],
    this.dimensions = const <NavDimension>[],
  });

  /// 当前频道ID（入参为空时后端回落第一个频道）。
  final int? channelId;
  final List<NavChannel> channels;
  final List<NavDimension> dimensions;

  factory CategoryNav.fromJson(Map<String, dynamic> json) => CategoryNav(
        channelId: (json['channelId'] as num?)?.toInt(),
        channels: _navList(json['channels'], NavChannel.fromJson),
        dimensions: _navList(json['dimensions'], NavDimension.fromJson),
      );
}

/// 频道（男生 / 女生等）。
class NavChannel {
  const NavChannel({required this.channelId, this.channelName = ''});

  final int channelId;
  final String channelName;

  factory NavChannel.fromJson(Map<String, dynamic> json) => NavChannel(
        channelId: _int(json['channelId']),
        channelName: _text(json['channelName']),
      );
}

/// 维度（hot 热门标签 / theme 主题 / role 角色 / plot 情节）。
class NavDimension {
  const NavDimension({
    required this.key,
    this.name = '',
    this.groups = const <NavGroup>[],
  });

  final String key;
  final String name;
  final List<NavGroup> groups;

  factory NavDimension.fromJson(Map<String, dynamic> json) => NavDimension(
        key: _text(json['key']),
        name: _text(json['name']),
        groups: _navList(json['groups'], NavGroup.fromJson),
      );
}

/// 分组（同一维度下按题材 / 身份等划分的小块）。
class NavGroup {
  const NavGroup({this.groupName = '', this.items = const <NavItem>[]});

  final String groupName;
  final List<NavItem> items;

  factory NavGroup.fromJson(Map<String, dynamic> json) => NavGroup(
        groupName: _text(json['groupName']),
        items: _navList(json['items'], NavItem.fromJson),
      );
}

/// 分组内的筛选项：标签墙体系下 itemType 恒为 tag（标签）。
class NavItem {
  const NavItem({
    required this.itemType,
    required this.itemId,
    this.itemName = '',
    this.workCount = 0,
  });

  final String itemType;
  final int itemId;
  final String itemName;
  final int workCount;

  factory NavItem.fromJson(Map<String, dynamic> json) => NavItem(
        itemType: _text(json['itemType']),
        itemId: _int(json['itemId']),
        itemName: _text(json['itemName']),
        workCount: _int(json['workCount']),
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
    this.score = 0,
    this.viewCount = 0,
    this.favoriteCount = 0,
    this.saleCount = 0,
    this.rating = 0,
    this.wordCount = 0,
    this.episodeCount = 0,
    this.price = 0,
    this.isFree = false,
    this.shelfTime = '',
  });

  final int rankNo;
  final int workId;
  final String title;
  final String cover;
  final String authorName;

  /// 榜单分数：等于当前榜单类型对应的主指标值（累计浏览量 / 累计收藏量 / 平均评分）。
  final double score;
  final int viewCount;
  final int favoriteCount;
  final int saleCount;
  final double rating;
  final int wordCount;
  final int episodeCount;
  final double price;
  final bool isFree;

  /// 上架时间（新书榜用）
  final String shelfTime;

  String get priceLabel => isFree ? '免费' : '¥${price.toStringAsFixed(2)}';

  factory RankingItem.fromJson(Map<String, dynamic> json) => RankingItem(
        rankNo: _int(json['rankNo']),
        workId: _int(json['workId']),
        title: _text(json['title']),
        cover: AppConfig.resolveAssetUrl(_text(json['cover'])),
        authorName: _text(json['authorName']),
        score: _decimal(json['score']),
        viewCount: _int(json['viewCount']),
        favoriteCount: _int(json['favoriteCount']),
        saleCount: _int(json['saleCount']),
        rating: _decimal(json['rating']),
        wordCount: _int(json['wordCount']),
        episodeCount: _int(json['episodeCount']),
        price: _decimal(json['price']),
        isFree: _flag(json['isFree']),
        shelfTime: _text(json['shelfTime']),
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

/// 榜单类型（App 展示四榜；交易热度榜因剧本通常只交易一次已下线，后端仍兼容 sale 参数）。
///
/// 方案 A「时间窗口 + 分级」，type 与主指标强绑定：
/// view 热门榜=累计浏览量 / favorite 收藏榜=累计收藏量 /
/// rating 评分榜=平均评分 / new 新书榜=近 30 天上架，按上架时间倒序（shelfTime）。
class RankingType {
  const RankingType(this.code, this.label);

  final String code;
  final String label;

  static const List<RankingType> all = <RankingType>[
    RankingType('view', '热门榜'),
    RankingType('favorite', '收藏榜'),
    RankingType('rating', '评分榜'),
    RankingType('new', '新书榜'),
  ];

  static RankingType of(String? code) =>
      all.firstWhere((type) => type.code == code, orElse: () => all.first);
}

/// 榜单响应载荷（接口 2.7.7 的 data：{list, updatedAt}）。
class RankingPayload {
  const RankingPayload({this.list = const <RankingItem>[], this.updatedAt = ''});

  final List<RankingItem> list;

  /// 榜单更新时间（后端实时取数时刻，yyyy-MM-dd HH:mm:ss）；缺失时为空串。
  final String updatedAt;

  factory RankingPayload.fromJson(Map<String, dynamic>? data) => RankingPayload(
        list: _rankingItems(data),
        updatedAt: _text(data?['updatedAt']),
      );
}

/// 榜单条目解析：非数组或元素非对象时按空集合处理。
List<RankingItem> _rankingItems(Map<String, dynamic>? data) {
  final raw = data?['list'];
  if (raw is! List) return const <RankingItem>[];
  return raw
      .whereType<Map>()
      .map((e) => RankingItem.fromJson(Map<String, dynamic>.from(e)))
      .toList();
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

  /// 当前身份是否可读本章：由服务端判定
  /// （试读范围内 或 作者标记的免费章节 或 已获版权授权），客户端不自行推算。
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
    this.publishedTotal = 0,
    this.chapters = const <ChapterSummary>[],
  });

  final int workId;
  final bool previewEnabled;
  final int previewEpisodes;

  /// 访问范围：preview（仅试读）/ full（已获授权全文），由服务端按当前身份下发。
  final String accessScope;

  /// 是否已获版权授权；等价于 [accessScope] == 'full'。
  final bool unlocked;

  /// 当前身份可见的章节数（未获授权时仅试读章节）。
  final int total;

  /// 已发布章节总数（含未开放试读、当前身份不可见的章节）。
  final int publishedTotal;

  /// 展示「共 N 章」时使用的章节总数。
  int get publishedCount => publishedTotal > 0 ? publishedTotal : total;

  final List<ChapterSummary> chapters;

  factory ChapterListPayload.fromJson(Map<String, dynamic> json) {
    final raw = json['list'];
    final int visibleTotal = _int(json['total']);
    final int publishedTotal = _int(json['publishedTotal']);
    return ChapterListPayload(
      workId: _int(json['workId']),
      previewEnabled: _flag(json['previewEnabled']),
      previewEpisodes: _int(json['previewEpisodes']),
      accessScope: _text(json['accessScope']).isEmpty
          ? 'preview'
          : _text(json['accessScope']),
      unlocked: _flag(json['unlocked']),
      total: visibleTotal,
      publishedTotal: publishedTotal > 0 ? publishedTotal : visibleTotal,
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
        fileUrl: AppConfig.resolveAssetUrl(_text(json['fileUrl'])),
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
    this.phone = '',
    this.email = '',
    this.wechat = '',
  });

  final int workId;

  /// 作者是否登记了联系方式。
  final bool hasContact;

  /// 展示范围：public / certified_partner / platform_forward / hidden。
  final String displayScope;

  /// 手机号（明文，开发阶段直接下发）
  final String phone;

  /// 邮箱（明文，开发阶段直接下发）
  final String email;

  /// 微信号（明文，开发阶段直接下发）
  final String wechat;

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
        phone: _text(json['phone']),
        email: _text(json['email']),
        wechat: _text(json['wechat']),
      );
}

/// 搜索历史条目（AppSearchHistoryItem，接口 2.7.4）。
///
/// 契约只声明 data.list 为数组、未定义元素字段，字段按 sys_search_history
/// 实际业务列对齐后端下发口径：id / keyword / searchCount / lastSearchAt。
class SearchHistoryItem {
  const SearchHistoryItem({
    required this.id,
    this.keyword = '',
    this.searchCount = 0,
    this.lastSearchAt,
  });

  /// 历史记录ID（删除单条时回传）。
  final int id;
  final String keyword;

  /// 累计搜索次数。
  final int searchCount;

  /// 最近一次搜索时间（"yyyy-MM-dd HH:mm:ss"）。
  final String? lastSearchAt;

  factory SearchHistoryItem.fromJson(Map<String, dynamic> json) => SearchHistoryItem(
        id: _int(json['id']),
        keyword: _text(json['keyword']),
        searchCount: _int(json['searchCount']),
        lastSearchAt: json['lastSearchAt'] as String?,
      );
}

/// 收藏状态（接口 2.7.10 的收藏态查询，data 只有 `favorited`）。
class FavoriteState {
  const FavoriteState({required this.favorited});

  final bool favorited;

  factory FavoriteState.fromJson(Map<String, dynamic> json) =>
      FavoriteState(favorited: _flag(json['favorited']));
}

/// 作品读者评分（读者评分通道，data 含 `rating` / `ratingCount` / `myScore`）。
class WorkRating {
  const WorkRating({
    required this.rating,
    required this.ratingCount,
    this.myScore,
  });

  /// 作品平均分（保留一位小数；无人评分时为 0）。
  final double rating;

  /// 评分数（一人一评，等于评分人数）。
  final int ratingCount;

  /// 我的评分（1~5）；null = 当前身份未评分（游客恒为 null）。
  final int? myScore;

  factory WorkRating.fromJson(Map<String, dynamic> json) => WorkRating(
        rating: _decimal(json['rating']),
        ratingCount: _int(json['ratingCount']),
        myScore: json['myScore'] == null ? null : _int(json['myScore']),
      );
}

/// 书架状态（接口 2.7.12 的书架态查询，data 只有 `onShelf`）。
class ShelfState {
  const ShelfState({required this.onShelf});

  final bool onShelf;

  factory ShelfState.fromJson(Map<String, dynamic> json) =>
      ShelfState(onShelf: _flag(json['onShelf']));
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