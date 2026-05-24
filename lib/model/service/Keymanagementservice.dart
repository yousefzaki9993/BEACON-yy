import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyManagementService {
  static final KeyManagementService _instance =
  KeyManagementService._internal();
  factory KeyManagementService() => _instance;
  KeyManagementService._internal();

  static const String _keyStorageKey = 'aes_256_gcm_shared_key';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  SecretKey? _cachedKey;

  Future<SecretKey> getOrCreateKey() async {
    if (_cachedKey != null) return _cachedKey!;

    final stored = await _secureStorage.read(key: _keyStorageKey);

    if (stored != null) {
      final keyBytes = base64Decode(stored);
      _cachedKey = SecretKey(keyBytes);
      return _cachedKey!;
    }

    final algorithm = AesGcm.with256bits();
    final newKey = await algorithm.newSecretKey();
    final keyBytes = await newKey.extractBytes();
    await _secureStorage.write(
      key: _keyStorageKey,
      value: base64Encode(keyBytes),
    );
    _cachedKey = newKey;
    return _cachedKey!;
  }

  Future<void> importKey(Uint8List keyBytes) async {
    await _secureStorage.write(
      key: _keyStorageKey,
      value: base64Encode(keyBytes),
    );
    _cachedKey = SecretKey(keyBytes);
  }

  Future<Uint8List> exportKeyBytes() async {
    final key = await getOrCreateKey();
    final bytes = await key.extractBytes();
    return Uint8List.fromList(bytes);
  }

  void clearCache() {
    _cachedKey = null;
  }
}