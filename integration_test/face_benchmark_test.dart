// integration_test/face_benchmark_test.dart

import 'dart:io';

import 'package:face_detection_mlkit/results/benchmark_result.dart';
import 'package:face_detection_mlkit/services/face_benchmark_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FaceBenchmarkService', () {
    late FaceBenchmarkService benchmarkService;

    setUp(() {
      benchmarkService = FaceBenchmarkService();
    });

    tearDown(() async {
      await benchmarkService.dispose();
    });

    test('Run benchmark and generate CSV', () async {
      // Ruta al archivo de anotaciones
      const String annotationFilePath = 'assets/wider_face_val_bbx_gt.txt';

      // Ejecutar el benchmark
      final List<BenchmarkResult> results =
          await benchmarkService.runBenchmark(annotationFilePath);

      // Verificar que se hayan procesado imágenes
      expect(results.isNotEmpty, true);
      print('✅ Se procesaron ${results.length} imágenes.');

      // Verificar que el archivo CSV se haya creado
      final String storagePath = await benchmarkService.getStoragePath();
      final Directory directory = Directory(storagePath);
      final List<FileSystemEntity> files = directory.listSync();

      final Iterable<File> csvFiles = files.whereType<File>().where((file) =>
          file.path.endsWith('.csv') &&
          file.path.contains('benchmark_results'));

      expect(csvFiles.isNotEmpty, true);
      print('✅ Archivo CSV generado: ${csvFiles.first.path}');

      // Leer el archivo CSV y verificar contenido
      final File csvFile = csvFiles.first;
      final String csvContent = await csvFile.readAsString();

      expect(csvContent.contains('image_path'), true); // Verificar headers
      expect(
          csvContent.split('\n').length, results.length + 1); // +1 por headers
      print('✅ Verificación del contenido del CSV completada.');
    });
  });
}
