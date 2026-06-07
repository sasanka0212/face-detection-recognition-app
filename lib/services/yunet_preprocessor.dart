import 'dart:typed_data';
import 'package:image/image.dart' as img;

class YuNetPreprocessor {
  static Float32List preprocess(
    img.Image image,
  ) {
    final resized = img.copyResize(
      image,
      width: 640,
      height: 640,
    );

    final tensor = Float32List(
      1 * 3 * 640 * 640,
    );

    int redOffset = 0;
    int greenOffset = 640 * 640;
    int blueOffset = 2 * 640 * 640;

    for (int y = 0; y < 640; y++) {
      for (int x = 0; x < 640; x++) {

        final pixel =
            resized.getPixel(x, y);

        tensor[redOffset++] =
            pixel.r.toDouble();

        tensor[greenOffset++] =
            pixel.g.toDouble();

        tensor[blueOffset++] =
            pixel.b.toDouble();
      }
    }

    return tensor;
  }
}