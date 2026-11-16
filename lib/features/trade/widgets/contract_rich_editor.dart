import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/theme/app_colors.dart';

/// 合同正文条款富文本标记，与后端 ContractClauseDocument、PC 端编辑器保持一致。
const String kContractDocPrefix = '<div data-contract-document="1">';
const String kContractDocSuffix = '</div>';

bool isContractDocument(String value) =>
    value.startsWith(kContractDocPrefix) && value.endsWith(kContractDocSuffix);

/// 取条款的纯文本形态（用于非空校验与字数展示）；纯文本条款原样返回。
String contractDocumentPlain(String value) {
  if (!isContractDocument(value)) return value;
  final body =
      value.substring(kContractDocPrefix.length, value.length - kContractDocSuffix.length);
  final stripped = body
      .replaceAll(RegExp('<(?:script|style)\\b[^>]*>[\\s\\S]*?</(?:script|style)>',
          caseSensitive: false), '')
      .replaceAll(
          RegExp('<br\\s*/?>|</(?:p|div|h[1-6]|li|blockquote)>', caseSensitive: false), '\n')
      .replaceAll(RegExp('<[^>]*>'), '');
  return _unescape(stripped).trimRight();
}

/// 把库里存的条款（富文本或历史纯文本）转成编辑区可编辑的 HTML 片段。
String contractDocEditableHtml(String stored) {
  if (stored.isEmpty) return '';
  if (isContractDocument(stored)) {
    return stored.substring(
        kContractDocPrefix.length, stored.length - kContractDocSuffix.length);
  }
  // 历史纯文本：「第…条」行按小标题回填，其余按段落，和后端渲染口径一致
  final buffer = StringBuffer();
  for (final line in stored.split(RegExp(r'\r?\n'))) {
    final text = line.trim();
    if (text.isEmpty) continue;
    final safe = _escape(text);
    buffer.write(RegExp(r'^第[一二三四五六七八九十百千0-9]+条').hasMatch(text)
        ? '<h3>$safe</h3>'
        : '<p>$safe</p>');
  }
  return buffer.toString();
}

String _unescape(String value) => value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&');

String _escape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// 合同正文条款富文本编辑器：contenteditable WebView + 原生工具栏。
///
/// APP 端只做基础排版（字号、加粗、斜体、下划线、标题、对齐、列表、引用、清除格式），
/// 产出 HTML 与 PC 端共用同一份标记格式，来回编辑不丢格式；入库仍由服务端白名单净化兜底。
class ContractRichEditor extends StatefulWidget {
  const ContractRichEditor({
    super.key,
    required this.initialClauses,
  });

  /// 库内条款原文：富文本标记串或历史纯文本
  final String initialClauses;

  @override
  State<ContractRichEditor> createState() => ContractRichEditorState();
}

class ContractRichEditorState extends State<ContractRichEditor> {
  late final WebViewController _controller;
  bool _ready = false;

  /// 字号档位：execCommand 的 fontSize 只有 1~7 档，3 档约等于 16px
  int _fontSizeStep = 3;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _ready = true),
      ))
      ..loadHtmlString(_documentHtml(contractDocEditableHtml(widget.initialClauses)));
  }

  @override
  void didUpdateWidget(ContractRichEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切换平台模板时外层只换初值，这里重载文档，避免沿用上一模板的内容
    if (oldWidget.initialClauses == widget.initialClauses) return;
    setState(() {
      _ready = false;
      _fontSizeStep = 3;
    });
    _controller
        .loadHtmlString(_documentHtml(contractDocEditableHtml(widget.initialClauses)));
  }

  /// 导出带标记的条款富文本；内容为空返回 null，由调用方提示。
  Future<String?> exportClauses() async {
    if (!_ready) return null;
    final html = _resultAsString(
        await _controller.runJavaScriptReturningResult('window.__exportClauses()'));
    if (html.isEmpty || contractDocumentPlain(html).trim().isEmpty) return null;
    return '$kContractDocPrefix$html$kContractDocSuffix';
  }

  void _run(String command, [String? value]) {
    if (!_ready) return;
    final payload = value == null ? 'null' : "'$value'";
    _controller.runJavaScript('window.__exec(\'$command\', $payload)');
  }

  void _changeFontSize(int delta) {
    final step = (_fontSizeStep + delta).clamp(1, 7);
    if (step == _fontSizeStep) return;
    setState(() => _fontSizeStep = step);
    _run('fontSize', '$step');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF7F6F2),
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                _tool('A−', () => _changeFontSize(-1), '字号变小'),
                _tool('A+', () => _changeFontSize(1), '字号变大'),
                const _Divider(),
                _tool('B', () => _run('bold'), '加粗'),
                _tool('I', () => _run('italic'), '斜体'),
                _tool('U', () => _run('underline'), '下划线'),
                const _Divider(),
                _tool('标题', () => _run('formatBlock', '<h2>'), '设为标题'),
                _tool('正文', () => _run('formatBlock', '<p>'), '恢复正文'),
                const _Divider(),
                _tool('左', () => _run('justifyLeft'), '左对齐'),
                _tool('中', () => _run('justifyCenter'), '居中'),
                _tool('右', () => _run('justifyRight'), '右对齐'),
                const _Divider(),
                _tool('1.', () => _run('insertOrderedList'), '编号列表'),
                _tool('•', () => _run('insertUnorderedList'), '项目符号'),
                _tool('引用', () => _run('formatBlock', '<blockquote>'), '引用段落'),
                const _Divider(),
                _tool('清除', () => _run('removeFormat'), '清除所选文字格式'),
              ],
            ),
          ),
        ),
        Expanded(
          child: WebViewWidget(controller: _controller),
        ),
      ],
    );
  }

  Widget _tool(String label, VoidCallback onTap, String tip) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: _ready ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _ready ? AppColors.text1 : AppColors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
      width: 1,
      height: 15,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: AppColors.divider);
}

