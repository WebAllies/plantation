import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

class PinHashBundle {
  final String hashBase64;
  final String saltBase64;

  const PinHashBundle({required this.hashBase64, required this.saltBase64});
}

class PinCrypto {
  static const int _saltLength = 16;
  static const int _derivedBits = 256;
  static const int _iterations = 100000;

  final Pbkdf2 _pbkdf2 = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _iterations,
    bits: _derivedBits,
  );

  String generateSaltBase64() {
    final random = Random.secure();
    final salt = Uint8List(_saltLength);
    for (var i = 0; i < salt.length; i++) {
      salt[i] = random.nextInt(256);
    }
    return base64Encode(salt);
  }

  Future<String> deriveHashBase64({
    required String pin,
    required String saltBase64,
  }) async {
    final secret = SecretKey(utf8.encode(pin));
    final nonce = base64Decode(saltBase64);
    final key = await _pbkdf2.deriveKey(secretKey: secret, nonce: nonce);
    final bytes = await key.extractBytes();
    return base64Encode(bytes);
  }

  Future<PinHashBundle> hashPin(String pin) async {
    final salt = generateSaltBase64();
    final hash = await deriveHashBase64(pin: pin, saltBase64: salt);
    return PinHashBundle(hashBase64: hash, saltBase64: salt);
  }

  bool constantTimeEquals(String aBase64, String bBase64) {
    final a = base64Decode(aBase64);
    final b = base64Decode(bBase64);
    if (a.length != b.length) return false;

    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= (a[i] ^ b[i]);
    }
    return diff == 0;
  }

  Future<bool> verifyPin({
    required String pin,
    required String expectedHashBase64,
    required String saltBase64,
  }) async {
    final calculated = await deriveHashBase64(pin: pin, saltBase64: saltBase64);
    return constantTimeEquals(calculated, expectedHashBase64);
  }
}
