import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:script_app/app.dart';
import 'package:script_app/core/providers/app_providers.dart';
import 'package:script_app/core/storage/secure_token_storage.dart';

void main() {
  testWidgets('应用可构建且无免登录按钮', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureTokenStorageProvider.overrideWithValue(InMemoryTokenSecureStorage()),
        ],
        child: const ScriptApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MaterialApp), findsWidgets);
    expect(find.textContaining('测试进入'), findsNothing);
  });
}
