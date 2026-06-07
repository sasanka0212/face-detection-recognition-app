import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_recognition_app/models/detection_candidate.dart';
import 'package:face_recognition_app/services/face_aligner_service.dart';
import 'package:face_recognition_app/services/face_database_service.dart';
import 'package:face_recognition_app/services/face_embedder_serbice.dart';
import 'package:face_recognition_app/services/face_painter.dart';
import 'package:face_recognition_app/services/yunet_postprocess.dart';
import 'package:face_recognition_app/services/yunet_preprocessor.dart';
import 'package:face_recognition_app/services/yunet_service.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../utils/yuv_converter.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:math';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? controller;
  bool _isProcessing = false;
  bool _savedFrame = false;
  List<DetectionCandidate> _detections = [];
  Uint8List? _alignedFaceBytes;
  final TextEditingController _nameController = TextEditingController();

  img.Image? _latestFrame;

  // services
  final _yuNet = YuNetService();
  final _embedder = FaceEmbedderService();
  final _faceAlignService = FaceAlignerService();
  final _faceDb = FaceDatabaseService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _yuNet.initialize();
    await _embedder.initialize();
    await _faceDb.initialize();
    await initializeCamera();
  }

  Future<void> initializeCamera() async {
    final cameras = await availableCameras();

    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    await controller!.initialize();
    await controller!.startImageStream(_processCameraImage);

    if (mounted) {
      setState(() {});
    }
  }

  void _processCameraImage(CameraImage image) async {
    if (_isProcessing) return;

    _isProcessing = true;

    try {
      // YUV420 -> RGB
      final rgb = YuvConverter.cameraImageToRgb(image);

      // Match preview orientation
      final corrected = img.flipHorizontal(img.copyRotate(rgb, angle: -90));
      _latestFrame = corrected;

      // Save one debug image
      if (!_savedFrame) {
        print('Corrected Image: ${corrected.width} x ${corrected.height}');

        final jpgBytes = img.encodeJpg(corrected, quality: 95);

        final directory = await getExternalStorageDirectory();

        print('DIR = ${directory?.path}');

        if (directory != null) {
          final file = File('${directory.path}/test_frame.jpg');

          await file.writeAsBytes(jpgBytes);

          print('====================');
          print('IMAGE SAVED');
          print(file.path);
          print('FILE EXISTS = ${await file.exists()}');
          print('====================');

          _savedFrame = true;
        }
      }

      final inputTensor = YuNetPreprocessor.preprocess(corrected);

      final detections = await _yuNet.detect(inputTensor);

      /* if (detections.isNotEmpty) {
        final alignedFace = _debugAlignFace(
          image: corrected,
          detection: detections.first,
        );

        _alignedFaceBytes =
            Uint8List.fromList(
              img.encodeJpg(alignedFace),
            );
      } */

      if (mounted & detections.isNotEmpty) {
        setState(() {
          _detections = detections;
        });
      }

      print('Tensor Length: ${inputTensor.length}');
    } catch (e, st) {
      print('ERROR: $e');
      print(st);
    } finally {
      _isProcessing = false;
    }
  }

  img.Image _debugAlignFace({
    required img.Image image,
    required DetectionCandidate detection,
  }) {
    final xs = detection.landmarks.points.map((e) => e.x);

    final ys = detection.landmarks.points.map((e) => e.y);

    final minX = xs.reduce(min);
    final maxX = xs.reduce(max);

    final minY = ys.reduce(min);
    final maxY = ys.reduce(max);

    final width = maxX - minX;
    final height = maxY - minY;

    final paddingX = width * 1.2;
    final paddingY = height * 1.8;

    final cropX = max(0, (minX - paddingX).toInt());

    final cropY = max(0, (minY - paddingY).toInt());

    final cropW = min(image.width - cropX, (width + paddingX * 2).toInt());

    final cropH = min(image.height - cropY, (height + paddingY * 2).toInt());

    final cropped = img.copyCrop(
      image,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    return img.copyResize(cropped, width: 112, height: 112);
  }

  Future<void> _registerFace() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Enter name first")));

      return;
    }

    if (_latestFrame == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No frame available")));

      return;
    }

    if (_detections.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("No face detected")));

      return;
    }

    if (_detections.length > 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Multiple faces detected")));

      return;
    }

    print("REGISTER CLICKED");
    print("Detections = ${_detections.length}");
    print("Frame Null = ${_latestFrame == null}");

    final alignedFace = _faceAlignService.align(
      _latestFrame!,
      _detections.first.landmarks,
    );

    final bytes = Uint8List.fromList(img.encodeJpg(alignedFace));

    setState(() {
      _alignedFaceBytes = bytes;
    });

    try {
      print("STEP 1");

      final embedding = await _embedder.infer(alignedFace);

      await _faceDb.saveFace(
        _nameController.text.trim(),
        embedding,
      );

      ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text(
              "${_nameController.text} registered",
          ),
        ),
      );

      final faces =
        await _faceDb.getAllFaces();

      print(
        "REGISTERED FACES = "
        "${faces.length}",
      );

      for(final face in faces){
        print(face.name);
      }

      // final sim = _embedder.cosineSimilarity(emb1, emb2);

      /* print(
        "Embedding Length = ${embedding.length}",
      );
      print(
        'embedding list: ${embedding.take(20).toList()}',
      ); */
    } catch (e, st) {
      print("EMBEDDER ERROR");
      print(e);
      print('str: $st');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null || !controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          /// Camera Preview
          Positioned.fill(child: CameraPreview(controller!)),

          /// aligned face
          if (_alignedFaceBytes != null)
            Positioned(
              top: 120,
              right: 20,
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                ),
                child: Image.memory(_alignedFaceBytes!, fit: BoxFit.cover),
              ),
            ),

          /// Face Boxes
          Positioned.fill(
            child: CustomPaint(
              painter: FacePainter(
                detections: _detections,
                imageSize: const Size(480, 720),
              ),
            ),
          ),

          /// Top App Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.45),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.face, color: Colors.green, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Face Detection",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.45),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          "${_detections.length}",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          /// Center Detection Target
          Center(
            child: Container(
              width: 260,
              height: 320,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.white.withOpacity(.7),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),

          Positioned(
            left: 20,
            right: 20,
            bottom: 180,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.7),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Enter Name",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(.6)),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _registerFace,
                      child: const Text("Register Face"),
                    ),
                  ),
                ],
              ),
            ),
          ),

          /// Bottom Status Card
          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Icon(
                        _detections.isNotEmpty
                            ? Icons.check_circle
                            : Icons.search,
                        color: _detections.isNotEmpty
                            ? Colors.green
                            : Colors.orange,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _detections.isNotEmpty
                              ? "Face Detected"
                              : "Searching for face...",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoTile("Faces", _detections.length.toString()),
                      _buildInfoTile("Camera", "Front"),
                      _buildInfoTile("Model", "YuNet"),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: IconButton(onPressed: () => _faceDb.exportDb(), icon: Icon(Icons.download)),
    );
  }

  Widget _buildInfoTile(String title, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12),
        ),
      ],
    );
  }
}
