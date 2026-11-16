import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../user_center/data/paged_data.dart';
import 'promotion_models.dart';
import 'promotion_repository.dart';

/// 作品推广依赖注入（复用框架层网络栈）。

final promotionRepositoryProvider = Provider<PromotionRepository>(
  (ref) => PromotionRepository(ref.watch(apiClientProvider)),
);

/// 指定资源位的位次（hot / search / banner）。
final promotionSlotsProvider =
    FutureProvider.autoDispose.family<PromotionSlotPage, String>(
  (ref, slotType) => ref.watch(promotionRepositoryProvider).listSlots(slotType),
);

/// 我的推广列表；key 为筛选状态（all / pending / locked / waiting / active / ended / rejected / cancelled）。
final myPromotionsProvider =
    FutureProvider.autoDispose.family<PagedData<PromotionApplication>, String>(
  (ref, viewStatus) => ref.watch(promotionRepositoryProvider).myApplications(
        viewStatus: viewStatus == 'all' ? null : viewStatus,
      ),
);

/// 推广申请详情。
final promotionDetailProvider =
    FutureProvider.autoDispose.family<PromotionApplication, int>(
  (ref, applyId) => ref.watch(promotionRepositoryProvider).detail(applyId),
);
