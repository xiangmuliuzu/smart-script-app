import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/user_center/data/user_center_providers.dart';
import '../providers/auth_providers.dart';
import 'local_notifier.dart';

/// 会话期的消息通知轮询。
///
/// 登录后启动一个定时器，周期拉取最新一页消息，把「未读且上次未见过的消息」通过
/// [LocalNotifier] 弹成系统通知；退出登录即停止。仅 App 进程存活时有效（本地通知，
/// 非离线推送），与消息页的前台轮询是两套独立机制、互不影响。
class NotificationPoller {
  NotificationPoller(this._ref);

  final Ref _ref;
  Timer? _timer;
  bool _polling = false;

  /// 已经处理过（弹过或已读）的消息 id；重登后由 [start] 重置，避免补弹历史未读。
  final Set<int> _seen = {};

  static const Duration _interval = Duration(seconds: 30);
  static const int _pageSize = 10;

  void start() {
    if (_timer != null) return;
    _seen.clear();
    // 登录后申请一次通知权限（Android 13+）；已授权或低版本为无副作用调用。
    LocalNotifier.ensurePermission();
    _timer = Timer.periodic(_interval, (_) => _poll());
    // 启动后稍等再首拉，避开登录瞬间的多请求并发。
    Future<void>.delayed(const Duration(seconds: 3), _poll);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    if (_polling) return;
    if (!_ref.read(authControllerProvider).isAuthenticated) return;
    _polling = true;
    try {
      final page = await _ref.read(messageRepositoryProvider).list(
            pageNum: 1,
            pageSize: _pageSize,
            includeAnnouncements: true,
          );
      for (final item in page.list) {
        final id = item.messageId;
        final firstSeen = _seen.add(id);
        // 首拉只登记基线，对已存在的未读不补弹；之后仅对「新未读」弹窗。
        if (!firstSeen) continue;
        if (item.read) continue;
        await LocalNotifier.show(
          id: id,
          title: item.title.isEmpty ? '新消息' : item.title,
          body: item.summary.isNotEmpty ? item.summary : (item.content ?? ''),
        );
      }
    } catch (_) {
      // 网络异常静默跳过，下一轮重试
    } finally {
      _polling = false;
    }
  }
}

/// 会话级单例：auth 变为已登录时启动轮询、退出时停止。
final notificationPollerProvider = Provider<NotificationPoller>((ref) {
  final poller = NotificationPoller(ref);
  ref.listen<bool>(
    authControllerProvider.select((s) => s.isAuthenticated),
    (previous, next) {
      if (next) {
        poller.start();
      } else {
        poller.stop();
      }
    },
  );
  ref.onDispose(poller.stop);
  return poller;
});
