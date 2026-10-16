import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/providers/auth_providers.dart';
import 'ai_models.dart';
import 'ai_repository.dart';

final aiRepositoryProvider = Provider<AiRepository>(
  (ref) => AiRepository(ref.watch(apiClientProvider)),
);

/// 当前登录用户 ID；未登录返回 0（页面受守卫保护，正常不会走到）。
int currentUserId(Ref ref) =>
    ref.watch(authControllerProvider).user?.userId ?? 0;

/// AI 机会余额（加载后缓存，页面共用；兑换/消耗后手动 invalidate 刷新）。
final aiBalanceProvider = FutureProvider<AiQuotaBalance>((ref) {
  final userId = currentUserId(ref);
  if (userId == 0) throw StateError('未登录');
  return ref.watch(aiRepositoryProvider).balance(userId);
});
