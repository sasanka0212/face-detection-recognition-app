import 'dart:math' as math;

import 'package:face_recognition_app/models/box.dart';
import 'package:face_recognition_app/models/face_land_marks.dart';
import 'package:face_recognition_app/models/landmark.dart';

double sigmoid(double x) {
  if (x > 88) return 1.0;
  if (x < -88) return 0.0;

  return 1.0 / (1.0 + math.exp(-x));
}

const strides = [8, 16, 32];

class Prior {
  final double cx;
  final double cy;
  final double w;
  final double h;

  Prior(this.cx, this.cy, this.w, this.h);
}

List<Prior> generatePriors(int inputW, int inputH) {
  final priors = <Prior>[];

  for (final stride in strides) {
    final featW = inputW ~/ stride;
    final featH = inputH ~/ stride;

    for (int y = 0; y < featH; y++) {
      for (int x = 0; x < featW; x++) {
        priors.add(
          Prior(
            x * stride.toDouble(),
            y * stride.toDouble(),
            stride.toDouble(),
            stride.toDouble(),
          ),
        );
      }
    }
  }

  return priors;
}

List<Prior> generateStridePriors(
  int inputW,
  int inputH,
  int stride,
) {
  final priors = <Prior>[];

  final featW = (inputW / stride).ceil();
  final featH = (inputH / stride).ceil();

  for (int y = 0; y < featH; y++) {
    for (int x = 0; x < featW; x++) {

      final cx =
          (x + 0.5) * stride.toDouble();

      final cy =
          (y + 0.5) * stride.toDouble();

      priors.add(
        Prior(
          cx,
          cy,
          stride.toDouble(),
          stride.toDouble(),
        ),
      );
    }
  }

  return priors;
}

List<Box> decodeBoxes(List<double> rawBoxes, List<Prior> priors) {
  final boxes = <Box>[];

  for (int i = 0; i < priors.length; i++) {
    final prior = priors[i];

    final offset = i * 4;

    final dx = rawBoxes[offset];
    final dy = rawBoxes[offset + 1];
    final dw = rawBoxes[offset + 2];
    final dh = rawBoxes[offset + 3];

    final cx = prior.cx + dx * prior.w - prior.w * 0.5;

    final cy = prior.cy + dy * prior.h;

    final w = prior.w * math.exp(dw.clamp(-4.0, 4.0));

    final h = prior.h * math.exp(dh.clamp(-4.0, 4.0));

    final x1 = cx - w * 0.5;
    final y1 = cy - h * 0.5;

    final x2 = cx + w * 0.5;
    final y2 = cy + h * 0.5;

    boxes.add(Box(x1, y1, x2, y2));
  }

  return boxes;
}

List<FaceLandmarks> decodeLandmarks(
  List<double> rawLandmarks,
  List<Prior> priors,
) {
  final results = <FaceLandmarks>[];

  for (int i = 0; i < priors.length; i++) {
    final prior = priors[i];

    final points = <Landmark>[];

    final offset = i * 10;

    for (int p = 0; p < 5; p++) {
      final dx = rawLandmarks[offset + p * 2];

      final dy = rawLandmarks[offset + p * 2 + 1];

      final x = dx * prior.w + prior.cx - prior.w * 0.5;

      final y = dy * prior.h + prior.cy - prior.h * 0.5;

      points.add(Landmark(x, y));
    }

    results.add(FaceLandmarks(points));
  }

  return results;
}

List<double> computeScores(List<double> clsRaw, List<double> objRaw) {
  final scores = <double>[];

  for (int i = 0; i < clsRaw.length; i++) {
    final clsScore = (clsRaw[i] >= 0 && clsRaw[i] <= 1)
        ? clsRaw[i]
        : sigmoid(clsRaw[i]);

    final objScore = (objRaw[i] >= 0 && objRaw[i] <= 1)
        ? objRaw[i]
        : sigmoid(objRaw[i]);

    scores.add(math.sqrt(clsScore * objScore));
  }

  return scores;
}

double computeIoU(
  Box a,
  Box b,
) {
  final xx1 = math.max(a.x1, b.x1);
  final yy1 = math.max(a.y1, b.y1);

  final xx2 = math.min(a.x2, b.x2);
  final yy2 = math.min(a.y2, b.y2);

  final w = math.max(0.0, xx2 - xx1);
  final h = math.max(0.0, yy2 - yy1);

  final inter = w * h;

  final areaA =
      (a.x2 - a.x1) *
      (a.y2 - a.y1);

  final areaB =
      (b.x2 - b.x1) *
      (b.y2 - b.y1);

  return inter /
      (areaA +
          areaB -
          inter +
          1e-6);
}