import 'dart:convert';
import 'dart:typed_data';

class EncryptedMessageModel {
  final Uint8List encryptedData;
  final Uint8List nonce;
  final Uint8List authTag;
  final String messageId;
  final int timestamp;
  final String senderId;

  EncryptedMessageModel({
    required this.encryptedData,
    required this.nonce,
    required this.authTag,
    required this.messageId,
    required this.timestamp,
    required this.senderId,
  });

  Map<String, dynamic> toMap() => {
    'encryptedData': base64Encode(encryptedData),
    'nonce': base64Encode(nonce),
    'authTag': base64Encode(authTag),
    'messageId': messageId,
    'timestamp': timestamp,
    'senderId': senderId,
  };

  factory EncryptedMessageModel.fromMap(Map<String, dynamic> map) =>
      EncryptedMessageModel(
        encryptedData: base64Decode(map['encryptedData']),
        nonce: base64Decode(map['nonce']),
        authTag: base64Decode(map['authTag']),
        messageId: map['messageId'],
        timestamp: map['timestamp'],
        senderId: map['senderId'],
      );

  String toJson() => jsonEncode(toMap());

  factory EncryptedMessageModel.fromJson(String source) =>
      EncryptedMessageModel.fromMap(jsonDecode(source));
}