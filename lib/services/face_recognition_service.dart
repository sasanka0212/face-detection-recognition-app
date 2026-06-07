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

    if (bestScore >= 0.75) {
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
}