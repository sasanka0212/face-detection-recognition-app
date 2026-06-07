import 'dart:typed_data';

import 'package:face_recognition_app/models/box.dart';
import 'package:face_recognition_app/models/detection_candidate.dart';
import 'package:face_recognition_app/models/face_land_marks.dart';
import 'package:face_recognition_app/models/landmark.dart';
import 'package:face_recognition_app/services/yunet_postprocess.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

class YuNetService {
  late OrtSession _session;
  static const int inputSize = 640;
  static const double scoreThreshold = 0.75;
  static const double nmsThreshold = 0.3;

  Future<void> initialize() async {
    final ort = OnnxRuntime();

    _session = await ort.createSessionFromAsset('assets/models/yunet.onnx');

    print('YUNET MODEL LOADED');
    print('runtime: ${_session.runtimeType}');
    print('input:');
    _session.inputNames.forEach((input) => print(input));
  }

  Future<List<DetectionCandidate>> detect(Float32List inputTensor) async {
    final inputOrt = await OrtValue.fromList(inputTensor, [1, 3, 640, 640]);

    final outputs = await _session.run({'input': inputOrt});

    print('OUTPUT COUNT: ${outputs.length}');

    outputs.forEach((name, value) async {
      final data = await value.asFlattenedList();

      print('$name -> ${data.length}');
    });

    final stride8 = await processStride(outputs: outputs, stride: 8);

    final stride16 = await processStride(outputs: outputs, stride: 16);

    final stride32 = await processStride(outputs: outputs, stride: 32);

    final scores8 = stride8['scores'] as List<double>;

    final boxes8 = stride8['boxes'] as List<Box>;

    final landmarks8 = stride8['landmarks'] as List<FaceLandmarks>;

    final scores16 = stride16['scores'] as List<double>;

    final boxes16 = stride16['boxes'] as List<Box>;

    final landmarks16 = stride16['landmarks'] as List<FaceLandmarks>;

    final scores32 = stride32['scores'] as List<double>;

    final boxes32 = stride32['boxes'] as List<Box>;

    final landmarks32 = stride32['landmarks'] as List<FaceLandmarks>;

    final allScores = <double>[];
    final allBoxes = <Box>[];
    final allLandmarks = <FaceLandmarks>[];

    allScores.addAll(scores8);
    allScores.addAll(scores16);
    allScores.addAll(scores32);

    allBoxes.addAll(boxes8);
    allBoxes.addAll(boxes16);
    allBoxes.addAll(boxes32);

    allLandmarks.addAll(landmarks8);
    allLandmarks.addAll(landmarks16);
    allLandmarks.addAll(landmarks32);

    final candidates = <DetectionCandidate>[];

    for (int i = 0; i < allScores.length; i++) {
      if (allScores[i] < scoreThreshold) {
        continue;
      }

      candidates.add(
        DetectionCandidate(
          box: allBoxes[i],
          landmarks: allLandmarks[i],
          score: allScores[i],
        ),
      );
    }

    if (allScores.isEmpty) {
      for (final output in outputs.values) {
        await output.dispose();
      }

      await inputOrt.dispose();

      return [];
    }

    final sortedScores = [...allScores];
    sortedScores.sort((a, b) => b.compareTo(a));

    for (int i = 0; i < sortedScores.length && i < 20; i++) {
      print(sortedScores[i]);
    }

    print('Candidates: ${candidates.length}');

    if (candidates.isEmpty) {

      for (final output in outputs.values) {
        await output.dispose();
      }

      await inputOrt.dispose();

      return [];
    }

    final detections = nms(List.from(candidates), nmsThreshold);
    detections.sort(
      (a, b) => b.score.compareTo(a.score),
    );

    const originalWidth = 480.0;
    const originalHeight = 720.0;

    const scaleX =
        originalWidth / 640.0;

    const scaleY =
        originalHeight / 640.0;

    print(
      'FINAL DETECTIONS: '
      '${detections.length}',
    );

    if (detections.isNotEmpty) {
      final best = detections.first;

      print(
        'BOX: '
        '${best.box.x1}, '
        '${best.box.y1}, '
        '${best.box.x2}, '
        '${best.box.y2}',
      );
    }

    for (int i = 0; i < 10 && i < detections.length; i++) {
      final d = detections[i];

      final w = d.box.x2 - d.box.x1;
      final h = d.box.y2 - d.box.y1;

      print(
        'Score=${d.score} '
        'W=$w '
        'H=$h',
      );
    }

    final scaledDetections =
      detections.map((d) {
        return DetectionCandidate(
          score: d.score,

          landmarks: FaceLandmarks(
            d.landmarks.points.map((p) {
              return Landmark(
                p.x * scaleX,
                p.y * scaleY,
              );
            }).toList(),
          ),

          box: Box(
            d.box.x1 * scaleX,
            d.box.y1 * scaleY,
            d.box.x2 * scaleX,
            d.box.y2 * scaleY,
          ),
      );
    }).toList();
    for (final output in outputs.values) {
      await output.dispose();
    }

    await inputOrt.dispose();
    return scaledDetections;
  }

  Future<Map<String, dynamic>> processStride({
    required Map<String, OrtValue> outputs,
    required int stride,
  }) async {
    final bbox = await outputs['bbox_$stride']!.asFlattenedList();

    final kps = await outputs['kps_$stride']!.asFlattenedList();

    final cls = await outputs['cls_$stride']!.asFlattenedList();

    final obj = await outputs['obj_$stride']!.asFlattenedList();

    final rawBoxes = bbox.map((e) => (e as num).toDouble()).toList();

    final rawKps = kps.map((e) => (e as num).toDouble()).toList();

    final clsScores = cls.map((e) => (e as num).toDouble()).toList();

    final objScores = obj.map((e) => (e as num).toDouble()).toList();

    final priors = generateStridePriors(640, 640, stride);

    final boxes = decodeBoxes(rawBoxes, priors);

    final landmarks = decodeLandmarks(rawKps, priors);

    final scores = computeScores(clsScores, objScores);

    return {'scores': scores, 'boxes': boxes, 'landmarks': landmarks};
  }

  List<DetectionCandidate> nms(
    List<DetectionCandidate> detections,
    double threshold,
  ) {
    detections.sort((a, b) => b.score.compareTo(a.score));

    final keep = <DetectionCandidate>[];

    while (detections.isNotEmpty) {
      final current = detections.removeAt(0);

      keep.add(current);

      detections.removeWhere(
        (candidate) => computeIoU(current.box, candidate.box) > threshold,
      );
    }

    return keep;
  }
}
