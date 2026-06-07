# Face Recognition App

A real-time offline Face Detection and Recognition application built with Flutter and Python. The application performs face detection, alignment, embedding extraction, and recognition directly on the device without requiring an internet connection.

---

## Features

- Real-time face detection from camera feed
- Face alignment for improved recognition accuracy
- Face registration/enrollment
- Offline face recognition using facial embeddings
- Local SQLite database storage
- ONNX model inference on-device
- Fast and privacy-focused authentication
- Cross-platform Flutter application

---

# Tech Stack

## Frontend
- Flutter
- Dart

## Computer Vision & AI
- Python
- OpenCV
- ONNX Runtime
- NumPy

## Database
- SQLite

---

# Platform Support

| Platform | Status |
|-----------|----------|
| Android | ✅ Supported |
| iOS | 🚧 Planned |

---

# Project Architecture

```text
Camera Feed
      │
      ▼
Face Detection (ONNX Model)
      │
      ▼
Face Alignment
      │
      ▼
Embedding Extraction
      │
      ▼
SQLite Storage / Retrieval
      │
      ▼
Cosine Similarity Matching
      │
      ▼
Recognition Result
```

---

# Prerequisites

Before running the project, ensure you have:

### Flutter

```bash
flutter --version
```

Flutter SDK 3.x or later is recommended.

### Python

```bash
python --version
```

Python 3.10+ recommended.

### Android Studio

- Android SDK
- Emulator or Physical Device
- USB Debugging enabled

---

# Setup Instructions

## 1. Clone Repository

```bash
git clone https://github.com/your-username/face-recognition-app.git
cd face-recognition-app
```

---

## 2. Install Flutter Dependencies

```bash
flutter pub get
```

## 3. Download Models

Place ONNX models inside:

```text
assets/models/
```

Example:

```text
assets/models/
├── face_detection.onnx
├── face_recognition.onnx
```

---

## 4. Configure Assets

Update `pubspec.yaml`

```yaml
flutter:
  assets:
    - assets/models/
```

Run:

```bash
flutter pub get
```

---

## 5. Run Application

```bash
flutter run
```

For a specific device:

```bash
flutter devices
flutter run -d <device-id>
```

---

# Database

The application stores:

- User information
- Face embeddings
- Registration metadata

Database used:

```text
SQLite
```

Example:

```text
faces.db
```

---

# Performance Highlights

- Fully offline recognition
- On-device inference
- Low-latency processing
- Privacy-preserving biometric authentication
- Optimized for mobile devices

---

# Future Improvements

- Multi-face recognition
- iOS support
- Cloud synchronization
- User management dashboard

---

# Author

**Sasanka Kundu**