import 'package:flutter/material.dart';

import '../../shared/widgets/placeholder_page.dart';

/// 分类（接口文档 2.10）——占位，待分类负责人实现。
class CategoryPage extends StatelessWidget {
  const CategoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderPage(title: '分类', subtitle: '分类列表 / 分类详情 / 标签');
  }
}
