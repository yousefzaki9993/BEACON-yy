import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../data/EncryptedMessageModel.dart';
import 'KeyManagementService.dart';

class EncryptionService {
  static final EncryptionService _instance = EncryptionService._internal();
  factory EncryptionService() => _instance;
  EncryptionService._internal();

  final AesGcm _algorithm = AesGcm.with256bits();
  final KeyManagementService _keyManagement = KeyManagementService();
  final Uuid _uuid = const Uuid();

  Future<EncryptedMessageModel> encrypt(
      String plainText,
      String senderId,
      ) async {
    final key = await _keyManagement.getOrCreateKey();
    final nonce = _algorithm.newNonce();
    final nonceBytes = Uint8List.fromList(nonce);

    final secretBox = await _algorithm.encrypt(
      utf8.encode(plainText),
      secretKey: key,
      nonce: nonceBytes,
    );

    return EncryptedMessageModel(
      encryptedData: Uint8List.fromList(secretBox.cipherText),
      nonce: nonceBytes,
      authTag: Uint8List.fromList(secretBox.mac.bytes),
      messageId: _uuid.v4(),
      timestamp: DateTime.now().millisecondsSinceEpoch,
      senderId: senderId,
    );
  }

  Future<String?> decrypt(EncryptedMessageModel model) async {
    try {
      final key = await _keyManagement.getOrCreateKey();

      final secretBox = SecretBox(
        model.encryptedData,
        nonce: model.nonce,
        mac: Mac(model.authTag),
      );

      final decrypted = await _algorithm.decrypt(
        secretBox,
        secretKey: key,
      );

      return utf8.decode(decrypted);
    } on SecretBoxAuthenticationError {
      return null;
    } catch (_) {
      return null;
    }
  }

  String serialize(EncryptedMessageModel model) => model.toJson();

  EncryptedMessageModel? deserialize(String payload) {
    try {
      return EncryptedMessageModel.fromJson(payload);
    } catch (_) {
      return null;
    }
  }
}