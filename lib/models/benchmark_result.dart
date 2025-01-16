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