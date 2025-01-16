import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceBenchmark extends StatefulWidget {
  const FaceBenchmark({super.key});

  @override
  State<FaceBenchmark> createState() => _FaceBenchmarkState();
}

class _FaceBenchmarkState extends State<FaceBenchmark> {
  List<Map<String, dynamic>> imagesWithAnnotations = [];

  @override
  void initState() {
    super.initState();
    _loadImagesAndAnnotations(); // Cargar anotaciones al iniciar
  }

  Future<void> _loadImagesAndAnnotations() async {
    try {
      final String data = await services.rootBundle.loadString('assets/wider_face_val_bbx_gt.txt');
      final List<String> lines = data.split('\n');
      List<Map<String, dynamic>> loadedImages = [];

      for (int i = 0; i < lines.length; i++) {
        final String fileName = lines[i].trim();
        if (fileName.isEmpty || !fileName.endsWith(".jpg")) continue;

        final int numBoxes = int.parse(lines[i + 1].trim());
        loadedImages.add({
          "fileName": fileName,
          "numBoxes": numBoxes
        });

        i += 1 + numBoxes;
      }

      setState(() {
        imagesWithAnnotations = loadedImages;
      });
    } catch (e) {
      print('❌ Error cargando anotaciones: $e');
    }
  }

  Future<int> _detectFaces(String imagePath) async {
    try {
      // Cargar la imagen desde assets usando rootBundle
      final data = await services.rootBundle.load('assets/images/$imagePath');
      final bytes = data.buffer.asUint8List();
      
      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(1, 1),  // Se actualizará con el tamaño real
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: 4,
        ),
      );

      final faceDetector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.accurate,
          enableLandmarks: false,
          enableContours: false,
        ),
      );

      final List<Face> faces = await faceDetector.processImage(inputImage);
      faceDetector.close();
      return faces.length;
    } catch (e) {
      print('❌ Error procesando $imagePath: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WIDER FACE Benchmark')),
      body: imagesWithAnnotations.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: imagesWithAnnotations.length,
              itemBuilder: (context, index) {
                final imageData = imagesWithAnnotations[index];
                final imagePath = imageData['fileName'];
                final expectedFaces = imageData['numBoxes'];

                return FutureBuilder<int>(
                  future: _detectFaces(imagePath),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (snapshot.hasData) {
                      final detectedFaces = snapshot.data!;
                      return ListTile(
                        title: Text(
                            "Imagen ${index + 1}: Detectados $detectedFaces rostros, Esperados $expectedFaces rostros"),
                        subtitle: Text('Path: $imagePath'),
                        trailing: detectedFaces == expectedFaces
                            ? const Icon(Icons.check_circle,
                                color: Colors.green)
                            : const Icon(Icons.error, color: Colors.red),
                      );
                    } else {
                      return ListTile(
                        title: Text("Error al procesar imagen $imagePath"),
                      );
                    }
                  },
                );
              },
            ),
    );
  }
}
