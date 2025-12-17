import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'peer.dart';
import 'chat.dart';

class NetworkDashboardPage extends StatefulWidget {
  final bool isHost;
  const NetworkDashboardPage({super.key, required this.isHost});

  @override
  State<NetworkDashboardPage> createState() => _NetworkDashboardPageState();
}

class _NetworkDashboardPageState extends State<NetworkDashboardPage> {
  final FlutterP2pHost host = FlutterP2pHost();
  final FlutterP2pClient client = FlutterP2pClient();

  List<BleDiscoveredDevice> discoveredHosts = [];
  List<Peer> peers = [];

  String myName = '';
  String? connectedHost;
  bool registered = false;
  bool isScanning = false;

  StreamSubscription<String>? sub;
  Timer? _handshakeTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    sub?.cancel();
    _handshakeTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();

    await host.initialize();
    await client.initialize();

    if (widget.isHost) {
      myName = 'HOST';
      await host.createGroup(advertise: true);
      sub = host.streamReceivedTexts().listen(_onMessage);
    } else {
      myName = 'Client-${DateTime.now().millisecondsSinceEpoch % 10000}';
      setState(() => isScanning = true);
      client.startScan((d) {
        setState(() {
          discoveredHosts = d;
          isScanning = false;
        });
      });
      sub = client.streamReceivedTexts().listen(_onMessage);
    }
  }

  void _onMessage(String msg) {
    final p = msg.split('|');
    final type = p[0];

    if (type == 'HANDSHAKE' && widget.isHost) {
      final name = p[1];
      if (name == 'HOST') return;

      if (!peers.any((e) => e.name == name)) {
        setState(() => peers.add(Peer(name)));
        _showNotification('New client connected: $name');
      }

      host.broadcastText('HANDSHAKE_ACK|HOST|$name|');
      _broadcastPeers();
    }

    if (type == 'HANDSHAKE_ACK' && !widget.isHost) {
      if (p[2] == myName) {
        registered = true;
        connectedHost = p[1];
        _handshakeTimer?.cancel();

        if (!peers.any((e) => e.name == connectedHost)) {
          setState(() => peers.insert(0, Peer(connectedHost!)));
        }
        _showNotification('Connected to host successfully');
      }
    }

    if (type == 'CLIENT_LIST' && !widget.isHost) {
      final list = p[3];
      setState(() {
        peers = [
          if (connectedHost != null) Peer(connectedHost!),
          ...list.isEmpty
              ? []
              : list
              .split(',')
              .where((e) => e != myName)
              .map((e) => Peer(e))
        ];
      });
    }

    if (type == 'CHAT_REQUEST') {
      final from = p[1];
      final to = p[2];
      if (to == myName) _showChatRequest(from);
    }

    if (type == 'CHAT_ACCEPT') {
      if (p[2] == myName) _openChat(p[1]);
    }
  }

  void _broadcastPeers() {
    final list = peers.map((e) => e.name).join(',');
    host.broadcastText('CLIENT_LIST|HOST|ALL|$list');
  }

  void _sendHandshake() {
    if (registered) return;
    client.broadcastText('HANDSHAKE|$myName|HOST|');
  }

  Future<void> _connectToHost(BleDiscoveredDevice d) async {
    await client.connectWithDevice(d);
    setState(() => isScanning = true);

    _handshakeTimer?.cancel();
    _handshakeTimer = Timer.periodic(const Duration(seconds: 2), (t) {
      if (registered) {
        t.cancel();
        setState(() => isScanning = false);
      } else {
        _sendHandshake();
      }
    });
  }

  void _showNotification(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[800],
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showChatRequest(String from) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A0000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Chat Request',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '$from wants to chat with you',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
            ),
            child: const Text('Reject'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              final msg = 'CHAT_ACCEPT|$myName|$from|';
              widget.isHost
                  ? host.broadcastText(msg)
                  : client.broadcastText(msg);
              _openChat(from);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Accept',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _openChat(String peer) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChattingPage(
          peer: peer,
          myName: myName,
          isHost: widget.isHost,
          host: host,
          client: client,
        ),
      ),
    );
  }

  void _startScan() {
    if (!widget.isHost) {
      setState(() => isScanning = true);
      client.startScan((d) {
        setState(() {
          discoveredHosts = d;
          isScanning = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromARGB(255, 14, 15, 19),
                Color(0xFF1A0000),
              ],
            ),
          ),
          child: Column(
            children: [
              // App Bar
              _buildAppBar(),

              // Status Card
              _buildStatusCard(),

              // Nearby Hosts Section (for clients only)
              if (!widget.isHost)
                SizedBox(
                  height: 130,
                  child: _buildNearbyHostsSection(),
                ),

              // Network Members Section
              Expanded(child: _buildNetworkSection()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'BEACON NETWORK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                widget.isHost ? 'Host Dashboard' : 'Client Dashboard',
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.red),
            ),
            child: Text(
              myName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Network Status',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: registered || widget.isHost
                          ? Colors.green
                          : Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    registered || widget.isHost
                        ? 'Connected'
                        : 'Searching',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'Active Peers',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${peers.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNearbyHostsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Available Hosts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: _startScan,
                icon: Icon(
                  isScanning ? Icons.refresh : Icons.search,
                  color: Colors.red,
                  size: 18,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: 'Scan for hosts',
              ),
            ],
          ),
        ),
        Expanded(
          child: discoveredHosts.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi_find,
                  color: Colors.white30,
                  size: 28,
                ),
                const SizedBox(height: 6),
                Text(
                  isScanning ? 'Scanning...' : 'No hosts found',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          )
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: discoveredHosts.length,
            itemBuilder: (context, index) {
              final hostDevice = discoveredHosts[index];
              return _buildHostCard(hostDevice, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHostCard(BleDiscoveredDevice hostDevice, int index) {
    String deviceName = hostDevice.deviceName ?? 'Unknown Host';

    String shortName = deviceName.length > 10
        ? '${deviceName.substring(0, 8)}...'
        : deviceName;

    return Container(
      width: 140,
      height: 100,
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2A0F0F),
            Color(0xFF1A0000),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.router,
                color: Colors.red,
                size: 14,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  shortName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 1),
          Text(
            'Tap to connect',
            style: TextStyle(
              color: Colors.green[300],
              fontSize: 9,
            ),
          ),
          const SizedBox(height:5 ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _connectToHost(hostDevice),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                minimumSize: const Size(0, 24),
              ),
              child: const Text(
                'Connect',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(
            widget.isHost ? 'Connected Clients' : 'Network Members',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: peers.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    widget.isHost
                        ? Icons.people_outline
                        : Icons.devices_other,
                    color: Colors.white30,
                    size: 36,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      widget.isHost
                          ? 'Waiting for clients...'
                          : 'No members in network',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.all(6),
              itemCount: peers.length,
              itemBuilder: (context, index) {
                return _buildPeerCard(peers[index]);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeerCard(Peer peer) {
    final isHostPeer = peer.name == 'HOST' || peer.name == connectedHost;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E).withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isHostPeer ? Colors.red.withOpacity(0.5) : Colors.transparent,
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        leading: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isHostPeer ? Colors.red.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            isHostPeer ? Icons.router : Icons.person,
            color: isHostPeer ? Colors.red : Colors.blue,
            size: 16,
          ),
        ),
        title: Text(
          peer.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
            fontSize: 12,
          ),
        ),
        subtitle: Text(
          isHostPeer ? 'Network Host' : 'Network Peer',
          style: TextStyle(
            color: isHostPeer ? Colors.red : Colors.blue,
            fontSize: 10,
          ),
        ),
        trailing: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: IconButton(
            onPressed: () {
              final msg = 'CHAT_REQUEST|$myName|${peer.name}|';
              widget.isHost
                  ? host.broadcastText(msg)
                  : client.broadcastText(msg);
            },
            icon: const Icon(
              Icons.chat_bubble_outline,
              color: Colors.red,
              size: 14,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: 'Start Chat',
          ),
        ),
      ),
    );
  }
}