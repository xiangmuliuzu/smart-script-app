import 'package:flutter_test/flutter_test.dart';
import 'package:script_app/core/network/api_client.dart';
import 'package:script_app/features/trade/data/trade_repository.dart';
import '../support/scripted_api.dart';

void main() {
  test('发起支付只取得二维码，确认支付以服务端查询结果为准', () async {
    final api = ScriptedApi();
    api.handle('/trade/order/42/pay', (request) => request.path.endsWith('/confirm')
        ? Envelope.ok({'paid': false, 'sandbox': true})
        : Envelope.ok({'qrCode': 'https://example.test/qr', 'sandbox': true}));
    final repo = TradeRepository(ApiClient(api.buildDio()));
    final result = await repo.appPayOrder(42);
    expect(result['qrCode'], 'https://example.test/qr');
    expect(await repo.confirmSandboxPayment(42), false);
    expect(api.requests.map((request) => request.path), [
      '/trade/order/42/pay', '/trade/order/42/pay/confirm',
    ]);
  });
}
