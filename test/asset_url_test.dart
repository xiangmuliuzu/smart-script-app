import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/config/app_config.dart';

/// 图片/材料地址解析：公开媒体走远端存储，带签名的合同材料留在签发它的后端。
void main() {
  const api = 'http://10.0.2.2:8080/api/v1';
  const storage = 'https://storage.test';

  String resolve(String raw) =>
      AppConfig.resolveAssetUrl(raw, apiBaseUrl: api, mediaBaseUrl: storage);

  group('public media', () {
    test('ignores the local backend host and uses remote storage', () {
      const path = '/profile/upload/2026-11-17/seal_zhangsanfeng.png';
      for (final raw in [
        path,
        'http://localhost:8080$path',
        'http://10.0.2.2:8080$path',
        'https://www.eyhereal.site/prod-api$path',
      ]) {
        expect(resolve(raw), '$storage$path');
      }
    });

    test('falls back to the api origin when no storage is configured', () {
      expect(
          AppConfig.resolveAssetUrl('/profile/upload/a.png',
              apiBaseUrl: 'https://api.test/api/v1', mediaBaseUrl: ''),
          'https://api.test/profile/upload/a.png');
    });

    test('keeps a query string that came with the resource', () {
      expect(resolve('/profile/upload/a.png?v=2'), '$storage/profile/upload/a.png?v=2');
    });
  });

  group('signed material', () {
    test('stays on the issuing backend with its signature', () {
      const page =
          '/profile/upload/contract/2026/11/c16/u3f9a1b2c_page_0.png?sig=abc&exp=1';
      expect(resolve('http://localhost:8080$page'),
          'http://10.0.2.2:8080$page');
      expect(resolve(page), 'http://10.0.2.2:8080$page');
    });

    test('legacy flat contract directory is guarded too', () {
      expect(resolve('/profile/contract/10/signed.pdf?sig=k'),
          'http://10.0.2.2:8080/profile/contract/10/signed.pdf?sig=k');
    });
  });

  test('non-profile relative paths and external hosts are left alone', () {
    expect(resolve('/material/file.pdf'), 'http://10.0.2.2:8080/material/file.pdf');
    expect(resolve('https://cdn.test/images/a.png'), 'https://cdn.test/images/a.png');
    expect(resolve(''), '');
  });

  test('local absolute urls without a profile anchor keep the api base', () {
    expect(resolve('http://localhost:8080/api/v1/files/x?id=9'),
        'http://10.0.2.2:8080/api/v1/files/x?id=9');
  });
}
