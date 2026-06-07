import 'dart:math';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class YuvConverter {
  static img.Image cameraImageToRgb(
    CameraImage image,
  ) {
    final width = image.width;
    final height = image.height;

    final rgbImage = img.Image(
      width: width,
      height: height,
    );

    final yPlane = image.planes[0];
    final uPlane = image.planes[1];
    final vPlane = image.planes[2];

    final yBytes = yPlane.bytes;
    final uBytes = uPlane.bytes;
    final vBytes = vPlane.bytes;

    final yRowStride = yPlane.bytesPerRow;

    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride =
        uPlane.bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {

        final yIndex =
            y * yRowStride + x;

        final uvIndex =
            (y ~/ 2) * uvRowStride +
            (x ~/ 2) * uvPixelStride;

        final Y = yBytes[yIndex];

        final U = uBytes[uvIndex];
        final V = vBytes[uvIndex];

        int r = (Y +
                1.402 * (V - 128))
            .round();

        int g = (Y -
                0.344136 * (U - 128) -
                0.714136 * (V - 128))
            .round();

        int b = (Y +
                1.772 * (U - 128))
            .round();

        r = min(255, max(0, r));
        g = min(255, max(0, g));
        b = min(255, max(0, b));

        rgbImage.setPixelRgb(
          x,
          y,
          r,
          g,
          b,
        );
      }
    }

    return rgbImage;
  }
}