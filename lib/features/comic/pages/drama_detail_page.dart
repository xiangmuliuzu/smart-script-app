import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../data/drama_providers.dart';
import '../widgets/drama_widgets.dart';

/// 外部视频详情（B 模块，接口文档 2.8.15）。
///
/// 公开页，游客可浏览。播放地址为站外链接（external_url），由系统浏览器/外部
/// 播放器打开；「找同款剧本」跳 2.8.16，「举报」为受保护入口（需 App Token）。
class DramaDetailPage extends ConsumerWidget {
  const DramaDetailPage({super.key, required this.dramaId});

  final int dramaId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(dramaDetailProvider(dramaId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(detail.valueOrNull?.title.isNotEmpty == true
            ? detail.valueOrNull!.title
            : '漫剧详情'),
        actions: [
          IconButton(
            tooltip: '举报',
            onPressed: () => AuthGuard.pushProtected(
              context,
              ref,
              target: RoutePath.dramaReportUrl(dramaId),
            ),
            icon: const Icon(Icons.flag_outlined),
          ),
        ],
      ),
      body: detail.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (e, __) => ErrorView(
          message: e is Exception ? e.toString() : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(dramaDetailProvider(dramaId)),
        ),
        data: (item) => ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.r),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const DramaCoverPlaceholder(width: 120, height: 80, iconSize: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title.isEmpty ? '未命名视频' : item.title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: AppColors.text1,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (item.sourceType.isNotEmpty)
                                  DramaTag(text: item.sourceType, color: AppColors.primary),
                                if (item.platform.isNotEmpty)
                                  DramaTag(text: item.platform, color: AppColors.text2),
                                if (item.status.isNotEmpty)
                                  DramaTag(text: _statusLabel(item.status), color: AppColors.success),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _row('来源渠道', item.channelName.isEmpty ? '未知渠道' : item.channelName),
                  _row('关联原著', item.hasRelatedWork ? '已绑定原著剧本' : '暂未绑定'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.r),
              ),
              child: Column(
                children: [
                  FilledButton.icon(
                    onPressed: item.externalUrl.isEmpty
                        ? null
                        : () => _openExternal(context, item.externalUrl),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(item.externalUrl.isEmpty ? '暂无播放地址' : '去外部观看'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => context.push(RoutePath.dramaRelatedWorkUrl(item.dramaId)),
                    icon: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('找同款剧本'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '说明：该内容为站外视频，播放由外部应用提供，本平台仅作信息展示与原著关联。',
                style: TextStyle(fontSize: 12, color: AppColors.text3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.text3)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, color: AppColors.text1)),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
        'on_shelf' => '已上架',
        'off_shelf' => '已下架',
        _ => status,
      };

  /// 用系统浏览器/外部播放器打开站外播放地址（不内嵌 WebView）。
  static Future<void> _openExternal(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri.tryParse(url);
    if (uri == null) {
      messenger.showSnackBar(const SnackBar(content: Text('播放地址无效')));
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('无法打开播放地址')));
    }
  }
}