import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beacon/model/data/UserProfile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'dart:async';
import 'package:collection/collection.dart';

import '../model/data/Resource.dart';
import '../model/data/Message.dart';
import '../model/data/Device.dart';
import '../model/service/notification_service.dart';
import '../model/service/p2p_service.dart';
import '../model/service/connected_device_service.dart';
import '../model/service/message_service.dart';
import '../model/service/resource_service.dart';
import '../model/service/user_profile_service.dart';
import '../model/Device.helper.dart';
import '../model/mapper/device_mapper.dart';
import '../model/service/Encryptionservice.dart';
import '../model/service/Integrityservice.dart';
import '../model/service/KeyManagementService.dart';
import 'ProfileViewModel.dart';

class P2PViewModel extends ChangeNotifier {

  String myId = 'unknown-device';
  final P2PService _service = P2PService();
  final ConnectedDeviceDao _deviceDao = ConnectedDeviceDao();
  final MessageDao _messageDao = MessageDao();
  final UserProfileDao userProfileDao = UserProfileDao();
  final ResourceDao _resourceDao = ResourceDao();
  final EncryptionService _encryption = EncryptionService();
  final IntegrityService _integrity = IntegrityService();
  final KeyManagementService _keyManagement = KeyManagementService();

  get service => _service;

  bool isHost = false;
  bool _keyReady = false;
  List<P2pClientInfo> peers = [];
  String? activePeerId;
  List<Message> currentChatMessages = [];
  Map<String, Message?> lastMessages = {};
  String connectionStatus = "Disconnected";
  bool isActive = false;
  bool isConnecting = false;
  Map<String, Uint8List> peerProfileImages = {};
  Map<String, String> peerProfileNames = {};

  StreamSubscription? _msgSub;
  StreamSubscription? _peerSub;
  StreamSubscription? _stateSub;
  String owner = "";

  Future<void> Function()? onRequestProfileRebroadcast;
  VoidCallback? onResourcesChanged;

  Future<void> initP2P(BuildContext context, bool newHost) async {
    if (isActive && !isHost && !newHost) return;
    if (isActive) await disconnect(isHost);

    _service.ensurePermissions();
    _service.ensureServices();

    if (!context.mounted) return;

    startP2P(newHost);
  }

  void startP2P(bool isHost) async {
    this.isHost = isHost;

    if (isHost) {
      await _keyManagement.getOrCreateKey();
      _keyReady = true;
      await _service.initHost();
      _setupHostStreams();
      await _service.hostInterface.createGroup(advertise: true);
    } else {
      _keyReady = false;
      await _service.initClient();
      _setupClientStreams();
      _startAutoScan();
    }
  }

  void _setupHostStreams() {
    _stateSub = _service.hostInterface.streamHotspotState().listen((state) {
      isActive = state.isActive;
      connectionStatus =
      state.isActive ? "Hosting: ${state.ssid}" : "Hosting...";
      notifyListeners();
    });
    _listenForPeers(true);
    _listenForMessages(true);
  }

  void _setupClientStreams() {
    _stateSub = _service.clientInterface.streamHotspotState().listen((state) {
      isActive = state.isActive;
      connectionStatus = state.isActive ? "Connected" : "Disconnected";
      if (state.isActive) isConnecting = false;
      notifyListeners();
    });
    _listenForPeers(false);
    _listenForMessages(false);
  }

  void _listenForPeers(bool isHost) {
    final listEquals = const IterableEquality().equals;

    _peerSub = _service
        .getPeerStream(isHost)
        .distinct((prev, next) => listEquals(prev, next))
        .listen((list) async {
      if (list.length > peers.length) {
        final joiner = list.firstWhere(
              (n) => !peers.any((p) => p.id == n.id),
        );
        NotificationService.showAlert(
            "Network Update",
            "${joiner.username} has joined.",
            'client_channel');

        if (isHost) {
          await _sendIdAndKey(joiner.id);
          await Future.delayed(const Duration(milliseconds: 500));
          if (onRequestProfileRebroadcast != null) {
            await onRequestProfileRebroadcast!();
          }
          await sendBroadcast("REQPROFILE|all");
        }

        if (peers.isEmpty && !isHost) {
          sendRawMessage("ID|${joiner.id}", joiner.id, isHost);
        }
      } else if (list.length < peers.length) {
        final leaver = peers.firstWhere(
              (p) => !list.any((n) => n.id == p.id),
          orElse: () => peers.first,
        );
        NotificationService.showAlert(
            "Network Update",
            "${leaver.username} has left the network.",
            'client_channel');

        final leaverName = peerProfileNames[leaver.id] ?? leaver.username;
        if (leaverName.isNotEmpty) {
          await _resourceDao.deleteResourcesByOwner(leaverName);
          await sendBroadcast("DELETE_OWNER|$leaverName");
          onResourcesChanged?.call();
          notifyListeners();
        }

        peerProfileImages.remove(leaver.id);
        peerProfileNames.remove(leaver.id);
      }

      peers = list;
      notifyListeners();
    });
  }

