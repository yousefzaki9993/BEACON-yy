import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

class ChattingPage extends StatefulWidget {
  final String peer;
  final String myName;
  final bool isHost;
  final FlutterP2pHost host;
  final FlutterP2pClient client;

  const ChattingPage({
    super.key,
    required this.peer,
    required this.myName,
    required this.isHost,
    required this.host,
    required this.client,
  });

  @override
  State<ChattingPage> createState() => _ChattingPageState();
}

class _ChattingPageState extends State<ChattingPage> {
  final TextEditingController _textController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<String>? _chatSubscription;
  bool _isRecording = false;
  bool _isVoiceMessageMode = false;

  bool _isMessageForMe({
    required String from,
    required String to,
  }) {
    if (to == widget.myName && from == widget.peer) return true;
    if (from == widget.myName && to == widget.peer) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();

    final stream = widget.isHost
        ? widget.host.streamReceivedTexts()
        : widget.client.streamReceivedTexts();

    _chatSubscription = stream.listen((msg) {
      final p = msg.split('|');
      if (p[0] == 'CHAT_MSG') {
        if (_isMessageForMe(from: p[1], to: p[2])) {
          setState(() => _messages.add({
            'text': p[3],
            'isMe': p[1] == widget.myName,
            'from': p[1],
            'time': DateTime.now(),
            'type': 'text',
          }));
          _scrollToBottom();
        }
      } else if (p[0] == 'VOICE_MSG') {
        if (_isMessageForMe(from: p[1], to: p[2])) {
          setState(() => _messages.add({
            'text': '🎤 Voice message',
            'isMe': p[1] == widget.myName,
            'from': p[1],
            'time': DateTime.now(),
            'type': 'voice',
            'duration': p.length > 4 ? p[4] : '0s',
          }));
          _scrollToBottom();
        }
      }
    });

    // رسالة ترحيب افتراضية
    _messages.add({
      'text': 'You are now connected! Start chatting...',
      'isMe': false,
      'from': 'System',
      'time': DateTime.now(),
      'type': 'system',
    });
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendTextMessage({String? text}) {
    String message = text ?? _textController.text;
    if (message.isEmpty) return;

    final msg = 'CHAT_MSG|${widget.myName}|${widget.peer}|$message';

    widget.isHost ? widget.host.broadcastText(msg) : widget.client.broadcastText(msg);

    setState(() => _messages.add({
      'text': message,
      'isMe': true,
      'from': widget.myName,
      'time': DateTime.now(),
      'type': 'text',
    }));
    _textController.clear();
    _scrollToBottom();
  }

  void _sendVoiceMessage() {
    // محاكاة رسالة صوتية (يمكنك استبدالها بتسجيل حقيقي)
    final duration = '5s'; // مدة افتراضية
    final msg = 'VOICE_MSG|${widget.myName}|${widget.peer}|voice_message|$duration';

    widget.isHost ? widget.host.broadcastText(msg) : widget.client.broadcastText(msg);

    setState(() => _messages.add({
      'text': '🎤 Voice message',
      'isMe': true,
      'from': widget.myName,
      'time': DateTime.now(),
      'type': 'voice',
      'duration': duration,
    }));
    _scrollToBottom();
  }

  void _sendQuickMessage(String text) {
    _sendTextMessage(text: text);
  }

  void _toggleVoiceMode() {
    setState(() {
      _isVoiceMessageMode = !_isVoiceMessageMode;
      _isRecording = false;
    });
  }

  void _startRecording() {
    setState(() => _isRecording = true);
    // محاكاة التسجيل
    Future.delayed(const Duration(seconds: 3), () {
      if (_isRecording) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() {
    setState(() => _isRecording = false);
    _sendVoiceMessage();
  }

  @override
  Widget build(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    double height = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A0000),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.peer,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.isHost ? 'Host' : 'Client',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 12,
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.wifi,
                  color: Colors.green,
                  size: 14,
                ),
                const SizedBox(width: 6),
                const Text(
                  "P2P",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection Status
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  const Color(0xFF1A0000).withOpacity(0.8),
                  const Color(0xFF2A0F0F).withOpacity(0.8),
                ],
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    "Secure P2P Connection • End-to-End Encrypted",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Messages Area
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF0D0D0D),
                    Color(0xFF1A1A1A),
                  ],
                ),
              ),
              child: _messages.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      color: Colors.white30,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Start the conversation",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Send your first message to ${widget.peer}",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  final isMe = message['isMe'] == true;
                  final isSystem = message['type'] == 'system';
                  final isVoice = message['type'] == 'voice';

                  if (isSystem) {
                    return _buildSystemMessage(message);
                  }

                  return _buildMessageBubble(
                    message: message,
                    isMe: isMe,
                    isVoice: isVoice,
                  );
                },
              ),
            ),
          ),

          // Voice Recording Indicator
          if (_isRecording)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.red.withOpacity(0.1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.mic, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  const Text(
                    "Recording... Release to send",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

          // Voice Message Mode
          if (_isVoiceMessageMode && !_isRecording)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A0000).withOpacity(0.5),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _startRecording,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mic, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "Hold to Record Voice Message",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _toggleVoiceMode,
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),

          // Text Input Area
          if (!_isVoiceMessageMode)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.1)),
                ),
              ),
              child: Row(
                children: [
                  // Voice Message Button
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: _toggleVoiceMode,
                      icon: Icon(
                        Icons.mic,
                        color: _isVoiceMessageMode ? Colors.red : Colors.white70,
                      ),
                      tooltip: 'Voice Message',
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Text Field
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A2A),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              style: const TextStyle(color: Colors.white),
                              controller: _textController,
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                hintStyle: TextStyle(color: Colors.white54),
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                              ),
                              onSubmitted: (value) => _sendTextMessage(),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _sendTextMessage(),
                            icon: const Icon(Icons.send, color: Colors.red),
                            tooltip: 'Send',
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),


          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              border: Border(
                top: BorderSide(color: Colors.white.withOpacity(0.1)),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildQuickMessageButton('HELP', Icons.help),
                  const SizedBox(width: 8),
                  _buildQuickMessageButton('LOCATION', Icons.location_on),
                  const SizedBox(width: 8),
                  _buildQuickMessageButton('MEDICAL', Icons.medical_services),
                  const SizedBox(width: 8),
                  _buildQuickMessageButton('OK', Icons.check),
                  const SizedBox(width: 8),
                  _buildQuickMessageButton('THANKS', Icons.thumb_up),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(Map<String, dynamic> message) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.security, color: Colors.blue, size: 16),
              const SizedBox(width: 8),
              const Text(
                "Secure Connection Established",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message['text'],
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble({
    required Map<String, dynamic> message,
    required bool isMe,
    required bool isVoice,
  }) {
    final time = message['time'] as DateTime? ?? DateTime.now();
    final formattedTime = '${time.hour}:${time.minute.toString().padLeft(2, '0')}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.red,
                    const Color(0xFFB71C1C),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: 18,
              ),
            ),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(20),
                  topRight: const Radius.circular(20),
                  bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
                  bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
                ),
                gradient: isMe
                    ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFC62828),
                    Color(0xFFB71C1C),
                  ],
                )
                    : LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2A2A2A),
                    Colors.grey[800]!,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Text(
                            message['from'] ?? 'Unknown',
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        if (!isMe) const SizedBox(height: 4),
                        if (isVoice)
                          Row(
                            children: [
                              Icon(
                                Icons.play_circle_filled,
                                color: isMe ? Colors.white : Colors.red,
                                size: 24,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message['text'],
                                      style: TextStyle(
                                        color: isMe ? Colors.white : Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Duration: ${message['duration'] ?? '0s'}',
                                      style: TextStyle(
                                        color: isMe ? Colors.white70 : Colors.white70,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        else
                          Text(
                            message['text'],
                            style: TextStyle(
                              color: isMe ? Colors.white : Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              formattedTime,
                              style: TextStyle(
                                color: isMe ? Colors.white70 : Colors.white70,
                                fontSize: 10,
                              ),
                            ),
                            if (isVoice)
                              Row(
                                children: [
                                  Icon(
                                    Icons.headset,
                                    color: isMe ? Colors.white70 : Colors.white70,
                                    size: 12,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Voice',
                                    style: TextStyle(
                                      color: isMe ? Colors.white70 : Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (isMe && isVoice)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Icon(
                        Icons.mic,
                        color: Colors.white.withOpacity(0.7),
                        size: 14,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isMe)
            Container(
              width: 32,
              height: 32,
              margin: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFC62828),
                    const Color(0xFFB71C1C),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.person,
                color: Colors.white,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQuickMessageButton(String text, IconData icon) {
    return GestureDetector(
      onTap: () => _sendQuickMessage(text),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF2A0F0F),
              Color(0xFF1A0000),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}