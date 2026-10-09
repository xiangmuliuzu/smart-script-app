import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import 'announcement_repository.dart';

final announcementRepositoryProvider = Provider<AnnouncementRepository>(
    (ref) => AnnouncementRepository(ref.watch(apiClientProvider)));
final announcementUnreadProvider = FutureProvider.autoDispose<int>(
    (ref) => ref.watch(announcementRepositoryProvider).unreadCount());
