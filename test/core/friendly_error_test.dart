import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_exception.dart';
import 'package:script_app/core/network/friendly_error.dart';

void main() {
  test('已知业务码映射为中文文案', () {
    expect(FriendlyError.message(ApiException('sms code invalid', code: 40001)),
        '验证码错误，请重新输入');
    expect(FriendlyError.message(ApiException('account disabled', code: 40301)),
        FriendlyError.accountDisabled);
    expect(FriendlyError.message(ApiException('unauthorized', code: 40100)),
        FriendlyError.loginExpired);
    expect(FriendlyError.message(ApiException('', code: 50000)),
        FriendlyError.serverBusy);
  });

  test('后端安全中文优先保留', () {
    expect(
        FriendlyError.message(
            ApiException('姓名长度不正确，请检查后重试', code: 40000)),
        '姓名长度不正确，请检查后重试');
    expect(FriendlyError.message(ApiException('自定义中文提示', code: 99999)),
        '自定义中文提示');
  });

  test('英文或技术文案回落为中文兜底', () {
    expect(FriendlyError.message(ApiException('invalid request', code: 40000)),
        FriendlyError.param);
    expect(FriendlyError.message(ApiException('HTTP 404', code: 40000)),
        FriendlyError.param);
    expect(FriendlyError.message(Exception('Failed to fetch')),
        FriendlyError.generic);
    expect(FriendlyError.sanitize('Some English', fallback: '兜底'), '兜底');
  });

  test('HTTP 状态兜底', () {
    expect(FriendlyError.message(ApiException('', code: null), status: 404),
        FriendlyError.notFound);
    expect(FriendlyError.message(ApiException('', code: null), status: 503),
        FriendlyError.serverBusy);
    expect(FriendlyError.message(ApiException('', code: null), status: 429),
        FriendlyError.tooFrequent);
  });
}
