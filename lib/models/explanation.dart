
class Explanation {
  final String subject;
  final String reasoning;
  List<int> scores;

  Explanation({
    required this.subject,
    required this.reasoning,
    this.scores = const [],
  });

  @override
  String toString() {
    return 'Subject: $subject | Reasoning: $reasoning | Scores: $scores';
  }
}

class Description { // Your class for the teaching feature
  final String modelName; // Added to easily identify the source LLM
  final String teaching;
  List<int> scores;

  Description({
    required this.modelName, // Add modelName here
    required this.teaching,
    this.scores = const [],
  });

  @override
  String toString() {
    // Include modelName in the string representation for clarity in logs
    return 'Model: $modelName | Teaching: $teaching | Scores: $scores';
  }

  // Helper to calculate average score, handling division by zero
  double get averageScore {
    if (scores.isEmpty) return 0.0;
    return scores.reduce((a, b) => a + b) / scores.length;
  }
}