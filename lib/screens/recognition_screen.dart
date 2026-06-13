import 'package:camera/camera.dart';
import 'package:face_recognition_app/models/recognition_result.dart';
import 'package:face_recognition_app/models/recognized_face.dart';
import 'package:face_recognition_app/services/anti_spoof_service.dart';
import 'package:face_recognition_app/services/face_aligner_service.dart';
import 'package:face_recognition_app/services/face_embedder_serbice.dart';
import 'package:face_recognition_app/services/face_recognition_painter.dart';
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

  final AntiSpoofService _spoofService = AntiSpoofService();

  late final FaceRecognitionService _recognizer;

  List<DetectionCandidate> _detections = [];

  final List<RecognizedFace> _trackedFaces = [];
  List<CameraDescription> _cameras = []; 
  int _cameraIndex = 0;
  bool _isInitialized = false;
  bool _isProcessing = false;
  bool _isSwitchingCamera = false;

  // all reconized faces
  List<RecognizedFace> _recognizedFaces = [];

  // cache the face results
  final Map<String, RecognitionResult> _faceCache = {};

  // spoof cache
  final Map<String, bool> _spoofCache = {};

  //bool _processing = false;

  int _frameCount = 0;

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

    await _spoofService.initialize();

    _cameras = await availableCameras();
    _cameraIndex = _cameras.indexWhere((camera) => camera.lensDirection == CameraLensDirection.front);
    if(_cameraIndex == -1) {
      setState(() => _cameraIndex = 0);
    }

    await startCamera(_cameraIndex);
  }

  Future<void> startCamera(int index) async {
    _isProcessing = false;  

    final oldController = _cameraController;
    _cameraController = null;

    if (oldController != null) {
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}

      await oldController.dispose();
    }

    final controller = CameraController(_cameras[index], ResolutionPreset.medium, enableAudio: false);

    _cameraController = controller;

    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    await controller.startImageStream(_processCameraImage);

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
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
    if (_isSwitchingCamera) return;

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

      final front = _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
      final corrected = front 
        ?  img.flipHorizontal(
            img.copyRotate(
              rgb,
              angle: -90,
            ),
          )
        : img.copyRotate(
          rgb,
          angle: 90,
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
          //RecognitionResult result;
  
          final tracked = findTrackedFace(detection: detection);

          //final alignedFace = _aligner.align(corrected, detection.landmarks);
          if(tracked != null && tracked.name != "Unknown" && tracked.name != 'Fake') {
            recognizedFaces.add(RecognizedFace(detection: detection, name: tracked.name, score: tracked.score, isReal: tracked.isReal, spoofScore: tracked.spoofScore));
            continue;
          }
          final alignedFace = _aligner.align(corrected, detection.landmarks);

          bool isReal;
          double spoofScore;

          final spoofResult = await _spoofService.detect(alignedFace);
          isReal = (spoofResult.label == 'Real Face') && (spoofResult.confidence >= 0.75);

          spoofScore = spoofResult.confidence;

          //_spoofCache[key] = isReal;

          if (!isReal) {
            final spoofFace = RecognizedFace(detection: detection, name: 'Fake', score: 0, isReal: false, spoofScore: spoofScore);

            //_trackedFaces.add(spoofFace);
            //recognizedFaces.add(spoofFace);

            continue;
          }

          /* if(_spoofCache.containsKey(key)) {
            isReal = _spoofCache[key]!;
            spoofScore = 1.0;
          } else { 
            final spoofResult = await _spoofService.detect(alignedFace);
            isReal = (spoofResult.label == 'Real Face') && (spoofResult.confidence >= 0.75);

            spoofScore = spoofResult.confidence;

            _spoofCache[key] = isReal;

            if (!isReal) {
              final spoofFace = RecognizedFace(detection: detection, name: 'Fake', score: 0, isReal: false, spoofScore: spoofScore);

              _trackedFaces.add(spoofFace);
              recognizedFaces.add(spoofFace);

              continue;
            } 
          } */

          RecognitionResult result;
          if(_faceCache.containsKey(key)) {
            result = _faceCache[key]!;
          } else {
            final embedding = await _embedder.infer(alignedFace);

            result = await _recognizer.recognize(embedding);
            _faceCache[key] = result;
          }
          final recognizedFace = RecognizedFace(
            detection: detection, 
            name: result.name ?? 'Unknown', 
            score: result.score, 
            isReal: isReal, 
            spoofScore: spoofScore,
          );

          updateTrackedFace(recognizedFace);
          recognizedFaces.add(recognizedFace);
        } catch(e) {
          recognizedFaces.add(
            RecognizedFace(detection: detection, name: 'Unknown', score: 0, isReal: false, spoofScore: 0),
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

  void updateTrackedFace(RecognizedFace face) {
    _trackedFaces.removeWhere((f) => _recognizer.distanceSquared(face.detection, f.detection) < 2500);

    _trackedFaces.add(face);
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

  Future<void> switchCamera() async {
    if (_cameras.length < 2) return;

    setState(() {
      _isSwitchingCamera = true;
    });

    _trackedFaces.clear();
    _faceCache.clear();
    _spoofCache.clear();
    
    _frameCount = 0;

    setState(() {
      _recognizedFaces = [];
      _detections = [];
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    });

    await startCamera(_cameraIndex);

    if (mounted) {
      setState(() {
        _isSwitchingCamera = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();

    _cameraController?.dispose();

    _yuNet.dispose();

    _spoofService.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator())
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Face Recognition')),
      body: Stack(
        children: [
          Positioned.fill(
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _cameraController!.value.previewSize!.height,
                  height: _cameraController!.value.previewSize!.width,
                  child: CameraPreview(_cameraController!),
                ),
              ),
            ),
          ),

          Positioned.fill(
            child: CustomPaint(
              painter: FaceRecognitionPainter(recognizedFaces: _recognizedFaces, imageSize: const Size(480, 720)),
            ),
          ),

          Positioned(
            top: 110,
            right: 20,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: switchCamera,
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.65),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.flip_camera_android, color: Colors.white, size: 28),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
