import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:face_recognition_app/models/detection_candidate.dart';
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

  @override
  Future<void> onInit() async {
    super.onInit();
  
    await yunet.initialize();
    await embedder.initialize();
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
    isProcessing.value = false;

    final oldController = cameraController;

    cameraController.value = null;

    if (oldController.value != null) {
      try {
        await oldController.value!.stopImageStream();
      } catch (e) {
        // Image stream not active
      }

      await oldController.value!.dispose();
    }

    cameraController.value = CameraController(
      cameras[index], 
      ResolutionPreset.medium, 
      enableAudio: false
    );

    await cameraController.value!.initialize();
    await cameraController.value!.lockCaptureOrientation(DeviceOrientation.portraitUp);
    await cameraController.value!.startImageStream(processCameraImage);
  
    isInitialized.value = true;
  }

  void processCameraImage(CameraImage image) async {
    if (isProcessing.value) return;

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

  void switchCamera() async {
    if (cameras.length < 2) return;
    cameraIndex.value = (cameraIndex.value + 1) % cameras.length;
    await startCamera(cameraIndex.value);
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

    print("REGISTER CLICKED");
    print("Detections = ${detections.length}");
    print("Frame Null = ${latestFrame == null}");

    final alignedFace = faceAligner.align(latestFrame!, detections.first.landmarks);

    final bytes = Uint8List.fromList(img.encodeJpg(alignedFace));

    alignedFaceBytes.value = bytes;

    try {
      //print("STEP 1");

      final embedding = await embedder.infer(alignedFace);

      await FaceDatabaseService.instance.saveFace(nameController.text.trim(), embedding);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("${nameController.text} registered")));

      //final faces = await FaceDatabaseService.instance.getAllFaces();

      /* print(
        "REGISTERED FACES = "
        "${faces.length}",
      ); */

      /* for (final face in faces) {
        print(face.name);
      } */
    } catch (e, st) {
      //print("EMBEDDER ERROR");
      //print(e);
      print('str: $st');
    }
  }

  @override
  void onClose() {
    cameraController.value?.stopImageStream();
    cameraController.value?.dispose();
    nameController.dispose();
    super.onClose();
  }
}