  Future<void> _sendIdAndKey(String clientId) async {
    final keyBytes = await _keyManagement.exportKeyBytes();
    final keyBase64 = base64Encode(keyBytes);
    final msg = "IDKEY|$clientId|$keyBase64";
    await _service.hostInterface.sendTextToClient(msg, clientId);
  }

  Future<void> sendRawMessage(
      String text, String targetId, bool isHost) async {
    if (isHost) {
      await _service.hostInterface.sendTextToClient(text, targetId);
    } else {
      await _service.clientInterface.sendTextToClient(text, targetId);
    }
  }

  void _listenForMessages(bool isHost) {
    _msgSub = _service.getMessageStream(isHost).listen((msg) async {

      if (msg.startsWith("REQ:")) {
        final UserProfile? currentUser = await userProfileDao.getUserProfile();
        if (currentUser?.name == msg.split(":")[1]) {
          NotificationService.showAlert(
              "Resource Request from ${msg.split(":")[2]}",
              msg.substring(4),
              'resource_channel');
        }

      } else if (msg.startsWith("DELETE_OWNER|")) {
        final ownerName = msg.substring(13);
        await _resourceDao.deleteResourcesByOwner(ownerName);
        onResourcesChanged?.call();
        notifyListeners();

      } else if (msg.startsWith("REQPROFILE|")) {
        if (onRequestProfileRebroadcast != null) {
          await onRequestProfileRebroadcast!();
        }

      } else if (msg.startsWith("IDKEY|")) {
        final parts = msg.split('|');
        if (parts.length >= 3) {
          final realId = parts[1];
          final keyBase64 = parts[2];
          myId = realId;
          try {
            final keyBytes = base64Decode(keyBase64);
            await _keyManagement.importKey(keyBytes);
            _keyReady = true;
            debugPrint("[KEY] Shared key imported successfully");
          } catch (e) {
            debugPrint("[KEY] Failed to import shared key: $e");
          }
          await sendJoinPing();
        }

      } else if (msg.startsWith("PROFILE_IMG|")) {
        final parts = msg.split('|');
        if (parts.length >= 4) {
          final peerId = parts[1];
          final peerName = parts[2];
          final base64Data = parts.sublist(3).join('|');
          try {
            final bytes = base64Decode(base64Data);
            peerProfileImages[peerId] = bytes;
            peerProfileNames[peerId] = peerName;
            notifyListeners();
          } catch (e) {
            debugPrint("[PROFILE_IMG_RECEIVE_ERROR] $e");
          }
        }

      } else if (msg.startsWith("PR|")) {
        final parts = msg.split('|');
        String clientId = parts[1];
        String resources = parts.sublist(2).join('|');
        if (isHost) SyncToClient(clientId, resources);

      } else if (msg.startsWith("ID|")) {
        final parts = msg.split('|');
        myId = parts[1];
        if (!isHost) await sendJoinPing();

      } else if (msg.startsWith("SYNC|")) {
        final data = jsonDecode(msg.substring(5));
        for (final r in data) {
          await _resourceDao.upsertResource(Resource.fromMap(r));
        }
        onResourcesChanged?.call();
        notifyListeners();

      } else if (msg.startsWith("DELETE_RES|")) {
        try {
          final int resourceId = int.parse(msg.substring(11));
          await _resourceDao.deleteResource(resourceId);
          onResourcesChanged?.call();
          NotificationService.showAlert(
              "Resource Synced",
              "Resource has been deleted.",
              'resource_channel');
        } catch (e) {
          debugPrint("[ERROR] Failed to parse resource ID for deletion: $e");
        }

      } else if (msg.startsWith("ENC|")) {
        if (!_keyReady) {
          debugPrint("[DECRYPT] Key not ready yet — dropping message");
          return;
        }

        final payload = msg.substring(4);
        final model = _encryption.deserialize(payload);

        if (model == null) {
          debugPrint("[DECRYPT] Failed to deserialize message");
          return;
        }

        if (!_integrity.verify(model)) {
          debugPrint("[INTEGRITY] Message rejected — replay or timestamp invalid");
          return;
        }

        final plainText = await _encryption.decrypt(model);

        if (plainText == null) {
          debugPrint("[DECRYPT] Auth tag verification failed — message tampered");
          return;
        }

        final senderId = model.senderId;

        Message newMessage = Message(
          senderDeviceId: senderId,
          receiverDeviceId: myId,
          messageType: "text",
          content: plainText,
          timestamp: DateTime.now().toIso8601String(),
          delivered: 1,
        );

        _messageDao.insertMessage(newMessage);
        updateLastMessageSummary(senderId);

        if (activePeerId != null) {
          if (senderId == activePeerId ||
              newMessage.receiverDeviceId == "ALL") {
            await refreshMessages(activePeerId!);
          }
        }

        NotificationService.showAlert("New Message", plainText, 'chat_channel');

      } else {
        List<String> parts = msg.split('|');
        String senderId = parts[0];
        String message = parts.sublist(1).join('|');

        Message newMessage = Message(
          senderDeviceId: senderId,
          receiverDeviceId: myId,
          messageType: "text",
          content: message,
          timestamp: DateTime.now().toIso8601String(),
          delivered: 1,
        );

        _messageDao.insertMessage(newMessage);
        updateLastMessageSummary(senderId);

        if (activePeerId != null) {
          if (senderId == activePeerId ||
              newMessage.receiverDeviceId == "ALL") {
            await refreshMessages(activePeerId!);
          }
        }

        NotificationService.showAlert("New Message", message, 'chat_channel');
      }
    });
  }

