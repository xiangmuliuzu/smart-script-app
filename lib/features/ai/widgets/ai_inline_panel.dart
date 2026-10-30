import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/route_paths.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../welfare/data/welfare_providers.dart';
import '../ai_quota_dialog.dart';
import '../data/ai_providers.dart';
import 'ai_skill_selector.dart';

/// 写稿页内嵌 AI 创作面板（E 模块）。
///
/// 在章节写稿页正文编辑区上方展开，提供 AI 剧本 / 写作 / 润色 / 分镜四个功能 tab，
/// 复用 [AiRepository]（outline / write / polish / storyboard）生成，结果支持：
///   - 复制全文；
///   - [onInsert] 回调把生成内容插入当前章节正文（由写稿页追加到正文控制器）。
/// 生成逻辑与独立 AI 功能页一致：次数不足弹引导弹窗、成功后刷新机会余额；
/// 可选择「导演(skill)」注入导演风格。
class AiInlinePanel extends ConsumerStatefulWidget {
  const AiInlinePanel({super.key, required this.onInsert});

  /// 把生成文本插入当前章节正文。
  final ValueChanged<String> onInsert;

  @override
  ConsumerState<AiInlinePanel> createState() => _AiInlinePanelState();
}

enum _AiTab { outline, write, polish, storyboard }

class _AiInlinePanelState extends ConsumerState<AiInlinePanel> {
  _AiTab _tab = _AiTab.outline;
  int? _skillId;

  // 大纲
  final _inspiration = TextEditingController();
  final _genre = TextEditingController();
  final _style = TextEditingController();

  // 写作
  final _prompt = TextEditingController();
  final _type = TextEditingController();

  // 润色
  final _content = TextEditingController();
  static const _polishStyles = ['简洁精炼', '专业正式', '文学优美', '轻松幽默', '情感细腻'];
  String? _selectedStyle;

  // 分镜（与独立 AI 分镜页一致：剧本文本 + 分镜风格）
  final _script = TextEditingController();
  static const _scriptStyles = ['电影感', '短剧竖屏', '动漫风'];
  String? _selectedScriptStyle;

  bool _loading = false;
  String _result = '';
  int _quotaUsed = 0;

  @override
  void dispose() {
    _inspiration.dispose();
    _genre.dispose();
    _style.dispose();
    _prompt.dispose();
    _type.dispose();
    _content.dispose();
    _script.dispose();
    super.dispose();
  }

  /// 校验当前 tab 输入并生成（流式：逐块追加显示）。
  Future<void> _generate() async {
    final requiredEmpty = switch (_tab) {
      _AiTab.outline => _inspiration.text.trim().isEmpty,
      _AiTab.write => _prompt.text.trim().isEmpty,
      _AiTab.polish => _content.text.trim().isEmpty,
      _AiTab.storyboard => _script.text.trim().isEmpty,
    };
    if (requiredEmpty) {
      final hint = switch (_tab) {
        _AiTab.outline => '请先输入作品主题或灵感',
        _AiTab.write => '请先输入写作提示词',
        _AiTab.polish => '请先填写或粘贴需要润色的内容',
        _AiTab.storyboard => '请先填写或粘贴剧本文本',
      };
      showAppToast(context, hint);
      return;
    }

    setState(() {
      _loading = true;
      _result = '';
      _quotaUsed = 0;
    });
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final repo = ref.read(aiRepositoryProvider);
      void onDelta(String delta) {
        if (!mounted) return;
        setState(() => _result += delta);
      }

      String text;
      String? emptyHint;
      switch (_tab) {
        case _AiTab.outline:
          final result = await repo.outlineStream(
            inspiration: _inspiration.text.trim(),
            genre: _genre.text.trim(),
            style: _style.text.trim(),
            skillId: _skillId,
            onDelta: onDelta,
          );
          text = result.outlineText;
          _quotaUsed = result.quotaUsed;
          if (text.trim().isEmpty) emptyHint = '未生成剧本大纲，请重试';
          break;
        case _AiTab.write:
          final result = await repo.writeStream(
            prompt: _prompt.text.trim(),
            type: _type.text.trim(),
            skillId: _skillId,
            onDelta: onDelta,
          );
          text = result.content;
          if (text.trim().isEmpty) emptyHint = '未生成内容，请重试';
          break;
        case _AiTab.polish:
          final result = await repo.polishStream(
            content: _content.text.trim(),
            style: _selectedStyle,
            skillId: _skillId,
            onDelta: onDelta,
          );
          text = result.content;
          if (text.trim().isEmpty) emptyHint = '未生成润色结果，请重试';
          break;
        case _AiTab.storyboard:
          final result = await repo.storyboardStream(
            script: _script.text.trim(),
            style: _selectedScriptStyle,
            skillId: _skillId,
            onDelta: onDelta,
          );
          text = result.content;
          if (text.trim().isEmpty) emptyHint = '未生成分镜，请重试';
          break;
      }
      // 扣减已发生：刷新机会余额缓存（写稿页无次数展示，福利中心/创作页仍监听）。
      container.invalidate(aiBalanceProvider);
      container.invalidate(welfareAssetProvider);
      if (!mounted) return;
      if (emptyHint != null) showAppToast(context, emptyHint);
      setState(() => _result = text);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (isQuotaInsufficientError(e)) {
        showAiQuotaInsufficientDialog(context, message: e.message);
      } else {
        showAppToast(context, e.message);
      }
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, '操作失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _copy() {
    if (_result.trim().isEmpty) return;
    Clipboard.setData(ClipboardData(text: _result));
    showAppToast(context, '内容已复制');
  }

