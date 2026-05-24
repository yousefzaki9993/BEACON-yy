import 'dart:typed_data';
import '../data/EncryptedMessageModel.dart';

class IntegrityService {
  static final IntegrityService _instance = IntegrityService._internal();
  factory IntegrityService() => _instance;
  IntegrityService._internal();

  static const int _replayWindowMs = 30000;
  static const int _maxSeenMessages = 500;

  final Set<String> _seenMessageIds = {};

  bool verify(EncryptedMessageModel model) {
    if (!_verifyTimestamp(model.timestamp)) return false;
    if (!_verifyReplay(model.messageId)) return false;
    return true;
  }

  bool _verifyTimestamp(int timestamp) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final diff = (now - timestamp).abs();
    return diff <= _replayWindowMs;
  }

  bool _verifyReplay(String messageId) {
    if (_seenMessageIds.contains(messageId)) return false;
    if (_seenMessageIds.length >= _maxSeenMessages) {
      _seenMessageIds.clear();
    }
    _seenMessageIds.add(messageId);
    return true;
  }

  void reset() {
    _seenMessageIds.clear();
  }
}