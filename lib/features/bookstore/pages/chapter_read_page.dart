import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/providers/auth_providers.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/bookstore_models.dart';
import '../data/content_providers.dart';

/// 章节正文（B 模块，接口 2.7.4 章节正文）。
///
/// 公开页，游客可试读。超出试读范围时后端返回 code=403 且 data 不含正文，
/// 由 [ApiClient] 抛 [ApiException]，本页落到「试读结束」提示而非通用错误态。
///
/// 正文载入成功后按当前登录身份上报阅读进度（PUT /content/shelf/{workId}/progress）：
/// 游客不报（避免必然 401），作品不在书架时后端返回 404，均视为正常，不影响阅读。
class ChapterReadPage extends ConsumerStatefulWidget {
  const ChapterReadPage({super.key, required this.chapterId, this.title});

  final int chapterId;

  /// 章节标题，仅用于加载期间的页面标题展示。
  final String? title;

  @override
  ConsumerState<ChapterReadPage> createState() => _ChapterReadPageState();
}

class _ChapterReadPageState extends ConsumerState<ChapterReadPage> {
  /// 已上报的章节ID：同一章在 build 重建时不重复上报。
  int? _reportedChapterId;

  /// 正文字号档位：A- / A+ 在其中循环，默认 17。
  ///
  /// 仅做「最小字号调节」：state 内 session 持有即可（不接全局主题），
  /// 重进章节/重进 App 回到默认档——本次范围不含持久化与夜间模式。
  static const List<double> _fontSizes = [16, 17, 18, 19, 20];
  int _fontIndex = 1;

  double get _bodyFontSize => _fontSizes[_fontIndex];

  /// 上报阅读进度；失败静默（进度是附加信息，不应打断阅读）。
  void _reportProgress(ChapterDetail detail) {
    if (_reportedChapterId == detail.chapterId) return;
    if (!ref.read(authControllerProvider).isAuthenticated) return;
    _reportedChapterId = detail.chapterId;
    unawaited(_send(detail.workId, detail.chapterId));
  }

  Future<void> _send(int workId, int chapterId) async {
    try {
      await ref.read(contentRepositoryProvider).saveShelfProgress(workId, chapterId);
    } catch (_) {
      // 忽略：未加入书架（404）或网络异常都不影响正文展示。
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(chapterDetailProvider(widget.chapterId));
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(
        title: Text((widget.title == null || widget.title!.isEmpty) ? '正文' : widget.title!),
        // 正文字号调节：AppBar 右侧常驻 A- / A+，在 _fontSizes 间循环。
        // 到边界置灰，最小/最大档不可再压/放。
        actions: [
          TextButton(
            onPressed: _fontIndex > 0 ? () => setState(() => _fontIndex--) : null,
            child: const Text('A-', style: TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: _fontIndex < _fontSizes.length - 1
                ? () => setState(() => _fontIndex++)
                : null,
            child: const Text('A+', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (error, _) {
          // 403 = 试读结束：属于正常业务边界，不作为错误展示。
          if (error is ApiException && error.code == 403) {
            return _LockedView(message: error.message, workId: _workIdFromError(error));
          }
          return ErrorView(
            message: error is ApiException ? error.message : '加载失败，请稍后重试',
            onRetry: () => ref.invalidate(chapterDetailProvider(widget.chapterId)),
          );
        },
        data: (detail) {
          final content = detail.content;
          if (!detail.readable || content == null || content.isEmpty) {
            return _LockedView(
              message: '试读结束，请合作或授权后查看完整剧本',
              workId: detail.workId,
            );
          }
          WidgetsBinding.instance.addPostFrameCallback((_) => _reportProgress(detail));
          return _Reader(detail: detail, content: content, bodyFontSize: _bodyFontSize);
        },
      ),
    );
  }
}

/// 403 试读边界（code=403）的 data 不含正文，但可能带章节归属 workId；
/// 能取到就用来跳章节目录，取不到由 [_LockedView] 回退书城首页兜底。
int? _workIdFromError(Object error) {
  if (error is! ApiException || error.code != 403) return null;
  final data = error.data;
  if (data is! Map) return null;
  final raw = data['workId'];
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw);
  return null;
}

/// 正文排版：按换行切段，段间留白，长文行高放宽便于阅读。
class _Reader extends StatelessWidget {
  const _Reader({required this.detail, required this.content, required this.bodyFontSize});

  final ChapterDetail detail;
  final String content;

  /// 正文字号，由阅读页 AppBar 的 A- / A+ 调节传入；章题与字数行保持固定字号。
  final double bodyFontSize;

  @override
  Widget build(BuildContext context) {
    final paragraphs = content.split('\n');
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      children: [
        Text(
          detail.chapterTitle.isEmpty ? '第 ${detail.chapterNo} 章' : detail.chapterTitle,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.text1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '共 ${detail.wordCount} 字',
          style: const TextStyle(fontSize: 12, color: AppColors.text3),
        ),
        const SizedBox(height: 20),
        for (final line in paragraphs)
          if (line.trim().isEmpty)
            const SizedBox(height: 10)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                line,
                style: TextStyle(fontSize: bodyFontSize, height: 1.9, color: AppColors.text2),
              ),
            ),
        const SizedBox(height: 16),
        const Text(
          '— 本章结束 —',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: AppColors.text3),
        ),
        _ChapterNav(workId: detail.workId, currentChapterId: detail.chapterId),
      ],
    );
  }
}

