import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/features/auth/data/qr_login_models.dart';

void main() {
  group('parseQrLoginToken', () {
    test('从网页二维码链接里取出票据', () {
      const token = 'a1b2c3d4e5f6a7b8c9d0a1b2c3d4e5f6';
      // 正式载荷：App 专用 scheme，通用扫码器不会把它当网页打开。
      expect(parseQrLoginToken('juyunce://qr-login?t=$token'), token);
      // 兼容网页形态，便于以后换成通用链接而不必升级 App。
      expect(
        parseQrLoginToken('https://script.example.com/qr-login?t=$token'),
        token,
      );
      expect(
        parseQrLoginToken('http://localhost:8080/qr-login?t=$token'),
        token,
      );
    });

    test('不是扫码登录链接的一律不认', () {
      expect(parseQrLoginToken(null), isNull);
      expect(parseQrLoginToken(''), isNull);
      expect(parseQrLoginToken('just some text'), isNull);
      // 其他站点路径、其他 scheme host、缺少票据参数
      expect(parseQrLoginToken('https://example.com/other?t=abcdefghijklmnopqrst'), isNull);
      expect(parseQrLoginToken('https://script.example.com/qr-login'), isNull);
      expect(parseQrLoginToken('juyunce://other?t=abcdefghijklmnopqrst'), isNull);
      // 票据长度不符合服务端口径时直接丢弃（过短不可能是真票据）
      expect(parseQrLoginToken('juyunce://qr-login?t=short'), isNull);
    });
  });

  group('QrScanTarget', () {
    test('登录端与设备文案', () {
      final creator = QrScanTarget.fromJson({
        'portal': 'creator',
        'browser': 'Chrome 130',
        'os': 'Windows 11',
        'status': 'SCANNED',
      });
      expect(creator.portalLabel, contains('创作者'));
      expect(creator.deviceLabel, 'Chrome 130 · Windows 11');

      final enterprise = QrScanTarget.fromJson({'portal': 'enterprise'});
      expect(enterprise.portalLabel, contains('企业端'));
      // 服务端未解析出浏览器时不能显示空字符串。
      expect(enterprise.deviceLabel, '未知设备');

      // 未知 portal 兜底为创作者端，不抛异常。
      expect(QrScanTarget.fromJson({'portal': 'weird'}).portalLabel, contains('创作者'));
    });
  });
}
