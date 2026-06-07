import 'package:flutter/material.dart';
import '../models/detection_candidate.dart';

class FacePainter extends CustomPainter {
  final List<DetectionCandidate> detections;
  final Size imageSize;
  final String? recognizedName;
  final double? similarity;

  FacePainter({
    required this.detections,
    required this.imageSize,
    this.recognizedName,
    this.similarity
  });

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.green;

    final landmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.red;

    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    for (final detection in detections) {
      // Draw bounding box
      final left = detection.box.x1 * scaleX;
      final top = detection.box.y1 * scaleY;
      final right = detection.box.x2 * scaleX;
      final bottom = detection.box.y2 * scaleY;

      canvas.drawRect(
        Rect.fromLTRB(
          left,
          top,
          right,
          bottom,
        ),
        boxPaint,
      );

      // Draw landmarks
      for (int i = 0; i < detection.landmarks.points.length; i++) {
        final point = detection.landmarks.points[i];

        final x = point.x * scaleX;
        final y = point.y * scaleY;

        // landmark dot
        canvas.drawCircle(
          Offset(x, y),
          4,
          landmarkPaint,
        );

        // landmark index text
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$i',
            style: const TextStyle(
              color: Colors.yellow,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();

        textPainter.paint(
          canvas,
          Offset(x + 5, y - 5),
        );
      }
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return true;
  }
}