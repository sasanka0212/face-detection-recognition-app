class FaceRecord {
  final int? id;
  final String name;
  final List<double> embedding;

  FaceRecord({
    this.id,
    required this.name,
    required this.embedding,
  });
}