import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Avatar người dùng hỗ trợ:
/// 1. Ảnh đại diện tải lên từ điện thoại / máy tính (base64 Data URL)
/// 2. Ảnh từ mạng hoặc ảnh tài khoản Google (HTTP/HTTPS URL)
/// 3. Ảnh mặc định tự động đồng bộ theo Email (Gravatar MD5 hash)
/// 4. Chữ cái viết tắt (Initials) thanh lịch khi không có ảnh hoặc ngoại tuyến
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    this.name,
    this.email,
    this.avatarUrl,
    this.size = 36,
    this.onTap,
    this.showEditBadge = false,
    this.onEditTap,
  });

  final String? name;
  final String? email;
  final String? avatarUrl;
  final double size;
  final VoidCallback? onTap;
  final bool showEditBadge;
  final VoidCallback? onEditTap;

  /// Trích xuất 1-2 chữ cái đầu làm ký hiệu đại diện.
  static String initials(String? name) {
    if (name == null || name.trim().isEmpty) return '??';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final only = parts.single;
      return '${only[0].toUpperCase()}${only.length > 1 ? only[1].toUpperCase() : ''}';
    }
    return '${parts[0][0].toUpperCase()}${parts[parts.length - 1][0].toUpperCase()}';
  }

  /// Tính URL Gravatar chuẩn từ email người dùng.
  static String gravatarUrl(String email, {int size = 160}) {
    final clean = email.trim().toLowerCase();
    final hash = md5.convert(utf8.encode(clean)).toString();
    return 'https://www.gravatar.com/avatar/$hash?s=$size&d=identicon';
  }

  /// Xác định URL avatar hiệu lực (ảnh riêng > gravatar theo email > null).
  static String? resolveEffectiveAvatarUrl({
    String? avatarUrl,
    String? email,
    int size = 160,
  }) {
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      return avatarUrl.trim();
    }
    if (email != null && email.trim().isNotEmpty && email.contains('@')) {
      return gravatarUrl(email, size: size);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final sc = Theme.of(context);
    final bg = _palette(sc);
    final textColor = sc.colorScheme.onSurface;
    final effectiveUrl = resolveEffectiveAvatarUrl(
      avatarUrl: avatarUrl,
      email: email,
      size: (size * 2).toInt().clamp(80, 400),
    );

    Widget avatarCore;
    if (effectiveUrl != null) {
      if (effectiveUrl.startsWith('data:image')) {
        try {
          final commaIdx = effectiveUrl.indexOf(',');
          final base64Payload =
              commaIdx != -1 ? effectiveUrl.substring(commaIdx + 1) : effectiveUrl;
          final bytes = base64Decode(base64Payload);
          avatarCore = ClipOval(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallback(bg, textColor),
            ),
          );
        } catch (_) {
          avatarCore = _buildFallback(bg, textColor);
        }
      } else {
        avatarCore = ClipOval(
          child: Image.network(
            effectiveUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallback(bg, textColor),
          ),
        );
      }
    } else {
      avatarCore = _buildFallback(bg, textColor);
    }

    final avatarWidget = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(
          color: sc.colorScheme.outlineVariant,
          width: 2,
        ),
      ),
      child: avatarCore,
    );

    Widget result = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: avatarWidget,
    );

    if (showEditBadge) {
      final badgeSize = (size * 0.36).clamp(20.0, 26.0);
      result = Stack(
        clipBehavior: Clip.none,
        children: [
          result,
          Positioned(
            bottom: -2,
            right: -2,
            child: GestureDetector(
              onTap: onEditTap ?? onTap,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: sc.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: sc.colorScheme.surface,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.camera_alt_rounded,
                  size: (badgeSize * 0.58).clamp(11.0, 15.0),
                  color: sc.colorScheme.onPrimary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return result;
  }

  Widget _buildFallback(Color bg, Color textColor) {
    return Center(
      child: Text(
        initials(name),
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
          letterSpacing: -0.5,
        ),
      ),
    );
  }

  static Color _palette(ThemeData sc) => switch (sc.brightness) {
        Brightness.light => const Color(0xFF007F86),
        Brightness.dark => const Color(0xFF9DB8E0),
      };
}
