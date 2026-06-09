import 'package:camera/camera.dart';
import 'package:face_recognition_app/models/recognition_result.dart';
import 'package:face_recognition_app/models/recognized_face.dart';
import 'package:face_recognition_app/services/face_aligner_service.dart';
import 'package:face_recognition_app/services/face_embedder_serbice.dart';
import 'package:face_recognition_app/services/face_recognition_painter.dart';
import 'package:face_recognition_app/services/yunet_preprocessor.dart';
import 'package:face_recognition_app/services/yunet_service.dart';
import 'package:face_recognition_app/state/recognition_controller.dart';
import 'package:face_recognition_app/utils/yuv_converter.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
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

  final List<RecognizedFace> _trackedFaces = []; 

  // all reconized faces
  List<RecognizedFace> _recognizedFaces = [];

  // cache the face results
  final Map<String, RecognitionResult> _faceCache = {};

  //bool _processing = false;

  int _frameCount = 0;

  bool _isProcessing = false;

  img.Image? _latestFrame;

  final RecognitionController _recognitionController = Get.put(RecognitionController());

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

  String _getFaceKey(DetectionCandidate detection) {
    final centerX = ((detection.box.x1 + detection.box.x2) / 2).round();

    final centerY = ((detection.box.y1 + detection.box.y2) / 2).round();

    return "${centerX}_$centerY";
  }

  Future<void> _processCameraImage(
    CameraImage image,
  ) async {

    if (_isProcessing) return;

    _frameCount++;

    // Run recognition every 15th frame
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
        _faceCache.clear();

        if (mounted) {
          setState(() {
            _detections = [];
            _recognizedFaces = [];
          });
        }

        return;
      }

      final recognizedFaces = <RecognizedFace>[];

      for(final detection in detections) {

        final key = _getFaceKey(detection);

        try {
          RecognitionResult result;

          // cache hit for same face
          if(_faceCache.containsKey(key)) {
            result = _faceCache[key]!;
          } else {
            RecognizedFace? tracked = findTrackedFace(detection: detection);

            //final alignedFace = _aligner.align(corrected, detection.landmarks);
            if(tracked != null) {
              recognizedFaces.add(RecognizedFace(detection: detection, name: tracked.name, score: tracked.score));
              continue;
            }
            final alignedFace = _aligner.align(corrected, detection.landmarks);

            final embedding = await _embedder.infer(alignedFace);

            result = await _recognizer.recognize(embedding);
            
            if(result.name != null) {
              _trackedFaces.add(RecognizedFace(detection: detection, name: result.name, score: result.score));

            }
          }

          recognizedFaces.add(RecognizedFace(detection: detection, name: result.name ?? "Unknown", score: result.score));
        } catch(e) {
          recognizedFaces.add(
            RecognizedFace(detection: detection, name: 'Unknown', score: 0),
          );
        }

      }
      if (!mounted) return;

      setState(() {

        _detections =
            detections;

        //_recognizedName = result.name ?? "Unknown";
        _recognizedFaces = recognizedFaces; 
        //_score = result.score;
      });

    } catch (e, st) {

      //print("RECOGNITION ERROR");
      
      print(e);
      print(st);

    } finally {

      _isProcessing = false;

    }
  }

  RecognizedFace? findTrackedFace({required DetectionCandidate detection}) {
    for(final face in _trackedFaces) {
      final distance = _recognizer.distanceSquared(detection, face.detection);
      if(distance < 2500) {
        return face;
      }
    }
    return null;
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
          Positioned.fill(child: CameraPreview(_cameraController!)),

          Positioned.fill(
            child: CustomPaint(
              painter: FaceRecognitionPainter(recognizedFaces: _recognizedFaces, imageSize: const Size(480, 720)),
            ),
          ),
        ],
      ),
    );
  }
}
