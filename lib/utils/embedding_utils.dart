double cosineSimilarity(
    List<double> a,
    List<double> b,
  ) {
    double dot = 0;

    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
    }

    return dot;
  }