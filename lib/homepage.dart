// Import necessary packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ImagePicker _picker = ImagePicker();
  late FaceDetector _faceDetector;
  File? _image;
  List<Face>? _faces;
  bool _isProcessing = false;
  double? _imageWidth;
  double? _imageHeight;

  @override
  void initState() {
    super.initState();
    final options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: false,
      enableContours: true,
    );
    _faceDetector = FaceDetector(options: options);
  }

  @override
  void dispose() {
    _faceDetector.close();
    super.dispose();
  }

  Future<void> _pickImageFromGallery() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _isProcessing = true;
      });
      await _getImageDimensions();
      _detectFaces();
    }
  }

  Future<void> _pickImageFromCamera() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.camera);
    if (pickedFile != null) {
      setState(() {
        _image = File(pickedFile.path);
        _isProcessing = true;
      });
      await _getImageDimensions();
      _detectFaces();
    }
  }

  Future<void> _getImageDimensions() async {
    if (_image == null) return;
    final decodedImage = await decodeImageFromList(_image!.readAsBytesSync());
    setState(() {
      _imageWidth = decodedImage.width.toDouble();
      _imageHeight = decodedImage.height.toDouble();
    });
  }

  Future<void> _detectFaces() async {
    if (_image == null) return;

    final inputImage = InputImage.fromFile(_image!);
    final faces = await _faceDetector.processImage(inputImage);

    setState(() {
      _faces = faces;
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: const Text('Detección de Rostros'),
      ),
      body: Column(
        children: [
          if (_faces != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text('Número de rostros detectados: ${_faces!.length}'),
            ),
          if (_image != null && _imageWidth != null && _imageHeight != null)
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final double scaleX = constraints.maxWidth / _imageWidth!;
                  final double scaleY = constraints.maxHeight / _imageHeight!;
                  final double scale = scaleX < scaleY ? scaleX : scaleY;
                  final double offsetX = (constraints.maxWidth - (_imageWidth! * scale)) / 2;
                  final double offsetY = (constraints.maxHeight - (_imageHeight! * scale)) / 2;

                  return Stack(
                    children: [
                      Center(
                        child: Image.file(
                          _image!,
                          fit: BoxFit.contain,
                          width: _imageWidth! * scale,
                          height: _imageHeight! * scale,
                        ),
                      ),
                      if (_faces != null)
                        for (var face in _faces!)
                          Positioned(
                            left: face.boundingBox.left * scale + offsetX,
                            top: face.boundingBox.top * scale + offsetY,
                            width: face.boundingBox.width * scale,
                            height: face.boundingBox.height * scale,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.red, width: 2),
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          if (_isProcessing)
            const CircularProgressIndicator(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _pickImageFromCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Usar Cámara'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _pickImageFromGallery,
                icon: const Icon(Icons.photo),
                label: const Text('Galería'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
