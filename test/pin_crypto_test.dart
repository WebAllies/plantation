import 'package:flutter_test/flutter_test.dart';
import 'package:iot_aqua_app/core/security/pin_crypto.dart';

void main() {
  group('PinCrypto', () {
    test('hash and verify succeed for valid pin', () async {
      final crypto = PinCrypto();
      final bundle = await crypto.hashPin('123456');

      final ok = await crypto.verifyPin(
        pin: '123456',
        expectedHashBase64: bundle.hashBase64,
        saltBase64: bundle.saltBase64,
      );

      expect(ok, isTrue);
    });

    test('verify fails for wrong pin', () async {
      final crypto = PinCrypto();
      final bundle = await crypto.hashPin('123456');

      final ok = await crypto.verifyPin(
        pin: '654321',
        expectedHashBase64: bundle.hashBase64,
        saltBase64: bundle.saltBase64,
      );

      expect(ok, isFalse);
    });

    test('constantTimeEquals handles different lengths', () {
      final crypto = PinCrypto();
      expect(crypto.constantTimeEquals('AA==', 'AAAA'), isFalse);
    });
  });
}
