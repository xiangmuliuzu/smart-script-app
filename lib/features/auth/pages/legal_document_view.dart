import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 法律文本章节。
class LegalSection {
  const LegalSection(this.heading, this.paragraphs);

  final String heading;
  final List<String> paragraphs;
}

/// 协议类页面通用视图：标题栏 + 版本信息 + 分章节正文。
///
/// 「用户协议」与「隐私政策」两个页面共用本视图，避免重复布局代码。
class LegalDocumentView extends StatelessWidget {
  const LegalDocumentView({
    super.key,
    required this.title,
    required this.version,
    required this.effectiveDate,
    required this.sections,
  });

  final String title;
  final String version;
  final String effectiveDate;
  final List<LegalSection> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          tooltip: '返回',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(
            '版本 v$version · 生效日期 $effectiveDate',
            style: const TextStyle(fontSize: 12, color: AppColors.text3),
          ),
          const SizedBox(height: 16),
          for (final section in sections) ...[
            Text(
              section.heading,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(height: 6),
            for (final paragraph in section.paragraphs) ...[
              Text(
                paragraph,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.7,
                  color: AppColors.text2,
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}
