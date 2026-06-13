import 'dart:math';
import 'dart:typed_data';
import 'package:face_recognition_app/runtime/smart_onnx_model_manager.dart';
import 'package:flutter/services.dart';

import 'package:image/image.dart' as img;
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';

import '../models/anti_spoof_result.dart';

class AntiSpoofService {
  late OrtSession _session;

  Future<void> initialize() async {
    final data = await rootBundle.load('assets/models/4_0_0_80x80_MiniFASNetV1SE.onnx');

    print('ANTI SPOOF MODEL SIZE = ${data.lengthInBytes}');

    _session = await SmartOnnxModelManager.getModel(
      key: 'fasnet',
      modelPath: 'assets/models/4_0_0_80x80_MiniFASNetV1SE.onnx',
    );
    //print('session spoof input: ${_session.inputNames}');
    //print('session output names: ${_session.outputNames}');
  }

  Future<AntiSpoofResult> detect(img.Image faceImage) async {

    final resized = img.copyResize(faceImage, width: 80, height: 80);

    final input = Float32List(1 * 3 * 80 * 80);

    int offset = 0;

    // CHW format
    for (int c = 0; c < 3; c++) {
      for (int y = 0; y < 80; y++) {
        for (int x = 0; x < 80; x++) {
          final pixel = resized.getPixel(x, y);

          double value;

          switch (c) {
            case 0:
              value = pixel.r.toDouble();
              break;
            case 1:
              value = pixel.g.toDouble();
              break;
            default:
              value = pixel.b.toDouble();
          }

          input[offset++] = value;
        }
      }
    }

    final tensor = await OrtValue.fromList(input, [1, 3, 80, 80]);

    // print('Spoof start');
    final outputs = await _session!.run({'input': tensor});
    // print('Spoof end');

    final output = await outputs['output']!.asFlattenedList();

    // print('Anti Spoof raw output: ${output}');

    final logits = output.map((e) => (e as num).toDouble()).toList();

    final scores = _softmax(logits);

    const labels = ['Paper Photo', 'Real Face', 'Screen Photo'];

    int bestIdx = 0;

    for (int i = 1; i < scores.length; i++) {
      if (scores[i] > scores[bestIdx]) {
        bestIdx = i;
      }
    }

    final result = AntiSpoofResult(label: labels[bestIdx], confidence: scores[bestIdx]);

    await tensor.dispose();

    for (final o in outputs.values) {
      await o.dispose();
    }

    return result;
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce(max);

    final exps = logits.map((e) => exp(e - maxLogit)).toList();

    final sum = exps.reduce((a, b) => a + b);

    return exps.map((e) => e / sum).toList();
  }

  Future<void> dispose() async {
    await SmartOnnxModelManager.unload('fasnet');
  }
}