  void _startAutoScan() async {
    connectionStatus = "Scanning for networks...";
    notifyListeners();

    await _service.clientInterface.startScan((devices) async {
      if (devices.isNotEmpty && !isActive && !isConnecting) {
        isConnecting = true;
        final target = devices.first;
        connectionStatus = "Auto-joining ${target.deviceName}...";
        notifyListeners();
        await _service.clientInterface.stopScan();
        _service.clientInterface.connectWithDevice(target);
        isConnecting = false;
      }
    });
  }

  Future<void> sendMessage(String text, String targetId, bool isHost) async {
    final isSystem = text.startsWith("ID|") || text.startsWith("REQ:");

    if (isSystem) {
      await sendRawMessage(text, targetId, isHost);
      return;
    }

    final isImage = text.startsWith("IMG_BASE64|");
    final isLocation = text.startsWith("LOC|");

    if (!isImage) {
      if (!_keyReady) {
        debugPrint("[ENCRYPT] Key not ready — cannot send encrypted message");
        return;
      }

      final encryptedModel = await _encryption.encrypt(text, myId);
      final serialized = _encryption.serialize(encryptedModel);
      final payload = "ENC|$serialized";

      bool ok = false;
      if (isHost) {
        ok = await _service.hostInterface.sendTextToClient(payload, targetId);
      } else {
        ok = await _service.clientInterface.sendTextToClient(payload, targetId);
      }

      if (ok) {
        Message newMessage = Message(
          senderDeviceId: myId,
          receiverDeviceId: targetId,
          messageType: isLocation ? "location" : "text",
          content: text,
          timestamp: DateTime.now().toIso8601String(),
          delivered: 0,
        );
        _messageDao.insertMessage(newMessage);
        await refreshMessages(targetId);
        updateLastMessageSummary(targetId);
      }
    } else {
      final fullText = "$myId|$text";
      if (isHost) {
        await _service.hostInterface.sendTextToClient(fullText, targetId);
      } else {
        await _service.clientInterface.sendTextToClient(fullText, targetId);
      }
    }
  }

