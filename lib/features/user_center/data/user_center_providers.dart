import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../data/message_repository.dart';
import '../data/user_center_models.dart';
import '../data/user_center_repository.dart';

/// A5 用户中心依赖注入（与框架层 [apiClientProvider] 同源，不新建网络栈）。

final userCenterRepositoryProvider = Provider<UserCenterRepository>(
  (ref) => UserCenterRepository(ref.watch(apiClientProvider)),
);

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepository(ref.watch(apiClientProvider)),
);

final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => FeedbackRepository(ref.watch(apiClientProvider)),
);

/// 个人资料：进入资料页时拉取最新值，返回后由页面触发全局 currentUser 刷新。
final userProfileProvider = FutureProvider.autoDispose<UserProfile>(
  (ref) => ref.watch(userCenterRepositoryProvider).profile(),
);

/// 实名状态：提交或重提后 invalidate 以重新拉取。
final realNameStatusProvider = FutureProvider.autoDispose<RealNameStatus>(
  (ref) => ref.watch(userCenterRepositoryProvider).realNameStatus(),
);

/// 未读消息数：我的页与消息中心共用；已读操作后 invalidate。
final unreadCountProvider = FutureProvider<UnreadCount>(
  (ref) => ref.watch(messageRepositoryProvider).unreadCount(),
);

/// 通知偏好。
final notificationPreferencesProvider =
    FutureProvider.autoDispose<List<NotificationPreference>>(
  (ref) => ref.watch(messageRepositoryProvider).preferences(),
);
