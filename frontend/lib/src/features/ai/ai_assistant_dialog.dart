import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../app/app_shell.dart';
import '../../data/repositories/http_bankops_repository.dart';
import '../auth/auth_service.dart';

class AiAssistantDialog extends StatefulWidget {
  const AiAssistantDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const AiAssistantDialog(),
    );
  }

  @override
  State<AiAssistantDialog> createState() => _AiAssistantDialogState();
}

class _ChatMessage {
  _ChatMessage({required this.isUser, required this.text, this.model});
  final bool isUser;
  final String text;
  final String? model;
}

class _AiAssistantDialogState extends State<AiAssistantDialog> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoading = false;
  bool _disposed = false;

  final List<_ChatMessage> _messages = [
    _ChatMessage(
      isUser: false,
      text: 'Xin chào! Tôi là Trợ lý Nghiệp vụ BankOps.\n'
          'Tôi có thể tra cứu quy trình duyệt phiếu, kho quỹ, đối soát và nhập dữ liệu từ tài liệu nghiệp vụ.',
      model: 'Trợ lý BankOps',
    ),
  ];

  final List<String> _quickPrompts = [
    'Ai được lập và duyệt phiếu?',
    'Khi đối soát có chênh lệch cần làm gì?',
    'Dòng dữ liệu nhập bị lỗi thì xử lý thế nào?',
    'Phiếu đã ghi sổ có sửa được không?',
  ];

  Future<void> _sendMessage(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;
    _controller.clear();

    setState(() {
      _messages.add(_ChatMessage(isUser: true, text: query));
      _isLoading = true;
    });

    _scrollToBottom();

    String answer = '';
    final sources = <String>[];
    final responseIndex = _messages.length;
    setState(() => _messages.add(_ChatMessage(isUser: false, text: 'Đang tra cứu tài liệu…')));

    try {
      final repository = RepositoryScope.of(context);
      final token = repository is HttpBankOpsRepository
          ? await repository.accessToken
          : await context.read<AuthService>().getAccessToken();
      final apiBaseUrl = repository is HttpBankOpsRepository
          ? repository.baseUrl
          : AuthService.defaultBaseUrl;
      final request = http.Request('POST', Uri.parse('$apiBaseUrl/ai/chat/stream'))
        ..headers.addAll({
          'Content-Type': 'application/json',
          'Accept': 'text/event-stream',
          if (token != null) 'Authorization': 'Bearer $token',
        })
        ..body = json.encode({'message': query});
      final client = http.Client();
      try {
        final response = await client.send(request).timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          throw Exception('Máy chủ trả mã ${response.statusCode}');
        }
        String event = '';
        await for (final line in response.stream.transform(utf8.decoder).transform(const LineSplitter())) {
          if (line.startsWith('event: ')) {
            event = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            final data = json.decode(line.substring(6));
            if (event == 'delta' && data is Map && data['text'] is String) {
              answer += data['text'] as String;
              if (mounted && !_disposed) {
                setState(() => _messages[responseIndex] = _ChatMessage(isUser: false, text: answer));
                _scrollToBottom();
              }
            } else if (event == 'sources' && data is List) {
              sources.addAll(data.whereType<Map>().map((source) =>
                  '${source['source'] ?? ''} · ${source['section'] ?? ''}').where((source) => source.trim().isNotEmpty));
            } else if (event == 'error') {
              throw Exception(data is Map ? data['message'] : 'Trợ lý AI chưa sẵn sàng.');
            }
          }
        }
      } finally {
        client.close();
      }
      if (answer.isEmpty) throw Exception('Không nhận được nội dung trả lời.');
      if (sources.isNotEmpty) answer += '\n\nNguồn: ${sources.join('; ')}';
    } catch (error) {
      answer = 'Không thể tra cứu lúc này. Vui lòng thử lại. ($error)';
    }

    if (mounted && !_disposed) {
      setState(() {
        _messages[responseIndex] = _ChatMessage(isUser: false, text: answer);
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 720),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.psychology_outlined, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Trợ lý Nghiệp vụ BankOps AI',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Tra cứu quy trình nghiệp vụ có dẫn nguồn',
                          style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Quick Prompts
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, idx) {
                  final prompt = _quickPrompts[idx];
                  return ActionChip(
                    label: Text(prompt, style: const TextStyle(fontSize: 12)),
                    onPressed: _isLoading ? null : () => _sendMessage(prompt),
                  );
                },
              ),
            ),
            const Divider(height: 1),

            // Messages
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: _messages.length,
                itemBuilder: (context, idx) {
                  final msg = _messages[idx];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                      children: [
                        if (!msg.isUser) ...[
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                            child: Icon(Icons.auto_awesome, size: 16, color: theme.colorScheme.primary),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: msg.isUser
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.text,
                                  style: TextStyle(
                                    color: msg.isUser ? Colors.white : theme.colorScheme.onSurface,
                                    fontSize: 13.5,
                                    height: 1.45,
                                  ),
                                ),
                                if (msg.model != null) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    'Mô hình: ${msg.model}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: msg.isUser ? Colors.white70 : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (msg.isUser) ...[
                          const SizedBox(width: 10),
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: theme.colorScheme.primary,
                            child: const Icon(Icons.person, size: 16, color: Colors.white),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),

            if (_isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'AI đang tra cứu quy trình...',
                      style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),

            // Input bar
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(top: BorderSide(color: theme.dividerColor)),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Nhập câu hỏi quy trình (ví dụ: Quy định duyệt phiếu > 1 tỷ)...',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: _isLoading ? null : _sendMessage,
                    ),
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.send_rounded, size: 18),
                    onPressed: _isLoading ? null : () => _sendMessage(_controller.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
