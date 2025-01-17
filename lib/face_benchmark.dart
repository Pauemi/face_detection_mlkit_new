import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class FaceBenchmark extends StatefulWidget {
  const FaceBenchmark({super.key});

  @override
  State<FaceBenchmark> createState() => _FaceBenchmarkState();
}

class _FaceBenchmarkState extends State<FaceBenchmark> {
  final List<BenchmarkResult> results = [];
  bool isRunning = false;
  double progress = 0.0;
  double averageIoU = 0.0;
  int totalTruePositives = 0;
  int totalFalsePositives = 0;
  int totalFalseNegatives = 0;
  final Stopwatch stopwatch = Stopwatch();

  // Instancia única de FaceDetector
  late final FaceDetector faceDetector;

  // Variable para almacenar el archivo CSV
  File? csvFile;

  @override
  void initState() {
    super.initState();
    faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: false,
        enableContours: false,
        minFaceSize: 0.05, // Reducir si las caras son pequeñas
      ),
    );
  }

  @override
  void dispose() {
    faceDetector.close();
    super.dispose();
  }

  // Obtener dimensiones originales de la imagen
  Future<Size> getImageSize(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    final img.Image? image = img.decodeImage(bytes);
    if (image != null) {
      return Size(image.width.toDouble(), image.height.toDouble());
    } else {
      throw Exception('No se pudo decodificar la imagen.');
    }
  }

  // Preparar InputImage y obtener dimensiones originales
  Future<Map<String, dynamic>> _prepareInputImage(String assetPath) async {
    try {
      print('📂 Cargando imagen desde assets...');
      final ByteData data = await rootBundle.load('assets/images/$assetPath');
      final Uint8List bytes = data.buffer.asUint8List();

      // Obtener dimensiones originales
      final img.Image? originalImage = img.decodeImage(bytes);
      if (originalImage == null)
        throw Exception('No se pudo decodificar la imagen.');

      final double originalWidth = originalImage.width.toDouble();
      final double originalHeight = originalImage.height.toDouble();

      // Guarda la imagen en un archivo temporal
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${assetPath.split('/').last}';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      // Corrige la orientación usando EXIF
      final rotatedFile = await FlutterExifRotation.rotateImage(path: tempPath);

      print('📸 Creando InputImage desde archivo rotado...');
      final inputImage = InputImage.fromFile(rotatedFile);

      return {
        'inputImage': inputImage,
        'originalWidth': originalWidth,
        'originalHeight': originalHeight,
      };
    } catch (e) {
      print('❌ Error preparando InputImage: $e');
      rethrow;
    }
  }

  Future<String> getDownloadsPath() async {
    if (Platform.isAndroid) {
      // En Android, usamos la carpeta de descargas pública
      final directory = Directory('/storage/emulated/0/Download');
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory.path;
    } else if (Platform.isIOS) {
      // En iOS, obtenemos la carpeta de descargas
      final paths = await getApplicationDocumentsDirectory();
      final downloadsPath = '${paths.path}/Downloads';
      final downloadsDir = Directory(downloadsPath);
      if (!await downloadsDir.exists()) {
        await downloadsDir.create(recursive: true);
      }
      return downloadsPath;
    }
    throw UnsupportedError('Plataforma no soportada');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WiderFace Benchmark')),
      body: Column(
        children: [
          if (isRunning) LinearProgressIndicator(value: progress),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Text('IoU Promedio: ${averageIoU.toStringAsFixed(3)}'),
                Text('Verdaderos Positivos: $totalTruePositives'),
                Text('Falsos Positivos: $totalFalsePositives'),
                Text('Falsos Negativos: $totalFalseNegatives'),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: isRunning ? null : _runBenchmark,
            child: Text(isRunning ? 'Ejecutando...' : 'Iniciar Benchmark'),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (context, index) {
                final result = results[index];
                return ListTile(
                  title: Text(result.imageName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Ground Truth: ${result.groundTruth} | Detectado: ${result.detected}'),
                      Text('IoU: ${result.iou.toStringAsFixed(3)}'),
                      Text(
                          'TP: ${result.truePositives} | FP: ${result.falsePositives} | FN: ${result.falseNegatives}'),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runBenchmark() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se requieren permisos de almacenamiento para guardar el archivo CSV'),
          ),
        );
        return;
      }
    }
    
    print('🚀 Iniciando benchmark...');
    stopwatch.reset();
    stopwatch.start();
    setState(() {
      isRunning = true;
      results.clear();
      averageIoU = 0.0;
      totalTruePositives = 0;
      totalFalsePositives = 0;
      totalFalseNegatives = 0;
      progress = 0.0;
    });

    try {
      print('📂 Intentando cargar archivo de anotaciones...');
      final String data =
          await rootBundle.loadString('assets/wider_face_val_bbx_gt.txt');
      final List<String> lines = data.split('\n');
      print('✅ Archivo de anotaciones cargado exitosamente');

      int totalImages = 0;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trim().endsWith('.jpg')) totalImages++;
      }
      print('📊 Total de imágenes a procesar: $totalImages');

      // Modificar esta parte para usar la carpeta de descargas
      final outputPath = await getDownloadsPath();
      
      // Generar un timestamp para el nombre del archivo
      final timestamp = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
      final fileName = 'benchmark_results_$timestamp.csv';
      final file = File('$outputPath/$fileName');

      // Crear archivo con headers
      await file.writeAsString(
          'image_path,ground_truth,detected,iou,true_pos,false_pos,false_neg,precision,recall,f1_score,processing_time_ms\n');

      // Asignar el archivo a la variable csvFile
      csvFile = file;

      int processedImages = 0;

      for (int i = 0; i < lines.length; i++) {
        final String imageName = lines[i].trim();
        if (!imageName.endsWith('.jpg')) continue;

        print('🖼️ Procesando imagen: $imageName');

        // Verificar que haya suficientes líneas para groundTruth y bounding boxes
        if (i + 1 >= lines.length) {
          print(
              '❌ Datos insuficientes para groundTruth de la imagen $imageName. Saltando esta imagen.');
          continue;
        }

        final int groundTruth;
        try {
          groundTruth = int.parse(lines[i + 1].trim());
        } catch (e) {
          print(
              '❌ Error al parsear groundTruth para la imagen $imageName: $e. Saltando esta imagen.');
          continue;
        }

        print('📝 Ground Truth faces: $groundTruth');

        try {
          print('🔍 Iniciando detección de caras...');
          stopwatch.reset();
          stopwatch.start();

          // Obtener InputImage y dimensiones originales
          final Map<String, dynamic> preparation =
              await _prepareInputImage(imageName);
          final InputImage inputImage = preparation['inputImage'];
          final double originalWidth = preparation['originalWidth'];
          final double originalHeight = preparation['originalHeight'];

          final List<BoundingBox> groundTruthBoxes = [];
          for (int j = 0; j < groundTruth; j++) {
            if (i + 2 + j >= lines.length) {
              print(
                  '❌ Datos insuficientes para las cajas de la imagen $imageName. Saltando esta caja.');
              continue;
            }
            final List<String> coords =
                lines[i + 2 + j].trim().split(RegExp(r'\s+'));
            if (coords.length < 4) {
              print(
                  '❌ Datos insuficientes para las coordenadas de la caja en la imagen $imageName. Saltando esta caja.');
              continue;
            }
            try {
              groundTruthBoxes.add(BoundingBox(
                x: double.parse(coords[0]),
                y: double.parse(coords[1]),
                width: double.parse(coords[2]),
                height: double.parse(coords[3]),
              ));
            } catch (e) {
              print(
                  '❌ Error al parsear coordenadas para la caja en la imagen $imageName: $e. Saltando esta caja.');
              continue;
            }
          }

          final List<BoundingBox> detectedBoxes =
              await _detectFaces(inputImage);

          // Obtener dimensiones escaladas (si las hay)
          // En este ejemplo, asumimos que no hay redimensionamiento.
          double scaledWidth = originalWidth;
          double scaledHeight = originalHeight;

          // Si decides redimensionar la imagen, ajusta scaledWidth y scaledHeight
          // y aplica el escalado a las Bounding Boxes detectadas.
          // Por ejemplo:
          // scaledWidth = 800;
          // scaledHeight = (originalHeight / originalWidth) * 800;
          // detectedBoxes = scaleBoundingBoxes(detectedBoxes, scaleX, scaleY);

          double scaleX = originalWidth / scaledWidth;
          double scaleY = originalHeight / scaledHeight;

          // Ajustar las Bounding Boxes detectadas si hay escalado
          List<BoundingBox> adjustedDetectedBoxes = detectedBoxes
              .map((box) => BoundingBox(
                    x: box.x * scaleX,
                    y: box.y * scaleY,
                    width: box.width * scaleX,
                    height: box.height * scaleY,
                  ))
              .toList();

          double totalIoU = 0.0;
          int truePositives = 0;
          int falsePositives = 0;

          // Comparar cada caja detectada con las cajas ground truth
          for (var detectedBox in adjustedDetectedBoxes) {
            double maxIoU = 0.0;
            BoundingBox? matchedGtBox;

            for (var groundTruthBox in groundTruthBoxes) {
              final iou = calculateIoU(detectedBox, groundTruthBox);
              if (iou > maxIoU) {
                maxIoU = iou;
                matchedGtBox = groundTruthBox;
              }
            }

            if (maxIoU >= 0.5 && matchedGtBox != null) {
              // Marcar esta groundTruthBox como ya asignada si es necesario
              truePositives++;
              totalIoU += maxIoU;
              // Opcional: Remover o marcar groundTruthBox para evitar múltiples asignaciones
            } else {
              falsePositives++;
            }
          }

          final falseNegatives = groundTruth - truePositives;
          final averageIoULocal =
              truePositives > 0 ? totalIoU / truePositives : 0.0;

          // Calcular métricas adicionales
          final double precision = (truePositives + falsePositives) > 0
              ? truePositives / (truePositives + falsePositives)
              : 0.0;
          final double recall = (truePositives + falseNegatives) > 0
              ? truePositives / (truePositives + falseNegatives)
              : 0.0;
          final double f1Score = (precision + recall) > 0
              ? 2 * (precision * recall) / (precision + recall)
              : 0.0;

          final benchmarkResult = BenchmarkResult(
            imageName: imageName,
            groundTruth: groundTruth,
            detected: detectedBoxes.length,
            iou: averageIoULocal,
            truePositives: truePositives,
            falsePositives: falsePositives,
            falseNegatives: falseNegatives,
            precision: precision,
            recall: recall,
            f1Score: f1Score,
            processingTime: stopwatch.elapsedMilliseconds,
          );

          // Guardar resultados en CSV
          await exportResultsToCSV(benchmarkResult);

          setState(() {
            results.add(benchmarkResult);

            // Actualizar métricas globales
            this.averageIoU =
                (this.averageIoU * processedImages + averageIoULocal) /
                    (processedImages + 1);
            this.totalTruePositives += truePositives;
            this.totalFalsePositives += falsePositives;
            this.totalFalseNegatives += falseNegatives;

            processedImages++;
            progress = processedImages / totalImages;
            print('📈 Progreso: ${(progress * 100).toStringAsFixed(1)}%');
          });
        } catch (e) {
          print('❌ Error procesando $imageName: $e');
        } finally {
          stopwatch.stop();
        }

        i += groundTruth + 1;
      }
    } catch (e) {
      print('❌ Error crítico en el benchmark: $e');
    } finally {
      stopwatch.stop();
      print('🏁 Benchmark finalizado');
      setState(() {
        isRunning = false;
        progress = 0.0;
      });
    }
  }

  Future<List<BoundingBox>> _detectFaces(InputImage inputImage) async {
    print('🔍 Iniciando detección de caras...');
    try {
      final List<Face> faces = await faceDetector.processImage(inputImage);
      print('✅ Detección completada. Caras encontradas: ${faces.length}');
      return faces
          .map((face) => BoundingBox(
                x: face.boundingBox.left,
                y: face.boundingBox.top,
                width: face.boundingBox.width,
                height: face.boundingBox.height,
              ))
          .toList();
    } catch (e) {
      print('❌ Error en detección facial: $e');
      return [];
    }
  }

  double calculateIoU(BoundingBox box1, BoundingBox box2) {
    double x1A = box1.x;
    double y1A = box1.y;
    double x2A = box1.x + box1.width;
    double y2A = box1.y + box1.height;

    double x1B = box2.x;
    double y1B = box2.y;
    double x2B = box2.x + box2.width;
    double y2B = box2.y + box2.height;

    double x1 = math.max(x1A, x1B);
    double y1 = math.max(y1A, y1B);
    double x2 = math.min(x2A, x2B);
    double y2 = math.min(y2A, y2B);

    double intersectionWidth = x2 - x1;
    double intersectionHeight = y2 - y1;

    if (intersectionWidth <= 0 || intersectionHeight <= 0) {
      return 0.0;
    }

    double intersectionArea = intersectionWidth * intersectionHeight;
    double areaA = box1.width * box1.height;
    double areaB = box2.width * box2.height;
    double unionArea = areaA + areaB - intersectionArea;

    return intersectionArea / unionArea;
  }

  Future<void> exportResultsToCSV(BenchmarkResult result) async {
    if (csvFile == null) {
      print('❌ Archivo CSV no inicializado.');
      return;
    }

    // Agregar nueva línea de resultados
    final line = '${result.imageName},'
        '${result.groundTruth},'
        '${result.detected},'
        '${result.iou.toStringAsFixed(4)},'
        '${result.truePositives},'
        '${result.falsePositives},'
        '${result.falseNegatives},'
        '${result.precision.toStringAsFixed(4)},'
        '${result.recall.toStringAsFixed(4)},'
        '${result.f1Score.toStringAsFixed(4)},'
        '${result.processingTime}\n';

    await csvFile!.writeAsString(line, mode: FileMode.append);

    // Agregar debug print
    debugPrint('📁 Resultados agregados al archivo CSV: ${csvFile!.path}');
  }
}

class BenchmarkResult {
  final String imageName;
  final int groundTruth;
  final int detected;
  final double iou;
  final int truePositives;
  final int falsePositives;
  final int falseNegatives;
  final double precision;
  final double recall;
  final double f1Score;
  final int processingTime;

  BenchmarkResult({
    required this.imageName,
    required this.groundTruth,
    required this.detected,
    required this.iou,
    required this.truePositives,
    required this.falsePositives,
    required this.falseNegatives,
    required this.precision,
    required this.recall,
    required this.f1Score,
    required this.processingTime,
  });
}

class BoundingBox {
  final double x;
  final double y;
  final double width;
  final double height;

  BoundingBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });
}
