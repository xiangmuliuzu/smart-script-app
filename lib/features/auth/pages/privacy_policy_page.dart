import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/app_providers.dart';
import '../data/agreement_versions.dart';
import 'legal_document_view.dart';

/// 隐私政策页。
///
/// 内容与后端实际收集范围保持一致：手机号、短信验证码记录、设备标识与登录日志。
class PrivacyPolicyPage extends ConsumerStatefulWidget {
  const PrivacyPolicyPage({super.key});

  @override
  ConsumerState<PrivacyPolicyPage> createState() => _PrivacyPolicyPageState();
}

class _PrivacyPolicyPageState extends ConsumerState<PrivacyPolicyPage> {
  String _version = AppConfig.agreementVersion;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _loadVersion();
    }
  }

  Future<void> _loadVersion() async {
    final version = await fetchAgreementVersion(
      ref.read(authRepositoryProvider),
      type: AgreementTypes.privacyPolicy,
    );
    if (!mounted) {
      return;
    }
    setState(() => _version = version);
  }

  @override
  Widget build(BuildContext context) {
    return LegalDocumentView(
      title: '隐私政策',
      version: _version,
      effectiveDate: '2026-01-01',
      sections: const [
        LegalSection('一、我们收集的信息', [
          '账号信息：您登录时提供的手机号。手机号在界面与日志中均以脱敏形式（如 138****8000）展示。',
          '登录凭证：用于维持登录态的 Access Token 与 Refresh Token。'
              'Refresh Token 仅保存在您的设备安全存储中，服务端只保存其散列值。',
          '设备信息：由 App 生成的一串随机设备标识与设备名称，用于多端登录管理与安全风控，'
              '不包含通讯录、位置、相册等任何个人信息。',
          '日志信息：接口访问时间、结果与请求标识（requestId），用于故障排查与安全审计。',
        ]),
        LegalSection('二、我们如何使用信息', [
          '用于完成账号注册、登录、密码设置与找回；用于短信验证码的发送与频次限制；'
              '用于识别异常登录、保障账号安全；用于按法律法规要求留存协议同意记录。',
        ]),
        LegalSection('三、信息的存储与保护', [
          '手机号、协议确认记录存储于中国大陆境内的服务器；密码采用 BCrypt 单向散列保存，我们无法还原您的密码。',
          '短信验证码与 Refresh Token 在数据库中仅保存散列值，明文不会落库。',
          '我们通过访问控制、传输加密（生产环境启用 HTTPS）等措施保护您的信息。',
        ]),
        LegalSection('四、信息的共享与披露', [
          '除以下情形外，我们不会向第三方共享您的个人信息：获得您的明确同意；'
              '为完成短信下发而委托的短信服务商（仅提供手机号）；法律法规要求或司法机关依法要求。',
        ]),
        LegalSection('五、您的权利', [
          '您可以随时查看账号信息、修改密码、退出登录；如需注销账号或删除个人信息，可通过意见反馈联系我们。',
        ]),
        LegalSection('六、未成年人保护', [
          '本平台服务面向成年人。若您为未成年人，请在监护人陪同下阅读本政策并使用本平台服务。',
        ]),
        LegalSection('七、政策更新', [
          '本政策更新后，我们会在您登录时提示最新版本；重大变更将以显著方式通知您。',
        ]),
        LegalSection('八、联系我们', [
          '如对本政策有任何疑问或投诉，可通过 App 内"意见反馈"与我们联系，我们将在 15 个工作日内答复。',
        ]),
      ],
    );
  }
}
