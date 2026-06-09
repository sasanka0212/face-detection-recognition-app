import 'package:face_recognition_app/models/recognized_face.dart';
import 'package:flutter/material.dart';

class FaceRecognitionPainter extends CustomPainter {
  final List<RecognizedFace> recognizedFaces;
  final Size imageSize;

  FaceRecognitionPainter({required this.recognizedFaces, required this.imageSize});

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

    for (final face in recognizedFaces) {
      final detection = face.detection;

      final left = detection.box.x1 * scaleX;
      final top = detection.box.y1 * scaleY;
      final right = detection.box.x2 * scaleX;
      final bottom = detection.box.y2 * scaleY;

      // Bounding Box
      canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), boxPaint);

      // Name + Similarity
      final labelPainter = TextPainter(
        text: TextSpan(
          text: face.name == "Unknown"
              ? "${face.name ?? "Unknown"}\n"
              : "${face.name ?? "Unknown"}\n"
                "${face.score.toStringAsFixed(2)}",
          style: TextStyle(color: face.name == null ? Colors.orange : Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold, backgroundColor: Colors.black),
        ),
        textDirection: TextDirection.ltr,
      );

      labelPainter.layout();

      labelPainter.paint(canvas, Offset(left, top - 40));

      // Landmarks
      for (final point in detection.landmarks.points) {
        final x = point.x * scaleX;
        final y = point.y * scaleY;

        canvas.drawCircle(Offset(x, y), 4, landmarkPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