  Future<void> sendImageBase64(File imageFile, String targetId) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);
      final payload = "IMG_BASE64|$base64Image";

      await sendMessage(payload, targetId, isHost);

      Message imageMessage = Message(
        senderDeviceId: myId,
        receiverDeviceId: targetId,
        messageType: "image",
        content: payload,
        timestamp: DateTime.now().toIso8601String(),
        delivered: 0,
      );

      await _messageDao.insertMessage(imageMessage);
      await refreshMessages(targetId);
      updateLastMessageSummary(targetId);
      notifyListeners();
    } catch (e) {
      debugPrint("[BASE64_IMAGE_ERROR] $e");
    }
  }

  Future<void> sendProfileImage(Uint8List imageBytes, String name) async {
    try {
      final base64Image = base64Encode(imageBytes);
      final msg = "PROFILE_IMG|$myId|$name|$base64Image";
      await sendBroadcast(msg);
    } catch (e) {
      debugPrint("[PROFILE_IMG_SEND_ERROR] $e");
    }
  }

  Future<List<Message>> getAllSavedMessages() async {
    return await _messageDao.getAll();
  }

  Future<void> refreshMessages(String peerId) async {
    currentChatMessages = await _messageDao.getChatHistory(myId, peerId);
    notifyListeners();
  }

  Future<void> updateLastMessageSummary(String peerId) async {
    final msg = await _messageDao.getLastMessageForPeer(myId, peerId);
    lastMessages[peerId] = msg;
    notifyListeners();
  }

  Future<void> loadChatWithPeer(String peerId) async {
    activePeerId = peerId;
    currentChatMessages = [];
    notifyListeners();
    currentChatMessages = await _messageDao.getChatHistory(myId, peerId);
    notifyListeners();
  }

  void closeChat() {
    activePeerId = null;
    currentChatMessages = [];
    notifyListeners();
  }

  @override
  void dispose() async {
    debugPrint("--------------------------------[DEBUG] Disposing P2PViewModel+++++++++++++++++++++++++++++");
    _msgSub?.cancel();
    _peerSub?.cancel();
    _stateSub?.cancel();
    final UserProfile? currentUser = await userProfileDao.getUserProfile();
    await _resourceDao.ClearResources(currentUser?.name ?? "");
    super.dispose();
  }

  Future<void> disconnect(bool isHost) async {
    final UserProfile? currentUser = await userProfileDao.getUserProfile();
    await _resourceDao.ClearResources(currentUser?.name ?? "");

    if (isHost) {
      await _service.hostInterface.removeGroup();
      await _service.hostInterface.dispose();
    } else {
      await _service.clientInterface.stopScan();
      await _service.clientInterface.disconnect();
      await _service.clientInterface.dispose();
    }

    peers = [];
    peerProfileImages = {};
    peerProfileNames = {};
    isActive = false;
    connectionStatus = "Disconnected";
    isHost = false;
    isConnecting = false;
    _keyReady = false;
    _keyManagement.clearCache();
    _integrity.reset();

    _msgSub?.cancel();
    _peerSub?.cancel();
    _stateSub?.cancel();
    _msgSub = null;
    _peerSub = null;
    _stateSub = null;

    notifyListeners();
  }

  Future<void> SyncToClient(String ClientID, String resources_msg) async {
    try {
      final List<dynamic> decoded = jsonDecode(resources_msg);
      final List<Resource> incomingResources =
      decoded.map((e) => Resource.fromMap(e)).toList();
      for (final resource in incomingResources) {
        await _resourceDao.addResource(resource);
      }
      debugPrint(
          "[HOST] Synced ${incomingResources.length} resources from client $ClientID");
      await sync_broadcast();
    } catch (e, stack) {
      debugPrint("[HOST][ERROR] Failed syncing resources: $e");
      debugPrint(stack.toString());
    }
    notifyListeners();
  }

  Future<void> sync_broadcast() async {
    final List<Resource> localResources = await _resourceDao.getAllResources();
    String msg =
        "SYNC|${jsonEncode(localResources.map((r) => r.toMap()).toList())}";
    sendBroadcast(msg);
  }

  Future<void> sendJoinPing() async {
    final List<Resource> localResources = await _resourceDao.getAllResources();
    final String msg =
        "PR|$myId|${jsonEncode(localResources.map((r) => r.toMap()).toList())}";
    _service.clientInterface.broadcastText(msg);
  }

  Future<void> sendBroadcast(String message) async {
    if (!isActive) return;
    if (isHost) {
      await _service.hostInterface.broadcastText(message);
    } else {
      await _service.clientInterface.broadcastText(message);
    }
  }

  Future<void> broadcastDeleteResource(int resourceId) async {
    final String msg = "DELETE_RES|$resourceId";
    await sendBroadcast(msg);
  }

  Future<void> sendBroadcastMessage(String text, String senderId) async {
    if (!_keyReady) return;

    final encryptedModel = await _encryption.encrypt(text, senderId);
    final serialized = _encryption.serialize(encryptedModel);
    final payload = "ENC|$serialized";

    if (isHost) {
      await _service.hostInterface.broadcastText(payload);
    } else {
      await _service.clientInterface.broadcastText(payload);
    }

    Message newMessage = Message(
      senderDeviceId: senderId,
      receiverDeviceId: "ALL",
      messageType: "broadcast",
      content: text,
      timestamp: DateTime.now().toIso8601String(),
      delivered: 0,
    );

    _messageDao.insertMessage(newMessage);
    await refreshMessages('ALL');
    updateLastMessageSummary('ALL');
  }

  Future<void> requestResource(Resource resource, String name) async {
    await sendBroadcast("REQ:${resource.owner}:$name");
  }
}