import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_colors.dart';

/// 国家 / 地区区号选择器。
///
/// 第一期只支持中国大陆（后端手机号规则为 11 位大陆号码），
/// 这里保留完整交互入口与数据结构，后续接入更多区号时只需扩充 [_supportedCodes]。
class CountryCodePicker extends StatelessWidget {
  const CountryCodePicker({super.key, this.code = AppConfig.defaultCountryCode});

  /// 当前区号。
  final String code;

  /// 已支持的区号列表（name + code）。
  static const List<Map<String, String>> _supportedCodes = [
    {'name': '中国大陆', 'code': '+86'},
  ];

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _showPicker(context),
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              code,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.text1,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.text3),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  '选择国家和地区',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              ..._supportedCodes.map(
                (item) => ListTile(
                  title: Text('${item['name']}'),
                  trailing: Text(
                    '${item['code']}',
                    style: const TextStyle(color: AppColors.text2),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Text(
                  '当前版本仅支持中国大陆手机号，更多区号敬请期待',
                  style: TextStyle(fontSize: 12, color: AppColors.text3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