/// 章末「上一章 / 下一章」导航。
///
/// 进入正文后才拉取本作品章节目录，按当前 chapterId 在目录中定位相邻章：
/// - 目录加载中 / 失败 / 未定位到当前章：两个按钮都禁用（不阻塞正文阅读）；
/// - 首章「上一章」、末章「下一章」置灰；
/// - 相邻章不可读（未授权）时同样置灰，与目录页点击锁章节的行为一致；
/// - 跳转用 pushReplacement：线性阅读不往页面栈累加阅读页，返回键直接回到目录，
///   深链直达场景栈深也恒为 1。
class _ChapterNav extends ConsumerWidget {
  const _ChapterNav({required this.workId, required this.currentChapterId});

  final int workId;
  final int currentChapterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(chapterListProvider(workId));
    final payload = listAsync.maybeWhen(data: (p) => p, orElse: () => null);

    ChapterSummary? prev;
    ChapterSummary? next;
    if (payload != null) {
      final index =
          payload.chapters.indexWhere((chapter) => chapter.chapterId == currentChapterId);
      if (index >= 0) {
        if (index > 0) prev = payload.chapters[index - 1];
        if (index < payload.chapters.length - 1) {
          next = payload.chapters[index + 1];
        }
      }
    }

    final bool prevEnabled = prev != null && prev.readable;
    final bool nextEnabled = next != null && next.readable;

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: prevEnabled ? () => _jump(context, prev!) : null,
              child: const Text('上一章'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton(
              onPressed: nextEnabled ? () => _jump(context, next!) : null,
              child: const Text('下一章'),
            ),
          ),
        ],
      ),
    );
  }

  void _jump(BuildContext context, ChapterSummary chapter) {
    context.pushReplacement(
      RoutePath.chapterReadUrl(chapter.chapterId, title: chapter.chapterTitle),
    );
  }
}

/// 试读结束提示：说明边界并提供返回入口。
class _LockedView extends StatelessWidget {
  const _LockedView({required this.message, this.workId});

  final String message;

  /// 用于跳章节目录的作品ID；403 错误分支可能拿不到（null），按钮回退书城首页。
  final int? workId;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 56, color: AppColors.text3),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppColors.text2, height: 1.6),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                  return;
                }
                // 深链/分享直达、页面栈无可 pop：直接跳到章节目录，不再是死按钮。
                final int? id = workId;
                if (id != null && id > 0) {
                  context.pushReplacement(RoutePath.chapterListUrl(id));
                } else {
                  // 403 分支正文未成功解析、拿不到 workId，回退书城首页兜底，避免困死。
                  context.go(RoutePath.bookstore);
                }
              },
              child: const Text('返回目录'),
            ),
          ],
        ),
      ),
    );
  }
}