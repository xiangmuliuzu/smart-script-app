import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../user_center/data/message_repository.dart';
import '../../user_center/data/user_center_models.dart';
import '../../user_center/data/user_center_providers.dart';

/// 关闭公告弹窗（展示详情）。
typedef AnnouncementPresenter = Future<void> Function(MessageItem detail);

/// 进入 App 时的公告提醒检查。
///
/// 只处理「未读且本次会话未弹过」的最新公告：先取列表定位，再取详情展示；
/// 弹窗关闭后写已读，公告本身仍保留在消息中心，可随时回看。
class AnnouncementEntryChecker {
  AnnouncementEntryChecker(this._repository);

  final MessageRepository _repository;

  /// 本次进程内已提示过的公告：即便写已读失败也不在同一会话反复弹。
  final Set<int> _handled = <int>{};
  bool _checking = false;

  /// 返回是否实际弹出了公告。
  Future<bool> check({
    required bool Function() isSessionActive,
    required AnnouncementPresenter present,
  }) async {
    if (_checking || !isSessionActive()) return false;
    _checking = true;
    try {
      final page = await _repository.announcements(pageNum: 1, pageSize: 20);
      MessageItem? latest;
      for (final item in page.list) {
        if (!item.read && !_handled.contains(item.messageId)) {
          latest = item;
          break;
        }
      }
      if (latest == null || !isSessionActive()) return false;
      final detail = await _repository.detail(latest.messageId,
          source: 'ANNOUNCEMENT');
      if (!isSessionActive()) return false;
      _handled.add(latest.messageId);
      await present(detail);
      // 关闭后置已读；失败不重弹，下次进入再按服务端状态决定。
      try {
        await _repository.markRead(latest.messageId, source: 'ANNOUNCEMENT');
      } catch (_) {
        // 已读写入失败不阻塞退出弹窗流程。
      }
      return true;
    } catch (_) {
      // 入口提醒失败不阻塞使用，下次进入再试。
      return false;
    } finally {
      _checking = false;
    }
  }

  /// 退出登录时清空会话内去重表，换账号后可重新提醒。
  void reset() => _handled.clear();
}

final announcementEntryCheckerProvider = Provider<AnnouncementEntryChecker>(
  (ref) => AnnouncementEntryChecker(ref.watch(messageRepositoryProvider)),
);
