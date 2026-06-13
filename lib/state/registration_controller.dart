import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_recognition_app/models/detection_candidate.dart';
import 'package:face_recognition_app/services/anti_spoof_service.dart';
import 'package:face_recognition_app/services/face_aligner_service.dart';
import 'package:face_recognition_app/services/face_database_service.dart';
import 'package:face_recognition_app/services/face_embedder_serbice.dart';
import 'package:face_recognition_app/services/yunet_preprocessor.dart';
import 'package:face_recognition_app/services/yunet_service.dart';
import 'package:face_recognition_app/utils/yuv_converter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image/image.dart' as img;

class RegistrationController extends GetxController {
  final cameraController = Rxn<CameraController>();
  var isProcessing = false.obs;
  var isInitialized = false.obs;
  final isSwitchCamera = false.obs;
  var cameraIndex = 0.obs;

  var detections = <DetectionCandidate>[].obs;

  var nameController = TextEditingController();

  img.Image? latestFrame;

  List<CameraDescription> cameras = [];

  final alignedFaceBytes = Rxn<Uint8List>();

  // services
  final yunet = YuNetService();
  final embedder = FaceEmbedderService();
  final faceAligner = FaceAlignerService();
  final spoofer = AntiSpoofService();

  @override
  Future<void> onInit() async {
    super.onInit();
  
    await yunet.initialize();
    await embedder.initialize();
    await spoofer.initialize();
    await initializeCamera();
  }

  Future<void> initializeCamera() async {
    cameras = await availableCameras();

    cameraIndex.value = cameras.indexWhere((camera) => camera.lensDirection ==     CameraLensDirection.front);

    if(cameraIndex.value == -1) {
      cameraIndex.value = 0;
    }

    await startCamera(cameraIndex.value);
  }

  Future<void> startCamera(int index) async {
    // print('Start camera');

    isProcessing.value = true;
    isInitialized.value = false;

    final oldController = cameraController.value;

    //cameraController.value = null;

    if (oldController != null) {
      // print('Dispose old camera');
      try {
        if (oldController.value.isStreamingImages) {
          await oldController.stopImageStream();
        }
      } catch (_) {}

      await oldController.dispose();
    }

    //await Future.delayed(const Duration(milliseconds: 500));

    final controller = CameraController(
      cameras[index], 
      ResolutionPreset.medium, 
      enableAudio: false
    );

    await controller.initialize();
    // print('Camera initialized');
    await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);

    cameraController.value = controller;
    // print('Controller assigned');

    await controller.startImageStream(processCameraImage);
  
    // print('Stream started');
    isInitialized.value = true;
    isProcessing.value = false;

    // print('Start camera completed');
  }

  void processCameraImage(CameraImage image) async {
    if(isSwitchCamera.value) return;
    if(isProcessing.value) return;

    final controller = cameraController.value;

    if (controller == null) return;

    if (!controller.value.isInitialized) return;

    isProcessing.value = true;

    try {
      // YUV420 -> RGB
      final rgb = YuvConverter.cameraImageToRgb(image);

      // Match preview orientation
      final isFront = cameras[cameraIndex.value].lensDirection == CameraLensDirection.front;

      final corrected = isFront
        ? img.flipHorizontal(img.copyRotate(rgb, angle: -90))
        : img.copyRotate(rgb, angle: 90);

      latestFrame = corrected;

      final inputTensor = YuNetPreprocessor.preprocess(corrected);

      final detections = await yunet.detect(inputTensor);

      //final changed = detections.length != this.detections.length;

      this.detections.assignAll(detections);
    } catch (e, st) {
      //print('ERROR: $e');
      print(st);
    } finally {
      isProcessing.value = false;
    }
  }

  Future<void> switchCamera() async {
    if(isSwitchCamera.value) return;

    isSwitchCamera.value = true;
    try {
      if (cameras.length < 2) return;
      cameraIndex.value = (cameraIndex.value + 1) % cameras.length;
      await startCamera(cameraIndex.value);
    } finally {
      isSwitchCamera.value = false;
    }
  }

  Future<void> registerFace({required BuildContext context}) async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter name first")));

      return;
    }

    if (latestFrame == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No frame available")));
      return;
    }

    if (detections.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No face detected")));

      return;
    }

    if (detections.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Multiple faces detected")));

      return;
    }

    // print("REGISTER CLICKED");
    // print("Detections = ${detections.length}");
    // print("Frame Null = ${latestFrame == null}");

    final alignedFace = faceAligner.align(latestFrame!, detections.first.landmarks);

    final spoofResult = await spoofer.detect(alignedFace);

    // print('Spoof label: ${spoofResult.label}');
    print('Spoof score: ${spoofResult.confidence}');

    if(spoofResult.confidence < 0.75 || spoofResult.label != 'Real Face') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Registration Failed: Please keep real face')),
      );
      return;
    }

    final bytes = Uint8List.fromList(img.encodeJpg(alignedFace));

    alignedFaceBytes.value = bytes;

    try {
      print("STEP 1");

      final embedding = await embedder.infer(alignedFace);

      await FaceDatabaseService.instance.saveFace(nameController.text.trim(), embedding);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${nameController.text} registered")));

      final faces = await FaceDatabaseService.instance.getAllFaces();

      print(
        "REGISTERED FACES = "
        "${faces.length}",
      );

      for (final face in faces) {
        print(face.name);
      }
    } catch (e, st) {
      print("EMBEDDER ERROR: $e");
      print('str: $st');
    }
  }

  @override
  void onClose() {
    final controller = cameraController.value;

    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          controller.stopImageStream();
        }
      } catch (_) {}

      controller.dispose();
    }

    nameController.dispose();

    yunet.dispose();
    spoofer.dispose();

    super.onClose();
  }
}