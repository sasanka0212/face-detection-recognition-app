import 'package:face_recognition_app/models/detection_candidate.dart';

class RecognizedFace {
  DetectionCandidate detection;

  /// add on 08-06-26
  final String? name;
  final double score;

  RecognizedFace({
    required this.detection,

    /// add on 08-06-26
    required this.name,
    required this.score,
  });
}
