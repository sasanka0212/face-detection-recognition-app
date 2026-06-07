import 'package:face_recognition_app/models/box.dart';
import 'package:face_recognition_app/models/face_land_marks.dart';

class DetectionCandidate {
  final Box box;
  final FaceLandmarks landmarks;
  final double score;

  DetectionCandidate({
    required this.box,
    required this.landmarks,
    required this.score,
  });
}