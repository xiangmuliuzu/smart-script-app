import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 全局主题。所有页面通过 `Theme.of(context)` 使用统一样式。
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      // 页面背景由 AppPageBackground 的渐变提供，Scaffold 须透明透出。
      scaffoldBackgroundColor: Colors.transparent,
      // 顶栏同样透明，让顶部冰蓝渐变从状态栏一直延伸到内容区，
      // 避免白色 AppBar 与渐变背景之间出现割裂的色块。
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.text1,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.text1,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // 描边按钮以主色勾边框，文字统一用正文黑，避免整屏蓝字。
          foregroundColor: AppColors.text1,
          minimumSize: const Size.fromHeight(44),
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.r),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.text1),
      ),
      tabBarTheme: const TabBarTheme(labelColor: AppColors.text1),
      chipTheme: const ChipThemeData(
        // 选中态靠底色区分，标签文字保持黑色；未选中态沿用默认灰字。
        secondaryLabelStyle: TextStyle(color: AppColors.text1),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.card,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.rSmall),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        // 聚焦时浮动标签默认取主色，这里统一回正文色，主色只留在描边上。
        floatingLabelStyle: const TextStyle(color: AppColors.text2),
      ),
      cardTheme: CardTheme(
        color: AppColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.r),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
