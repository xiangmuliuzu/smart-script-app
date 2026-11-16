import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'copyright_api_service.dart';
import 'copyright_models.dart';
import '../providers/copyright_provider.dart';

/// 版权 API 服务 Provider。
final copyrightApiServiceProvider = Provider<CopyrightApiService>(
  (ref) => CopyrightApiService(ref.watch(apiClientProvider)),
);

/// 版权管理 Provider（全局单例）。
final copyrightProvider = ChangeNotifierProvider<CopyrightProvider>((ref) {
  return CopyrightProvider(ref.watch(copyrightApiServiceProvider));
});

/// 按订单查交割单（订单详情用；没有交割单时返回 null）。
final deliveryByOrderProvider =
    FutureProvider.autoDispose.family<CopyrightDelivery?, int>((ref, orderId) async {
  try {
    return await ref.watch(copyrightApiServiceProvider).getDeliveryByOrder(orderId);
  } catch (_) {
    return null;
  }
});
