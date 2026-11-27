import 'package:flutter/material.dart';

/// 底部弹出编辑弹层（作品资料 / 章节概要等「整段替换」编辑共用）。
///
/// 键盘弹起时自动上推（[isScrollControlled] + viewInsets），多行文本可滚动；
/// 返回用户确认后的文本，取消 / 下滑关闭返回 null。
Future<String?> showBlueprintTextEditSheet(
  BuildContext context, {
  required String title,
  String subtitle = '直接写文本，保存后整段替换',
  required String initialValue,
  String? hintText,
  String? helperText,
  int minLines = 8,
  bool enabled = true,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (sheetContext) => _TextEditSheet(
      title: title,
      subtitle: subtitle,
      initialValue: initialValue,
      hintText: hintText,
      helperText: helperText,
      minLines: minLines,
      enabled: enabled,
    ),
  );
}

class _TextEditSheet extends StatefulWidget {
  const _TextEditSheet({
    required this.title,
    required this.subtitle,
    required this.initialValue,
    this.hintText,
    this.helperText,
    required this.minLines,
    required this.enabled,
  });

  final String title;
  final String subtitle;
  final String initialValue;
  final String? hintText;
  final String? helperText;
  final int minLines;
  final bool enabled;

  @override
  State<_TextEditSheet> createState() => _TextEditSheetState();
}

class _TextEditSheetState extends State<_TextEditSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.86),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                alignment: Alignment.center,
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E6EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 3, 16, 10),
                child: Text(widget.subtitle,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF86909C))),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: TextField(
                    controller: _controller,
                    enabled: widget.enabled,
                    autofocus: true,
                    maxLines: null,
                    minLines: widget.minLines,
                    keyboardType: TextInputType.multiline,
                    style: const TextStyle(fontSize: 14, height: 1.8),
                    decoration: InputDecoration(
                      hintText: widget.hintText,
                      helperText: widget.helperText,
                      helperMaxLines: 3,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: widget.enabled
                            ? () => Navigator.of(context).pop(_controller.text)
                            : null,
                        child: const Text('保存'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
