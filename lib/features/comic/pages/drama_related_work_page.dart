import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/auth_guard.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/common_views.dart';
import '../../bookstore/widgets/bookstore_widgets.dart';
import '../data/drama_providers.dart';

/// 找同款剧本（B 模块，接口文档 2.8.16；追更 2.8.13）。
///
/// 公开页：关联原著信息（复用作列表行）游客可见；
/// 「观看短剧」与「追更」为受保护动作，未登录由 [AuthGuard] 引导登录后回跳本页。
///
/// 追更状态说明：2.8 只提供 POST/DELETE 与追更列表，契约未定义「按作品查追更态」
/// 接口，故不做进入即回显（不用列表前 N 条推测，避免误显）；首次进入统一显示「追更」，
/// 操作成功后就地切换，重复追更为后端保证的幂等成功。
class DramaRelatedWorkPage extends ConsumerStatefulWidget {
  const DramaRelatedWorkPage({super.key, required this.dramaId});

  final int dramaId;

  @override
  ConsumerState<DramaRelatedWorkPage> createState() => _DramaRelatedWorkPageState();
}

class _DramaRelatedWorkPageState extends ConsumerState<DramaRelatedWorkPage> {
  bool _subscribed = false;
  bool _busy = false;

  String get _selfLocation => RoutePath.dramaRelatedWorkUrl(widget.dramaId);

  Future<void> _toggleSubscribe(int workId) async {
    if (!AuthGuard.requireLogin(context, ref, target: _selfLocation)) return;
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(dramaRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (_subscribed) {
        await repo.unsubscribe(workId);
        if (mounted) setState(() => _subscribed = false);
        messenger.showSnackBar(const SnackBar(content: Text('已取消追更')));
      } else {
        await repo.subscribe(workId);
        if (mounted) setState(() => _subscribed = true);
        messenger.showSnackBar(const SnackBar(content: Text('已追更，更新时可在「我的追更」查看')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e is ApiException ? e.message : '操作失败，请稍后重试'),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final related = ref.watch(relatedWorkProvider(widget.dramaId));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('找同款剧本')),
      body: related.when(
        loading: () => const LoadingView(message: '加载中'),
        error: (e, __) => ErrorView(
          message: e is ApiException ? e.message : '加载失败，请稍后重试',
          onRetry: () => ref.invalidate(relatedWorkProvider(widget.dramaId)),
        ),
        data: (payload) {
          final work = payload.work;
          if (!payload.hasRelatedWork) {
            return const EmptyView(message: '该视频暂未绑定原著剧本', icon: Icons.link_off);
          }
          if (work == null) {
            return const EmptyView(message: '原著暂不可见', icon: Icons.visibility_off_outlined);
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 12),
            children: [
              Container(
                color: AppColors.card,
                child: WorkListTile(
                  work: work,
                  onTap: () => context.push(RoutePath.workDetailUrl(work.workId)),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    FilledButton.icon(
                      onPressed: () => AuthGuard.pushProtected(
                        context,
                        ref,
                        target: RoutePath.dramaPlayUrl(work.workId),
                      ),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('观看短剧'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _toggleSubscribe(work.workId),
                      icon: Icon(
                        _subscribed ? Icons.bookmark : Icons.bookmark_border,
                        size: 18,
                      ),
                      label: Text(_subscribed ? '已追更（点击取消）' : '追更此作品'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}