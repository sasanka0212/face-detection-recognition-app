import 'package:camera/camera.dart';
import 'package:face_recognition_app/services/face_aligner_service.dart';
import 'package:face_recognition_app/services/face_embedder_serbice.dart';
import 'package:face_recognition_app/services/face_painter.dart';
import 'package:face_recognition_app/services/yunet_preprocessor.dart';
import 'package:face_recognition_app/services/yunet_service.dart';
import 'package:face_recognition_app/utils/yuv_converter.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../models/detection_candidate.dart';
import '../services/face_database_service.dart';

import '../services/face_recognition_service.dart';

class RecognitionScreen extends StatefulWidget {
  const RecognitionScreen({super.key});

  @override
  State<RecognitionScreen> createState() => _RecognitionScreenState();
}

class _RecognitionScreenState extends State<RecognitionScreen> {
  CameraController? _cameraController;

  final YuNetService _yuNet = YuNetService();

  final FaceEmbedderService _embedder = FaceEmbedderService();

  final FaceAlignerService _aligner = FaceAlignerService();

  late final FaceRecognitionService _recognizer;

  List<DetectionCandidate> _detections = [];

  String _recognizedName = "Unknown";

  double _score = 0;

  bool _processing = false;

  int _frameCount = 0;

  bool _isProcessing = false;

  img.Image? _latestFrame;

  @override
  void initState() {
    super.initState();

    _recognizer = FaceRecognitionService(FaceDatabaseService.instance);

    _initialize();
  }

  Future<void> _initialize() async {
    await FaceDatabaseService.instance.database;

    await _yuNet.initialize();

    await _embedder.initialize();

    final cameras = await availableCameras();

    final front = cameras.firstWhere(
      (e) => e.lensDirection == CameraLensDirection.front,
    );

    _cameraController = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await _cameraController!.initialize();

    await _cameraController!.startImageStream(_processCameraImage);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _processCameraImage(
    CameraImage image,
  ) async {

    if (_isProcessing) return;

    _frameCount++;

    // Run recognition every 10th frame
    if (_frameCount % 15 != 0) {
      return;
    }

    _isProcessing = true;

    try {

      final rgb =
          YuvConverter.cameraImageToRgb(
        image,
      );

      final corrected =
          img.flipHorizontal(
        img.copyRotate(
          rgb,
          angle: -90,
        ),
      );

      _latestFrame = corrected;

      final inputTensor =
          YuNetPreprocessor.preprocess(
        corrected,
      );

      final detections =
          await _yuNet.detect(
        inputTensor,
      );

      if (detections.isEmpty) {

        if (mounted) {
          setState(() {
            _detections = [];
            _recognizedName = "Unknown";
            _score = 0;
          });
        }

        return;
      }

      final alignedFace =
          _aligner.align(
        corrected,
        detections.first.landmarks,
      );

      final embedding =
          await _embedder.infer(
        alignedFace,
      );

      final result =
          await _recognizer.recognize(
        embedding,
      );

      if (!mounted) return;

      setState(() {

        _detections =
            detections;

        _recognizedName =
            result.name ??
            "Unknown";

        _score =
            result.score;
      });

    } catch (e, st) {

      //print("RECOGNITION ERROR");
      print(e);
      print(st);

    } finally {

      _isProcessing = false;

    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();

    _cameraController?.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Face Recognition')),
      body: Stack(
        children: [
          Positioned.fill(
            child: CameraPreview(
              _cameraController!,
            ),
          ),

          Positioned.fill(
            child: CustomPaint(
              painter: FacePainter(
                detections: _detections,
                imageSize: const Size(480, 720),
              ),
            ),
          ),

          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white12,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  Text(
                    _recognizedName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    "Similarity: ${_score.toStringAsFixed(3)}",
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Text(
                    _recognizedName == "Unknown"
                        ? "No registered match"
                        : "Face recognized successfully",
                    style: TextStyle(
                      color: _recognizedName == "Unknown"
                          ? Colors.orange
                          : Colors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
