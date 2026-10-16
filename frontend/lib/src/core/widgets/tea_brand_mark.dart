import 'package:flutter/material.dart';

/// Biểu tượng trà sữa vẽ bằng vector để luôn hiện đúng trên web và desktop.
class TeaBrandMark extends StatelessWidget {
  const TeaBrandMark({super.key, this.size = 20});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: const CustomPaint(painter: _TeaBrandMarkPainter()),
      );
}

class _TeaBrandMarkPainter extends CustomPainter {
  const _TeaBrandMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas.save();
    canvas.scale(scale, scale);

    final fill = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Nắp và thân ly trà sữa.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(5.4, 5.5, 13.2, 2.2), const Radius.circular(1.1)),
      fill,
    );
    canvas.drawPath(
      Path()
        ..moveTo(6.9, 8.7)
        ..lineTo(8.1, 19.1)
        ..quadraticBezierTo(8.3, 20.5, 9.7, 20.5)
        ..lineTo(14.4, 20.5)
        ..quadraticBezierTo(15.8, 20.5, 16.0, 19.1)
        ..lineTo(17.1, 8.7)
        ..close(),
      stroke,
    );

    // Ống hút và hai trân châu tạo dấu hiệu nhận biết khi thu nhỏ.
    canvas.drawLine(const Offset(14.3, 3.2), const Offset(12.4, 8.0), stroke);
    canvas.drawCircle(const Offset(10.1, 16.5), 1.15, fill);
    canvas.drawCircle(const Offset(13.9, 16.5), 1.15, fill);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TeaBrandMarkPainter oldDelegate) => false;
}
