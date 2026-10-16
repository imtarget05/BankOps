import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/http_bankops_repository.dart';
import '../auth/auth_service.dart';

/// "Khai" là trợ lý cho ứng dụng Quản Lý Kho Trà Sữa.
/// is intentionally not shown inside a user's conversation.
class AiAssistantDialog extends StatefulWidget {
  const AiAssistantDialog({super.key});

  static Future<void> show(BuildContext context) {
    final repo = RepositoryScope.maybeOf(context);
    return showDialog(
      context: context,
      builder: (_) {
        Widget child = const AiAssistantDialog();
        if (repo != null) {
          child = RepositoryScope(repository: repo, child: child);
        }
        return child;
      },
    );
  }

  @override
  State<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _ChatMessage {
  const _ChatMessage({
    required this.isUser,
    required this.text,
    this.needsSignIn = false,
  });

  final bool isUser;
  final String text;
  final bool needsSignIn;
}

class _ChatRequestFailure implements Exception {
  const _ChatRequestFailure(this.statusCode);
  final int statusCode;
}

String _shortSourceLabel(Map source) {
  final raw = (source['source'] ?? '').toString();
  var name = raw.split('/').last;
  if (name.endsWith('.md')) {
    name = name.substring(0, name.length - 3);
  }
  return name.trim();
}

class _AiAssistantDialogState extends State<AiAssistantDialog> {
  static const _brand = Color(0xFF153E75);
  static const _ink = Color(0xFF10233F);
  static const _muted = Color(0xFF60708A);

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _disposed = false;

