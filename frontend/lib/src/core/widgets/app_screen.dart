import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../util/responsive.dart';

/// Bọc nội dung màn: padding theo breakpoint, nội dung giới hạn width,
/// refresh toàn cục.
///
/// Shell (`AppShell`) cung cấp AppBar + rail/bottom nav bên cạnh.
/// Màn chỉ cần truyền `body` (scrollable) và `header` tùy ý.
class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.body,
    this.header,
    this.onRefresh,
  });

  final Widget body;
  final Widget? header;
  final RefreshCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    Widget content = Column(
      children: [
        if (header != null) ...[
          header!,
          const SizedBox(height: AppSpacing.xxl),
        ],
        Expanded(child: body),
      ],
    );

    if (onRefresh != null) {
      content = RefreshIndicator(
        onRefresh: onRefresh!,
        child: content,
      );
    }

    return SafeArea(
      top: false, // AppBar đã xử lý top safe area
      bottom: false, // NavigationBar đã xử lý bottom safe area
      left: true, // Xử lý tai thỏ / giọt nước / Dynamic Island khi xoay ngang
      right: true, // Xử lý tai thỏ / giọt nước / Dynamic Island khi xoay ngang
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1120),
        padding: context.pagePadding,
        child: content,
      ),
    );
  }
}
