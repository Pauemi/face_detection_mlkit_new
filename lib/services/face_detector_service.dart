import 'dart:typed_data';

class FaceDetection {
  final double score;
  final double xMin;
  final double yMin;
  final double width;
  final double height;

  FaceDetection({
    required this.score,
    required this.xMin,
    required this.yMin,
    required this.width,
    required this.height,
  });
}

class FaceDetectorService {
  Future<void> init() async {
    // Inicialización del detector
  }

  Future<List<FaceDetection>> detectFaces(Uint8List imageBytes) async {
    // Implementa la lógica de detección facial aquí
    return [];
  }
} 