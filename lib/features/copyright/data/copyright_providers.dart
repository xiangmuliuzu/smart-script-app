import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import 'copyright_api_service.dart';
import '../providers/copyright_provider.dart';

/// 版权 API 服务 Provider。
final copyrightApiServiceProvider = Provider<CopyrightApiService>(
  (ref) => CopyrightApiService(ref.watch(apiClientProvider)),
);

/// 版权管理 Provider（全局单例）。
final copyrightProvider = ChangeNotifierProvider<CopyrightProvider>((ref) {
  return CopyrightProvider(ref.watch(copyrightApiServiceProvider));
});
