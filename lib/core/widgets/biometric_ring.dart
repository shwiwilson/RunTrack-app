import 'package:flutter/material.dart';
import 'dart:math'; // Import dart:math for pi

class BiometricRing extends StatelessWidget {
  final double progress;
  final Color color;
  final double size;
  final Color subtleStrokeColor;
  final String? label;
  final double labelAngleOffset;
  final double? strokeWidth;

  const BiometricRing({
    required this.progress,
    required this.color,
    required this.size,
    required this.subtleStrokeColor,
    this.label,
    this.labelAngleOffset = 0,
    this.strokeWidth,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(4.0),
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.transparent,
      ),
      child: CustomPaint(
        painter: RingPainter(
          progress: progress,
          color: color,
          subtleStrokeColor: subtleStrokeColor,
          label: label,
          labelAngleOffset: labelAngleOffset,
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color subtleStrokeColor;
  final String? label;
  final double labelAngleOffset;
  final double? strokeWidth;

  RingPainter({
    required this.progress,
    required this.color,
    required this.subtleStrokeColor,
    this.label,
    this.strokeWidth,
    this.labelAngleOffset = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerX = size.width / 2.0;
    final centerY = size.height / 2.0;

    // Use provided strokeWidth or fallback to proportional:
    // 14% of diameter provides the best balance for text
    final effectiveStrokeWidth = strokeWidth ?? (size.width * 0.14);
    final radius = (size.width / 2.0) - (effectiveStrokeWidth / 2.0);

    final backgroundPaint = Paint()
      ..color = subtleStrokeColor
      ..strokeWidth = effectiveStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..strokeWidth = effectiveStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(Offset(centerX, centerY), radius, backgroundPaint);

    final startAngle = -pi / 2;
    final sweepAngle = pi * 2 * progress;

    // Draw background and progress arcs
    canvas.drawArc(
      Rect.fromCircle(center: Offset(centerX, centerY), radius: radius),
      startAngle,
      sweepAngle,
      false,
      progressPaint,
    );

    // Draw curved label if provided
    if (label != null) {
      _drawCurvedLabel(canvas, size, radius, centerX, centerY);
    }
  }

  void _drawCurvedLabel(
    Canvas canvas,
    Size size,
    double radius,
    double centerX,
    double centerY,
  ) {
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: (size.width * 0.09).clamp(
        10.0,
        24.0,
      ), // Cap font size for legibility
      fontWeight:
          FontWeight.w900, // Extra bold for better 'Difference' contrast
      letterSpacing: 1.5,
    );

    // Create a layer to apply the difference blend mode.
    // This allows the white text to invert the colors underneath it.
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..blendMode = BlendMode.difference,
    );

    // Start drawing characters at the top, adjusted by the offset
    double currentAngle = -pi / 2 + labelAngleOffset;

    for (int i = 0; i < label!.length; i++) {
      final char = label![i];
      final textPainter = TextPainter(
        text: TextSpan(text: char, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final charAngle = textPainter.width / radius;

      canvas.save();
      // Move to the position on the circle
      final x = centerX + radius * cos(currentAngle + charAngle / 2);
      final y = centerY + radius * sin(currentAngle + charAngle / 2);

      canvas.translate(x, y);
      canvas.rotate(currentAngle + charAngle / 2 + pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();

      currentAngle += charAngle;
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.subtleStrokeColor != subtleStrokeColor ||
        oldDelegate.label != label ||
        oldDelegate.labelAngleOffset != labelAngleOffset ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