  void _insert() {
    if (_result.trim().isEmpty) return;
    widget.onInsert(_result);
    showAppToast(context, '已插入章节正文');
  }

  @override
  Widget build(BuildContext context) {
    // 积分余额（与 PC 用户端一致：AI 创作旁展示剩余积分）。
    final asset = ref.watch(welfareAssetProvider);
    final pointsText = asset.when(
      loading: () => '积分 —',
      error: (_, __) => '积分 —',
      data: (value) => '积分 ${value.points.balance}',
    );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.r),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text('AI 创作',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text1)),
              const Spacer(),
              Text(pointsText,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
              const SizedBox(width: 12),
              // AI 记录入口：记录内容多，内嵌展示不便，直接跳转记录页。
              InkWell(
                onTap: () => context.push(RoutePath.aiRecords),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primaryTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.history, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('AI 记录',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _tabChip(_AiTab.outline, '剧本'),
              const SizedBox(width: 6),
              _tabChip(_AiTab.write, '写作'),
              const SizedBox(width: 6),
              _tabChip(_AiTab.polish, '润色'),
              const SizedBox(width: 6),
              _tabChip(_AiTab.storyboard, '分镜'),
            ],
          ),
          const SizedBox(height: 10),
          AiSkillSelector(
            selectedSkillId: _skillId,
            onChanged: (value) => setState(() => _skillId = value),
            enabled: !_loading,
            skillTypeFilter: _tab == _AiTab.storyboard ? 'storyboard' : 'write',
          ),
          const SizedBox(height: 10),
          _buildForm(),
          if (_result.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 140),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.fill,
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  _result,
                  style: const TextStyle(
                      fontSize: 13, height: 1.6, color: AppColors.text2),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_quotaUsed > 0) ...[
                  Text('消耗 $_quotaUsed token',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.text3)),
                  const Spacer(),
                ] else
                  const Spacer(),
                OutlinedButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _insert,
                  icon: const Icon(Icons.south_west, size: 16),
                  label: const Text('插入正文'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// tab 切换小按钮。
  Widget _tabChip(_AiTab tab, String label) {
    final selected = _tab == tab;
    return InkWell(
      onTap: _loading
          ? null
          : () => setState(() {
                _tab = tab;
                _result = '';
                _quotaUsed = 0;
              }),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryTint : AppColors.fill,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.primary : AppColors.text2,
          ),
        ),
      ),
    );
  }

  /// 当前 tab 的输入表单（按功能不同渲染）。
  Widget _buildForm() {
    final Widget form = switch (_tab) {
      _AiTab.outline => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_inspiration, '主题 / 灵感 *', 3, '例如：落魄青年意外获得穿越能力'),
            const SizedBox(height: 10),
            _field(_genre, '题材（可选）', 1, '例如：都市、玄幻、悬疑'),
            const SizedBox(height: 10),
            _field(_style, '风格（可选）', 1, '例如：爽文、正剧、轻松搞笑'),
          ],
        ),
      _AiTab.write => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_prompt, '写作提示词 *', 4, '例如：写一段男主重逢对手戏，冲突强烈'),
            const SizedBox(height: 10),
            _field(_type, '写作类型（可选）', 1, '例如：对话、旁白、动作描写'),
          ],
        ),
      _AiTab.polish => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_content, '待润色内容 *', 4, '粘贴需要润色的正文、对话或旁白'),
            const SizedBox(height: 10),
            const Text('选择风格',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in _polishStyles)
                  _styleChip(style),
              ],
            ),
          ],
        ),
      _AiTab.storyboard => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _field(_script, '剧本文本 *', 4, '粘贴 AI 剧本或自写剧本，AI 将拆解为可出售的分镜脚本'),
            const SizedBox(height: 10),
            const Text('选择分镜风格',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text1)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final style in _scriptStyles)
                  InkWell(
                    onTap: () => setState(() {
                      _selectedScriptStyle =
                          (_selectedScriptStyle == style ? null : style);
                    }),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedScriptStyle == style
                            ? AppColors.primary
                            : AppColors.fill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _selectedScriptStyle == style
                              ? AppColors.primary
                              : AppColors.divider,
                        ),
                      ),
                      child: Text(
                        style,
                        style: TextStyle(
                          fontSize: 12,
                          color: _selectedScriptStyle == style
                              ? Colors.white
                              : AppColors.text2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        form,
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: ElevatedButton(
            onPressed: _loading ? null : _generate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.rSmall),
              ),
            ),
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : const Text('生成',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    int maxLines,
    String hint,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text1)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: AppColors.text3, fontSize: 12),
            filled: true,
            fillColor: AppColors.fill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            isDense: true,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.rSmall),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
          ),
          style: const TextStyle(fontSize: 13, color: AppColors.text1),
        ),
      ],
    );
  }

  Widget _styleChip(String style) {
    final selected = _selectedStyle == style;
    return InkWell(
      onTap: () => setState(() {
        _selectedStyle = selected ? null : style;
      }),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.fill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          style,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.white : AppColors.text2,
          ),
        ),
      ),
    );
  }
}
