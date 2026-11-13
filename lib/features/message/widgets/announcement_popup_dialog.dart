import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// 进入 App 时的平台公告弹窗。
///
/// 只负责展示标题与正文；是否已读、消息中心可见性由调用方处理。
class AnnouncementPopupDialog extends StatelessWidget {
  const AnnouncementPopupDialog({
    super.key,
    required this.title,
    required this.content,
    this.createdAt,
  });

  final String title;
  final String content;

  /// 服务端时间字符串（`yyyy-MM-dd HH:mm:ss`）；无值时只显示「平台公告」。
  final String? createdAt;

  @override
  Widget build(BuildContext context) {
    final text = content.trim();
    final date = _dateText(createdAt);
    final maxBodyHeight = MediaQuery.sizeOf(context).height * 0.42;

    return Dialog(
      key: const Key('announcement-popup'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 32,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.primaryTint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.campaign_outlined,
                      size: 22,
                      color: AppColors.text1,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '平台公告',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.8,
                                color: AppColors.text3,
                              ),
                            ),
                            const Spacer(),
                            if (date.isNotEmpty)
                              Text(
                                date,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.text3,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          title.trim().isEmpty ? '公告' : title.trim(),
                          style: const TextStyle(
                            fontSize: 17.5,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                            color: AppColors.text1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (text.isNotEmpty) ...[
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxBodyHeight),
                  child: SingleChildScrollView(
                    child: Text(
                      text,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.8,
                        color: AppColors.text2,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('知道了'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateText(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    return value.split(' ').first.replaceAll('-', '.');
  }
}
