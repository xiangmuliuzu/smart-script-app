// 框架冒烟测试：验证应用可在初始化本地存储后正常构建。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/app.dart';
import 'package:script_app/core/providers/app_providers.dart' as providers;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          providers.sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: const ScriptApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(ScriptApp), findsOneWidget);
  });
}