  final List<String> _quickPrompts = const [
    'Ai được lập và duyệt phiếu kho?',
    'Chốt ca sáng/chiều theo công thức nào?',
    'Tồn chạm Min hoặc lệch kiểm kê thì xử lý sao?',
    'Lô sữa tươi cận date cần làm gì?',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_messages.isNotEmpty) return;
    final user =
        SessionScope.maybeOf(context)?.user ?? context.read<AuthService>().user;
    final name = (user?.displayName.trim().isNotEmpty ?? false)
        ? user!.displayName.trim()
        : (user?.username.trim().isNotEmpty ?? false)
            ? user!.username.trim()
            : 'bạn';
    _messages.add(_ChatMessage(isUser: false, text: 'Xin chào, $name.'));
  }

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty || _isLoading) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: query));
      _messages.add(const _ChatMessage(isUser: false, text: 'Đang trả lời…'));
      _isLoading = true;
    });
    final responseIndex = _messages.length - 1;
    _scrollToBottom();

    String answer = '';
    final sources = <String>[];
    var needsSignIn = false;
    try {
      final repository = RepositoryScope.maybeOf(context);
      final auth = context.read<AuthService>();
      final token = repository is HttpBankOpsRepository
          ? await repository.accessToken
          : await auth.getAccessToken();
      if (token == null || token.isEmpty) throw const _ChatRequestFailure(401);
      final apiBaseUrl = repository is HttpBankOpsRepository
          ? repository.baseUrl
          : auth.apiBaseUrl;
      final request =
          http.Request('POST', Uri.parse('$apiBaseUrl/ai/chat/stream'))
            ..headers.addAll({
              'Content-Type': 'application/json',
              'Accept': 'text/event-stream',
              'Authorization': 'Bearer $token',
            })
            ..body = json.encode({'message': query});

      final client = http.Client();
      try {
        try {
          final response =
              await client.send(request).timeout(const Duration(seconds: 25));
          if (response.statusCode != 200) {
            throw _ChatRequestFailure(response.statusCode);
          }
          String event = '';
          await for (final line in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
            if (line.startsWith('event: ')) {
              event = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              final raw = line.substring(6).trim();
              if (raw.isEmpty) continue;
              final data = json.decode(raw);
              if (event == 'delta' && data is Map && data['text'] is String) {
                answer += data['text'] as String;
                if (mounted && !_disposed) {
                  setState(() => _messages[responseIndex] =
                      _ChatMessage(isUser: false, text: answer));
                  _scrollToBottom();
                }
              } else if (event == 'sources' && data is List) {
                sources.addAll(data
                    .whereType<Map>()
                    .map(_shortSourceLabel)
                    .where((source) => source.trim().isNotEmpty));
              } else if (event == 'error') {
                throw const _ChatRequestFailure(503);
              }
            }
          }
        } on _ChatRequestFailure {
          rethrow;
        } catch (_) {
          // Fall back only for an SSE transport failure, never after 401/403/429.
          final response = await http
              .post(
                Uri.parse('$apiBaseUrl/ai/chat'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer $token'
                },
                body: json.encode({'message': query}),
              )
              .timeout(const Duration(seconds: 25));
          if (response.statusCode != 200) {
            throw _ChatRequestFailure(response.statusCode);
          }
          final data = json.decode(utf8.decode(response.bodyBytes));
          if (data is! Map || data['answer'] is! String) {
            throw const _ChatRequestFailure(503);
          }
          answer = data['answer'] as String;
          if (data['sources'] is List) {
            sources.addAll((data['sources'] as List)
                .whereType<Map>()
                .map(_shortSourceLabel)
                .where((source) => source.trim().isNotEmpty));
          }
        }
      } finally {
        client.close();
      }
      if (answer.isEmpty) throw const _ChatRequestFailure(503);
      final briefSources = <String>[];
      for (final source in sources) {
        if (source.isEmpty || briefSources.contains(source)) continue;
        briefSources.add(source);
        if (briefSources.length == 3) break;
      }
      if (briefSources.isNotEmpty) {
        answer += "\n\nNguồn: ${briefSources.join(', ')}";
      }
    } on _ChatRequestFailure catch (error) {
      if (error.statusCode == 401) {
        answer = 'Phiên đăng nhập đã hết hạn. Đăng nhập lại để tiếp tục.';
        needsSignIn = true;
      } else if (error.statusCode == 403) {
        answer = 'Tài khoản này chưa được phép dùng trợ lý nghiệp vụ.';
      } else if (error.statusCode == 429) {
        answer = 'Bạn đã gửi quá nhiều câu hỏi. Hãy thử lại sau một phút.';
      } else if (error.statusCode == 503) {
        answer = 'Khai chưa sẵn sàng. Vui lòng thử lại sau.';
      } else {
        answer = 'Máy chủ trả lỗi ${error.statusCode}.';
      }
    } catch (_) {
      answer = 'Không kết nối được với Khai. Hãy kiểm tra kết nối rồi thử lại.';
    }

    if (!mounted || _disposed) return;
    setState(() {
      _messages[responseIndex] =
          _ChatMessage(isUser: false, text: answer, needsSignIn: needsSignIn);
      _isLoading = false;
    });
    _scrollToBottom();
  }

  Future<void> _signOutAndClose() async {
    await context.read<AuthService>().signOut();
    if (mounted) Navigator.of(context).pop();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
          child: Column(children: [
            _buildHeader(),
            _buildQuickPrompts(),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                itemCount: _messages.length,
                itemBuilder: (_, index) => _buildMessage(_messages[index]),
              ),
            ),
            _buildComposer(),
          ]),
        ),
      );

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
        color: _ink,
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF74D3C4),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Text('K',
                style: TextStyle(
                    color: _ink, fontSize: 23, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Khai',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 2),
              Text('Trợ lý Quản Lý Kho Trà Sữa',
                  style: TextStyle(color: Color(0xFFC3D4EE), fontSize: 12)),
            ]),
          ),
          IconButton(
            tooltip: 'Đóng trợ lý',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ]),
      );

  Widget _buildQuickPrompts() => Container(
        alignment: Alignment.centerLeft,
        color: const Color(0xFFF5F8FC),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _quickPrompts
                .map((prompt) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(prompt),
                        labelStyle: const TextStyle(fontSize: 12, color: _ink),
                        side: const BorderSide(color: Color(0xFFD8E2EF)),
                        backgroundColor: Colors.white,
                        onPressed:
                            _isLoading ? null : () => _sendMessage(prompt),
                      ),
                    ))
                .toList(),
          ),
        ),
      );

  Widget _buildMessage(_ChatMessage message) {
    final bubbleColor = message.isUser ? _brand : const Color(0xFFF1F5F9);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                  color: Color(0xFFD9F1EC), shape: BoxShape.circle),
              child: const Text('K',
                  style: TextStyle(color: _ink, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 9),
          ],
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 570),
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(message.isUser ? 16 : 4),
                  bottomRight: Radius.circular(message.isUser ? 4 : 16),
                ),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(message.text,
                        style: TextStyle(
                            color: message.isUser ? Colors.white : _ink,
                            fontSize: 14,
                            height: 1.45)),
                    if (message.needsSignIn) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _signOutAndClose,
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: const Text('Đăng nhập lại'),
                        style:
                            OutlinedButton.styleFrom(foregroundColor: _brand),
                      ),
                    ],
                  ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() => Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE0E7F0))),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _controller,
              enabled: !_isLoading,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              decoration: InputDecoration(
                hintText: 'Hỏi về quy trình, tồn kho hoặc đối soát…',
                hintStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: const Color(0xFFF6F8FB),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFD8E2EF)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFD8E2EF)),
                ),
              ),
              onSubmitted: _isLoading ? null : _sendMessage,
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            label: 'Gửi câu hỏi',
            button: true,
            child: IconButton.filled(
              tooltip: 'Gửi câu hỏi',
              onPressed:
                  _isLoading ? null : () => _sendMessage(_controller.text),
              style: IconButton.styleFrom(
                  backgroundColor: _brand, minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ]),
      );
}
