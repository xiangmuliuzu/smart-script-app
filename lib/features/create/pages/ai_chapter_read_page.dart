import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 章节正文阅读页（AI 创作页内预览用）。
///
/// 直接展示本次生成的正文，不依赖已落库/已上架章节接口：章节刚生成、
/// 甚至来自 AI 记录的预览章节，都能从创作页点「查看正文」进入阅读。
class AiChapterReadPage extends StatelessWidget {
  const AiChapterReadPage({super.key, required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(
        title: const Text('章节正文'),
        backgroundColor: Colors.white,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.text1,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            content,
            style: const TextStyle(fontSize: 16.5, height: 1.9, color: AppColors.text1),
          ),
        ],
      ),
    );
  }
}
