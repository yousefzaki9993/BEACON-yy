import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:beacon/presentation/widgets/AppBarTop.dart';
import 'package:beacon/presentation/widgets/NavigationBarBottom.dart';
import 'package:beacon/presentation/widgets/FloatingVoiceButton.dart';

import 'chat.dart';

import '../../viewmodels/p2p_viewmodel.dart';
import '../../viewmodels/fall_detection_viewmodel.dart';
import '../../viewmodels/ProfileViewModel.dart';

import '../../main.dart';

class NetworkDashboardPage extends StatefulWidget {
  final bool isHost;

  const NetworkDashboardPage({
    super.key,
    required this.isHost,
  });

  @override
  State<NetworkDashboardPage> createState() => _NetworkDashboardPageState();
}

class _NetworkDashboardPageState extends State<NetworkDashboardPage> {
  final Map<String, bool> _peerFallStatus = {};
  final Map<String, Timer> _peerFallTimers = {};
  bool _initialProfileSent = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final p2pVM = context.read<P2PViewModel>();
      final fallVM = context.read<FallDetectionViewModel>();
      final profileVM = context.read<ProfileViewModel>();

      await profileVM.loadProfile();
      await fallVM.initialize(p2pVM);

      p2pVM.onRequestProfileRebroadcast = () async {
        await _broadcastProfileImage(p2pVM, profileVM);
      };

