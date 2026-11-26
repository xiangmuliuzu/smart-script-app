import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/theme/app_theme.dart';
import 'package:script_app/features/bookstore/data/bookstore_models.dart';
import 'package:script_app/features/bookstore/data/content_providers.dart';
import 'package:script_app/features/profile/pages/user_profile_page.dart';
import 'package:script_app/features/user_center/data/paged_data.dart';
import 'package:script_app/features/user_center/data/user_center_providers.dart';
import 'package:script_app/features/user_center/data/user_social_models.dart';
import 'package:script_app/features/user_center/data/user_social_repository.dart';

class _FakeSocialRepo implements UserSocialRepository {
  @override
  Future<FollowResult> follow(int targetUserId) async =>
      const FollowResult(following: true, followerCount: 2);

  @override
  Future<FollowResult> unfollow(int targetUserId) async =>
      const FollowResult(following: false, followerCount: 1);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

void main() {
  testWidgets('他人主页点击关注切换为已关注时，在全局主题下头部不挤压错位', (tester) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const profile = UserProfileView(
      userId: 106,
      nickname: '测试创作者',
      bio: '这个人很懒，什么都没写~',
      registeredAt: '2026-10-09T08:00:00',
      followingCount: 0,
      followerCount: 1,
      likeCount: 169890,
      userType: '02',
      isSelf: false,
      isFollowing: false,
      isBlocked: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileViewProvider(106).overrideWith((ref) async => profile),
          authorWorksProvider(106)
              .overrideWith((ref) async => const PagedData<BookItem>(total: 0, list: [])),
          userSocialRepositoryProvider.overrideWithValue(_FakeSocialRepo()),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const UserProfilePage(userId: 106),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('+ 关注'), findsOneWidget);
    final joinBefore = tester.getRect(find.text('加入时间 2026-10-09'));

    await tester.tap(find.text('+ 关注'));
    await tester.pumpAndSettle();

    expect(find.text('已关注'), findsOneWidget);
    final joinAfter = tester.getRect(find.text('加入时间 2026-10-09'));
    final buttonRect = tester.getRect(find.byType(OutlinedButton));

    // 加入时间保持单行横向展示，不被挤压成竖排
    expect(joinAfter.width, greaterThan(100));
    expect(joinAfter.height, lessThan(28));
    expect((joinAfter.height - joinBefore.height).abs(), lessThan(4));
    // 已关注按钮宽度紧凑且不越出屏幕
    expect(buttonRect.width, lessThan(140));
    expect(buttonRect.right, lessThanOrEqualTo(412));
  });
}
