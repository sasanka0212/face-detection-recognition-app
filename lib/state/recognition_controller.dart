import 'package:face_recognition_app/models/detection_candidate.dart';
import 'package:face_recognition_app/models/recognized_face.dart';
import 'package:get/get.dart';

class RecognitionController extends GetxController {

  var recognizedFaces = <RecognizedFace>[].obs;
  var trackedFaces = <RecognizedFace>[].obs;
  var detectionCandidates = <DetectionCandidate>[].obs;
}