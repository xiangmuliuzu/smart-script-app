import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers/app_providers.dart';
import '../data/agreement_versions.dart';
import 'legal_document_view.dart';

/// 用户协议页。
///
/// 版本号来自既有 `GET /auth/agreements`，与登录 / 注册时提交的
/// `agreementAcceptances` 同源，保证「用户看到的版本」与「服务端留痕的版本」一致。
class AgreementPage extends ConsumerStatefulWidget {
  const AgreementPage({super.key});

  @override
  ConsumerState<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends ConsumerState<AgreementPage> {
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
      type: AgreementTypes.userAgreement,
    );
    if (!mounted) {
      return;
    }
    setState(() => _version = version);
  }

  @override
  Widget build(BuildContext context) {
    return LegalDocumentView(
      title: '用户协议',
      version: _version,
      effectiveDate: '2026-01-01',
      sections: const [
        LegalSection('一、协议范围', [
          '本协议是您与智能剧本创作平台（以下简称"本平台"）之间关于使用本平台服务所订立的协议。'
              '您在注册或登录时勾选同意本协议，即表示您已阅读、理解并接受本协议全部条款。',
        ]),
        LegalSection('二、账号注册与安全', [
          '本平台以手机号作为账号唯一标识。您可使用手机号 + 短信验证码登录，未注册的手机号将自动完成注册；'
              '您也可以设置登录密码，通过手机号 + 密码登录。',
          '请妥善保管账号与密码。以您的账号进行的操作视为您本人的行为；如发现账号被他人使用，请立即联系我们。',
        ]),
        LegalSection('三、服务内容', [
          '本平台提供剧本创作辅助、作品展示、版权交易撮合、短剧发行等服务。'
              '部分功能需要登录后方可使用，具体以平台实际提供为准。',
        ]),
        LegalSection('四、用户行为规范', [
          '您承诺上传、发布的内容拥有合法权利或已获得合法授权，不侵犯任何第三方的著作权、商标权等权利。',
          '您不得利用本平台从事违法违规活动，包括但不限于发布违法信息、侵犯他人隐私、恶意刷量等。',
        ]),
        LegalSection('五、内容与知识产权', [
          '您在本平台上传的原创内容，著作权归您所有；您授予本平台为提供服务所必需的展示、存储与推广权利。',
        ]),
        LegalSection('六、服务变更与终止', [
          '本平台可能根据业务需要调整服务内容，并会以适当方式通知您。'
              '您可随时通过"退出登录"停止使用本平台服务。',
        ]),
        LegalSection('七、协议更新', [
          '本协议更新后，我们会在您登录时提示最新版本；继续使用服务即视为接受更新后的协议。',
        ]),
        LegalSection('八、联系我们', [
          '如对本协议有任何疑问，可通过 App 内"意见反馈"与我们联系。',
        ]),
      ],
    );
  }
}
