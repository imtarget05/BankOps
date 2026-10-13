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
          'Tôi có thể hỗ trợ bạn tra cứu quy trình Maker - Checker, hạn mức két sắt, quản lý kho phôi thẻ chip, hoặc hướng dẫn xử lý lỗi import.',
      model: 'Trợ lý BankOps',
    ),
  ];

  final List<String> _quickPrompts = [
    'Quy trình Maker - Checker hoạt động ra sao?',
    'Hạn mức tồn quỹ két sắt quầy giao dịch?',
    'Cách xử lý khi file import staging bị lỗi?',
    'Quy định quản lý phôi thẻ EMV và sổ séc?',
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
    String? modelUsed;

    try {
      final repository = RepositoryScope.of(context);
      final token = repository is HttpBankOpsRepository
          ? await repository.accessToken
          : await context.read<AuthService>().getAccessToken();
      final apiBaseUrl = repository is HttpBankOpsRepository
          ? repository.baseUrl
          : const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://localhost:8000/api/v1',
            );
      final uri = Uri.parse('$apiBaseUrl/ai/chat');

      final resp = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({'message': query}),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode == 200) {
        final data = json.decode(utf8.decode(resp.bodyBytes));
        answer = data['answer'] as String? ?? 'Không có phản hồi từ máy chủ.';
        modelUsed = data['model'] as String?;
      } else {
        throw Exception('Mã phản hồi: ${resp.statusCode}');
      }
    } catch (_) {
      // Fallback nghiệp vụ ngân hàng đáng tin cậy
      answer = _getGroundedBankingAnswer(query);
      modelUsed = 'bankops-local-rules';
    }

    if (mounted && !_disposed) {
      setState(() {
        _messages.add(_ChatMessage(isUser: false, text: answer, model: modelUsed));
        _isLoading = false;
      });
      _scrollToBottom();
    }
  }

  String _getGroundedBankingAnswer(String q) {
    final lower = q.toLowerCase();
    if (lower.contains('maker') || lower.contains('checker') || lower.contains('duyệt')) {
      return 'Quy trình Maker - Checker (Four-Eyes Principle):\n'
          '1. Maker lập phiếu yêu cầu (Draft) -> bấm Gửi duyệt (Pending).\n'
          '2. Phiếu chuyển sang Hộp thư phê duyệt của Kiểm soát viên (Checker).\n'
          '3. Checker độc lập kiểm tra chứng từ và Phê duyệt (Posted) hoặc Từ chối (Rejected).\n'
          'Lưu ý: Maker tuyệt đối không được tự duyệt phiếu của chính mình!';
    }
    if (lower.contains('két') || lower.contains('quỹ') || lower.contains('hạn mức')) {
      return 'Hệ thống Quỹ BankOps:\n'
          '- Đại quỹ Hội sở (CB-MAIN-01): Số dư 25.000.000.000 VND (Két chính).\n'
          '- Két quầy GDV 1 & 2 (CB-TELLER-01/02): Hạn mức định mức 100 - 500 triệu VND.\n'
          '- Két ATM (CB-ATM-01): 500 triệu VND phục vụ chi tiền tự động.\n'
          'Số dư chỉ thay đổi sau khi phiếu thu/chi đã được Checker duyệt thành công.';
    }
    if (lower.contains('import') || lower.contains('staging') || lower.contains('lỗi')) {
      return 'Quy trình xử lý lỗi Import:\n'
          '1. File CSV/JSON hoặc Google Sheets tải lên sẽ nằm tại vùng tạm (Staging).\n'
          '2. Xem bảng Preview kiểm tra các dòng bị báo đỏ (lỗi SKU, sai định dạng ngày, số tiền âm).\n'
          '3. Không nhấn Xác nhận (Confirm) khi còn dòng lỗi. Hãy tải lại file đã chuẩn hóa dữ liệu.';
    }
    if (lower.contains('phôi') || lower.contains('thẻ') || lower.contains('séc') || lower.contains('sổ')) {
      return 'Quản lý Kho Ấn chỉ quan trọng:\n'
          '- Phôi thẻ Visa Debit EMV Chip và Sổ séc bảo chi bắt buộc quản lý theo Serial (Tracked by Serial).\n'
          '- Mỗi giao dịch xuất kho cấp phát cho GDV đều phải lưu vết dải serial cụ thể và có xác nhận của Thủ kho.';
    }
    return 'Chào bạn! Để đảm bảo an toàn vận hành ngân hàng, mọi thao tác ghi sổ và duyệt chi tiền đều cần tuân thủ quy trình Maker-Checker. Bạn có thể hỏi thêm về quy định két sắt, kho ấn chỉ, hoặc kiểm toán hash-chain.';
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
                          'Hỗ trợ tra cứu quy trình kiểm soát nội bộ, kho quỹ & Maker-Checker',
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
