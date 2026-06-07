import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;

class FaceEmbedderService {
  late OrtSession _session;

  Future<void> initialize() async {
    final ort = OnnxRuntime();

    _session = await ort.createSessionFromAsset(
      'assets/models/mobilefacenet.onnx',
    );

    print('MOBILEFACENET LOADED');

    for (final input in _session.inputNames) {
      print('INPUT: $input');
    }
  }

  Future<List<double>> infer(
    img.Image alignedFace,
  ) async {

    print("INFER START");

    final inputTensor = _preprocess(alignedFace);
    print("PREPROCESS DONE");

    final inputOrt = await OrtValue.fromList(
      inputTensor,
      [1, 3, 112, 112],
    );
    print("INPUT CREATED");

    print("INPUT NAMES = ${_session.inputNames}");
    print("OUTPUT NAMES = ${_session.outputNames}");

    print("BEFORE RUN");

    final outputs = await _session.run({
      'input.1': inputOrt,
    });

    print("AFTER RUN");

    final output =
        outputs.values.first;

    final raw =
        await output.asFlattenedList();

    final embedding =
        raw.map(
          (e) => (e as num).toDouble(),
        ).toList();

    final normalized =
        _normalize(embedding);

    await inputOrt.dispose();

    for (final o in outputs.values) {
      await o.dispose();
    }

    return normalized;
  }

  Float32List _preprocess(
    img.Image image,
  ) {
    final resized =
        img.copyResize(
          image,
          width: 112,
          height: 112,
        );

    final data =
        Float32List(
          3 * 112 * 112,
        );

    int rIndex = 0;
    int gIndex = 112 * 112;
    int bIndex = 2 * 112 * 112;

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {

        final pixel =
            resized.getPixel(x, y);

        final r =
            pixel.r.toDouble();

        final g =
            pixel.g.toDouble();

        final b =
            pixel.b.toDouble();

        data[rIndex++] =
            (r - 127.5) / 128.0;

        data[gIndex++] =
            (g - 127.5) / 128.0;

        data[bIndex++] =
            (b - 127.5) / 128.0;
      }
    }

    return data;
  }

  List<double> _normalize(
    List<double> emb,
  ) {
    double norm = 0;

    for (final v in emb) {
      norm += v * v;
    }

    norm = sqrt(norm);

    return emb
        .map(
          (e) => e / norm,
        )
        .toList();
  }

  double cosineSimilarity(
    List<double> a,
    List<double> b,
  ) {
    double dot = 0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }

    return dot;
  }
}