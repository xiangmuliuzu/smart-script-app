import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

/// 书城（接口文档 2.7）——占位，待书城负责人实现。
class BookstorePage extends StatelessWidget {
  const BookstorePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '书城', subtitle: '作品列表 / 详情 / 榜单 / 书架');
  }
}