/// Android 上字符串结果可能被再包一层 JSON 引号，统一解开。
String _resultAsString(Object? raw) {
  if (raw == null) return '';
  var text = raw.toString();
  if (text == 'null') return '';
  if (text.startsWith('"') && text.endsWith('"')) {
    try {
      text = jsonDecode(text) as String;
    } on FormatException {
      // 非严格 JSON 字符串，按原文处理
    }
  }
  return text;
}

String _documentHtml(String bodyHtml) => '''
<!DOCTYPE html><html lang="zh-CN"><head><meta charset="utf-8" />
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no" />
<style>
html,body{margin:0;padding:0;background:#fff;}
/* 与后端合同文档同一口径（ContractHtmlSupport 的 body 与 .clause-rich 规则），编辑区看到的就是签约时看到的。 */
body{font-family:SimSun,'Songti SC',serif;font-size:14px;line-height:1.8;color:#000;padding:10px 12px;-webkit-text-size-adjust:100%;}
#doc{outline:none;min-height:120px;text-align:justify;}
#doc p{margin:15px 0;text-indent:28px;}
#doc h1,#doc h2,#doc h3{font-weight:bold;margin:20px 0 10px;}
#doc h1{font-size:20px;}
#doc h2{font-size:17px;}
#doc h3{font-size:16px;}
#doc ul,#doc ol{margin:15px 0;padding-left:28px;}
#doc li{margin-bottom:4px;}
#doc blockquote{margin:15px 0 15px 16px;padding-left:12px;border-left:3px solid #999;color:#444;}
</style></head><body>
<div id="doc" contenteditable="true">$bodyHtml</div>
<script>
var doc = document.getElementById('doc');
// execCommand 的 fontSize 只会写 CSS 关键字字号，这里换成与 PC 端一致的像素档位（3 档为正文默认，不落样式）。
var sizeMap = {'xx-small':'12px','x-small':'14px','small':'14px','medium':'','large':'18px','x-large':'24px','xx-large':'32px'};
function normalizeSize(root){
  var nodes = root.querySelectorAll('[style]');
  for (var i = 0; i < nodes.length; i++) {
    var el = nodes[i];
    var fs = (el.style.getPropertyValue('font-size') || '').toLowerCase();
    if (!fs || sizeMap[fs] === undefined) continue;
    if (sizeMap[fs]) el.style.setProperty('font-size', sizeMap[fs]);
    else el.style.removeProperty('font-size');
    if (el.getAttribute('style') === '') el.removeAttribute('style');
  }
}
function blank(value){ return !value || value.replace(/<[^>]*>/g,'').replace(/\\u00a0/g,' ').trim() === ''; }
window.__exec = function(name, value){
  try { document.execCommand('styleWithCSS', false, true); } catch (e) {}
  document.execCommand(name, false, value === null ? null : value);
  doc.focus();
};
window.__exportClauses = function(){
  normalizeSize(doc);
  var html = doc.innerHTML;
  return blank(html) || blank(doc.innerText) ? '' : html;
};
</script></body></html>
''';
