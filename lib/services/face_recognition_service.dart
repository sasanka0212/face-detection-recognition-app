import 'package:face_recognition_app/models/detection_candidate.dart';
import 'package:face_recognition_app/models/recognition_result.dart';
import 'face_database_service.dart';

class FaceRecognitionService {

  final FaceDatabaseService database;

  FaceRecognitionService(this.database);

  Future<RecognitionResult> recognize(
    List<double> queryEmbedding,
  ) async {

    final faces =
        await database.getAllFaces();

    if (faces.isEmpty) {
      return RecognitionResult(
        name: null,
        score: 0,
      );
    }

    String? bestName;
    double bestScore = -1;

    for (final face in faces) {

      double score = 0;

      for (int i = 0; i < queryEmbedding.length; i++) {
        score +=
            queryEmbedding[i] *
            face.embedding[i];
      }

      if (score > bestScore) {
        bestScore = score;
        bestName = face.name;
      }

      print(
        "Face Name: ${face.name} -> $score",
      );
    }

    if (bestScore >= 0.72) {
      return RecognitionResult(
        name: bestName,
        score: bestScore,
      );
    }

    return RecognitionResult(
      name: null,
      score: bestScore,
    );
  }

  double  distanceSquared(DetectionCandidate a, DetectionCandidate b) {
    final ax = (a.box.x1 + a.box.x2) / 2;
    final ay = (a.box.y1 + a.box.y2) / 2;

    final bx = (b.box.x1 + b.box.x2) / 2;
    final by = (b.box.y1 + b.box.y2) / 2;

    final dx = ax - bx;
    final dy = ay - by;

    return dx * dx + dy * dy;
  }
}