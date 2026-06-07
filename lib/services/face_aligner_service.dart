import 'package:image/image.dart' as img;

import '../models/face_land_marks.dart';

class FaceAlignerService {
  static const List<List<double>> arcFaceDst = [
    [38.2946, 51.6963],
    [73.5318, 51.5014],
    [56.0252, 71.7366],
    [41.5493, 92.3655],
    [70.7299, 92.2041],
  ];

    img.Image align(
    img.Image image,
    FaceLandmarks landmarks,
  ) {

    final matrix =
        _estimateAffine(
          landmarks,
        );

    return _warpAffine(
      image,
      matrix,
      112,
      112,
    );
  }

    List<List<double>> _estimateAffine(
    FaceLandmarks landmarks,
  ) {

    final src =
        landmarks.points;

    final rows = <List<double>>[];
    final values = <double>[];

    for (int i = 0; i < 5; i++) {

      final x = src[i].x;
      final y = src[i].y;

      final dx = arcFaceDst[i][0];
      final dy = arcFaceDst[i][1];

      rows.add([
        x,
        -y,
        1,
        0,
      ]);

      values.add(dx);

      rows.add([
        y,
        x,
        0,
        1,
      ]);

      values.add(dy);
    }

    final params =
        _leastSquares(
          rows,
          values,
        );

    final a = params[0];
    final b = params[1];
    final tx = params[2];
    final ty = params[3];

    return [
      [a, -b, tx],
      [b, a, ty],
    ];
  }

    List<double> _leastSquares(
    List<List<double>> A,
    List<double> B,
  ) {

    final ata =
        List.generate(
          4,
          (_) => List.filled(4, 0.0),
        );

    final atb =
        List.filled(4, 0.0);

    for (int r = 0; r < A.length; r++) {

      for (int i = 0; i < 4; i++) {

        atb[i] += A[r][i] * B[r];

        for (int j = 0; j < 4; j++) {
          ata[i][j] +=
              A[r][i] * A[r][j];
        }
      }
    }

    return _solve4x4(
      ata,
      atb,
    );
  }

    List<double> _solve4x4(
    List<List<double>> A,
    List<double> b,
  ) {

    for (int i = 0; i < 4; i++) {

      double pivot =
          A[i][i];

      for (int j = i; j < 4; j++) {
        A[i][j] /= pivot;
      }

      b[i] /= pivot;

      for (int k = 0; k < 4; k++) {

        if (k == i) continue;

        final factor =
            A[k][i];

        for (int j = i; j < 4; j++) {
          A[k][j] -=
              factor * A[i][j];
        }

        b[k] -= factor * b[i];
      }
    }

    return b;
  }

    img.Image _warpAffine(
    img.Image image,
    List<List<double>> M,
    int outW,
    int outH,
  ) {

    final output =
        img.Image(
          width: outW,
          height: outH,
        );

    final inv =
        _invertAffine(M);

    for (int y = 0; y < outH; y++) {

      for (int x = 0; x < outW; x++) {

        final sx =
            inv[0][0] * x +
            inv[0][1] * y +
            inv[0][2];

        final sy =
            inv[1][0] * x +
            inv[1][1] * y +
            inv[1][2];

        final ix =
            sx.round();

        final iy =
            sy.round();

        if (ix >= 0 &&
            ix < image.width &&
            iy >= 0 &&
            iy < image.height) {

          output.setPixel(
            x,
            y,
            image.getPixel(
              ix,
              iy,
            ),
          );
        }
      }
    }

    return output;
  }

  List<List<double>> _invertAffine(
    List<List<double>> M,
  ) {

    final a = M[0][0];
    final b = M[0][1];
    final tx = M[0][2];

    final c = M[1][0];
    final d = M[1][1];
    final ty = M[1][2];

    final det =
        a * d - b * c;

    return [
      [
        d / det,
        -b / det,
        (b * ty - d * tx) / det,
      ],
      [
        -c / det,
        a / det,
        (c * tx - a * ty) / det,
      ],
    ];
  }
}