      p2pVM.addListener(() => _onP2PUpdate(p2pVM));
    });
  }

  Future<void> _broadcastProfileImage(
      P2PViewModel p2pVM, ProfileViewModel profileVM) async {
    Uint8List? bytes;

    if (profileVM.pickedImageFile != null) {
      bytes = await profileVM.pickedImageFile!.readAsBytes();
    } else if (profileVM.profile != null &&
        profileVM.profile!.imagePath.isNotEmpty) {
      final f = File(profileVM.profile!.imagePath);
      if (await f.exists()) {
        bytes = await f.readAsBytes();
      }
    }

    if (bytes == null) return;

    final name = profileVM.profile?.name ?? '';
    await p2pVM.sendProfileImage(bytes, name);
  }

  void _onP2PUpdate(P2PViewModel p2pVM) {
    _checkForFallInLastMessages(p2pVM);
    _trySendInitialProfileImage(p2pVM);
  }

  Future<void> _trySendInitialProfileImage(P2PViewModel p2pVM) async {
    if (_initialProfileSent) return;
    if (!p2pVM.isActive) return;
    if (p2pVM.myId == 'unknown-device') return;
    if (p2pVM.peers.isEmpty) return;

    final profileVM = context.read<ProfileViewModel>();
    await _broadcastProfileImage(p2pVM, profileVM);
    _initialProfileSent = true;
  }

  void _checkForFallInLastMessages(P2PViewModel p2pVM) {
    bool changed = false;

    p2pVM.lastMessages.forEach((peerId, msg) {
      if (msg == null) return;
      if (msg.senderDeviceId == p2pVM.myId) return;

      if (msg.content.contains("FALL_DETECTED") &&
          _peerFallStatus[peerId] != true) {
        _peerFallStatus[peerId] = true;
        changed = true;

        _peerFallTimers[peerId]?.cancel();
        _peerFallTimers[peerId] = Timer(const Duration(minutes: 1), () {
          if (mounted) {
            setState(() {
              _peerFallStatus[peerId] = false;
            });
          }
          _peerFallTimers.remove(peerId);
        });
      }
    });

    if (changed && mounted) setState(() {});
  }

  @override
  void dispose() {
    final p2pVM = context.read<P2PViewModel>();
    p2pVM.onRequestProfileRebroadcast = null;
    for (final timer in _peerFallTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  Widget _peerAvatar(P2PViewModel p2pVM, String peerId, bool isHost) {
    final imageBytes = p2pVM.peerProfileImages[peerId];
    if (imageBytes != null) {
      return CircleAvatar(
        radius: 24,
        backgroundImage: MemoryImage(imageBytes),
      );
    }
    final peer = p2pVM.peers.firstWhere(
          (p) => p.id == peerId,
      orElse: () => p2pVM.peers.first,
    );
    final displayName = p2pVM.peerProfileNames[peerId] ?? peer.username;
    final initial =
    displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 24,
      backgroundColor: isHost ? Colors.orange : Colors.red,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p2pVM = context.watch<P2PViewModel>();
    final profileVM = context.watch<ProfileViewModel>();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBarTop(title: "Network Dashboard"),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Connected: ${p2pVM.peers.length} Devices",
                  style: const TextStyle(color: Colors.white),
                ),
                if (profileVM.profile != null)
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: const Color(0xFF1E1E1E),
                        backgroundImage: profileVM.pickedImageFile != null
                            ? FileImage(profileVM.pickedImageFile!)
                            : (profileVM.profile!.imagePath.isNotEmpty
                            ? FileImage(
                            File(profileVM.profile!.imagePath))
                            : const AssetImage("assets/pp.png"))
                        as ImageProvider,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        profileVM.profile!.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Network Status: ${p2pVM.connectionStatus}",
              style: const TextStyle(color: Colors.green),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: p2pVM.peers.length,
                itemBuilder: (context, i) {
                  final p = p2pVM.peers[i];
                  final bool isFallDetected = _peerFallStatus[p.id] == true;
                  final displayName =
                      p2pVM.peerProfileNames[p.id] ?? p.username;

                  final lastMsgObj = p2pVM.lastMessages[p.id];
                  String lastSeenText = "Never";
                  if (lastMsgObj != null) {
                    final dt = DateTime.parse(lastMsgObj.timestamp);
                    final diff = DateTime.now().difference(dt);
                    if (diff.inMinutes < 1) {
                      lastSeenText = "Just now";
                    } else if (diff.inMinutes < 60) {
                      lastSeenText = "${diff.inMinutes}m ago";
                    } else {
                      lastSeenText = "${diff.inHours}h ago";
                    }
                  }

                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(10),
                      border: isFallDetected
                          ? Border.all(color: Colors.red, width: 1.5)
                          : null,
                    ),
                    child: ListTile(
                      leading: _peerAvatar(p2pVM, p.id, p.isHost),
                      title: Text(
                        displayName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.isHost ? "Host" : "Client",
                            style: const TextStyle(color: Colors.grey),
                          ),
                          Text(
                            "Last seen: $lastSeenText",
                            style: const TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                isFallDetected
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle_outline,
                                size: 14,
                                color: isFallDetected
                                    ? Colors.red
                                    : Colors.green,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "AI Status: ${isFallDetected ? 'Fall Detected' : 'Normal'}",
                                style: TextStyle(
                                  color: isFallDetected
                                      ? Colors.red
                                      : Colors.green,
                                  fontSize: 12,
                                  fontWeight: isFallDetected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      trailing: const Icon(
                        Icons.chat_bubble_outline,
                        color: Colors.red,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChattingPage(
                              target: p,
                              isHost: widget.isHost,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.7,
              child: ElevatedButton(
                key: const Key('Broadcast_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _showBroadcastDialog(context),
                child: const Text(
                  "Send Broadcast Message",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Floatingvoicebutton(
        centre: false,
        onVoiceAction: (action) {
          if (action == "broadcast") _showBroadcastDialog(context);
        },
      ),
      bottomNavigationBar: NavigationBarBottom(currentIndex: 0),
    );
  }

  void _showBroadcastDialog(BuildContext context) {
    final TextEditingController msgController = TextEditingController();
    final TextEditingController newMsgController = TextEditingController();
    final p2pVM = context.read<P2PViewModel>();
    final appState = context.read<MyAppState>();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Broadcast Message",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      const Text("Shortcuts (Long press to delete)",
                          style:
                          TextStyle(color: Colors.grey, fontSize: 12)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: appState.predefinedMessages.map((text) {
                          return GestureDetector(
                            onLongPress: () async {
                              await appState.deletePredefinedMessage(text);
                              setDialogState(() {});
                            },
                            child: ActionChip(
                              backgroundColor: Colors.red.withOpacity(0.2),
                              label: Text(text,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                              onPressed: () => msgController.text = text,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: newMsgController,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 13),
                              decoration: const InputDecoration(
                                hintText: "Add new shortcut...",
                                hintStyle: TextStyle(color: Colors.grey),
                                isDense: true,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle,
                                color: Colors.green),
                            onPressed: () async {
                              if (newMsgController.text.trim().isNotEmpty) {
                                await appState.addPredefinedMessage(
                                    newMsgController.text.trim());
                                newMsgController.clear();
                                setDialogState(() {});
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(color: Colors.grey),
                      TextField(
                        controller: msgController,
                        maxLines: 3,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: "Type your message...",
                          hintStyle: const TextStyle(color: Colors.grey),
                          filled: true,
                          fillColor: Colors.black,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Cancel",
                                style: TextStyle(color: Colors.grey)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () async {
                              final msg = msgController.text.trim();
                              if (msg.isEmpty) return;
                              await p2pVM.sendBroadcastMessage(
                                  msg, p2pVM.myId);
                              Navigator.pop(context);
                            },
                            child: const Text("Send",
                                style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}