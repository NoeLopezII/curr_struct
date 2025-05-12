import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/explanation.dart';
import 'dart:convert';

class DeepSeekService {
  static final _apiKey = dotenv.get('DEEPSEEK_API_KEY');

  static Future<Explanation> x(String text) async {
    return Explanation(subject: 'Calculus', reasoning: 'Basic trigonometry concept');
  }

  static Future<Explanation> getExplanation(String text, List<String> subjects) async {
    final subjectList = subjects.map((s) => '"$s"').join(', ');
    final response = await http.post(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'deepseek-reasoner',
        'messages': [{
          'role': 'user',
          'content': 'The user is enrolled in the following subjects: [$subjectList]. '
              'Analyze the following content and determine which of these subjects it best(has the highest probability of belonging to) belongs to. '
              'Use LaTeX format for any equation if you decide to use any. '
              'Return ONLY a JSON object with fields "subject" and "reasoning". Text: "$text"'
        }]
      }),
    );

    if (response.statusCode == 200) {
      final raw = jsonDecode(response.body)['choices'][0]['message']['content'];
      final cleaned = raw
          .replaceAll(RegExp(r'```json'), '')
          .replaceAll(RegExp(r'```'), '')
          .trim();

      final escaped = cleaned.replaceAll(r'\', r'\\');

      final data = jsonDecode(escaped);

      return Explanation(
        subject: data['subject'].toString(),
        reasoning: data['reasoning'].toString(),
      );
    }
    throw Exception('DeepSeek Error: ${response.body}');
  }

  static Future<Map<String, dynamic>> checkConsensus(List<String> subjects) async {
    final response = await http.post(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [{
          'role': 'user',
          'content': 'Do these subjects all refer to the exact same specific class? '
              'Respond ONLY with JSON: {"agreed": true/false, "subject": "..."} '
              'Subjects: ${subjects.join(', ')}'
        }]
      }),
    );

    if (response.statusCode == 200) {
      final raw = jsonDecode(response.body)['choices'][0]['message']['content'];
      final cleaned = raw
          .replaceAll(RegExp(r'```json'), '')
          .replaceAll(RegExp(r'```'), '')
          .trim();

      // escape backslashes here too
      final escaped = cleaned.replaceAll(r'\', r'\\');
      return jsonDecode(escaped);
    }

    return {'agreed': false, 'subject': ''};
  }

  /// (unchanged) winner logic…

  static Future<String> determineWinner(List<Explanation> explanations) async {
    if (explanations.isEmpty) return "Undetermined";

    final averages = explanations.map((e) {
      if (e.scores.isEmpty) return 0.0;
      return e.scores.reduce((a, b) => a + b) / e.scores.length;
    }).toList();

    final maxAverage = averages.fold(0.0, (m, a) => a > m ? a : m);
    final winners = explanations.where((e) {
      final avg = e.scores.isEmpty
          ? 0.0
          : e.scores.reduce((a, b) => a + b) / e.scores.length;
      return avg == maxAverage;
    }).toList();

    if (winners.length == 1) return winners.first.subject;
    final subjects = winners.map((e) => e.subject).toSet();
    return (subjects.length == 1) ? subjects.first : "Undetermined";
  }




  static Future<int> scoreExplanation(String text, Explanation explanation) async {
    final prompt = "Here is a piece of textual data: ${text}. The following explanation claims "
        "that it belongs to ${explanation.subject}: ${explanation.reasoning}. Please evaluate the "
        "accuracy of this claim. Consider factors such as whether the textual data indeed belongs "
        "to the claimed subject, the relevance of the explanation, the depth of the explanation, "
        "consistency with established knowledge, likely-hood of mainly being taught in that specific subject/class and logical flow. Provide only the numerical "
        "score from 0 to 100, where 100 means the claim is completely accurate and 0 means it is "
        "completely inaccurate.";

    final response = await http.post(
      Uri.parse('https://api.deepseek.com/v1/chat/completions'),
      headers: {
        'Authorization': 'Bearer $_apiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'model': 'deepseek-reasoner',
        'messages': [{
          'role': 'user',
          'content': prompt
        }]
      }),
    );

    // Handle the API response
    if (response.statusCode == 200) {
      final scoreText = jsonDecode(response.body)['choices'][0]['message']['content'];
      // Extract the first sequence of digits from the response
      final scoreMatch = RegExp(r'\d+').firstMatch(scoreText);
      if (scoreMatch != null) {
        return int.parse(scoreMatch.group(0)!); // Safe to use ! here since we checked for null
      }
      return 0; // Return 0 if no digits are found
    }
    return 0;
  }


  static Future<Description> generateTeaching(String ocrText) async {
    final prompt = """
    Based *strictly* on the content of the following text, provide a concise teaching of the core concept presented.
    Focus only on what is mentioned in the text. Do not introduce outside information, examples, or analogies that are not specific to the text.
    Keep the explanation brief and clear but *enough* for the specific concept to be learnt by the user. The user should be able to solve the problem 
    and be able to teach whatever is in the text to other students after your teaching. Keep in mind the: relevance, accuracy, Organization & Structure, Clarity of Explanation.
    Use LaTeX format for any equation if you decide to use any.


    Text:
    "$ocrText"
    
    Concise Explanation (focused on the text provided):
    """;

    try {
      final response = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'), // Same URL structure
        headers: {
          'Authorization': 'Bearer $_apiKey', // Same header structure
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'deepseek-chat', // Using chat model, similar to checkConsensus
          'messages': [{'role': 'user', 'content': prompt}],
        }),
      );

      if (response.statusCode == 200) {
        // Following similar response parsing
        final content = jsonDecode(response.body)['choices'][0]['message']['content'];
        return Description(
          modelName: 'DeepSeek', // Identify the source model
          teaching: content.trim(), // Trim whitespace
        );
      } else {
        // Similar error handling approach: log and return an error Description
        print('DeepSeek generateTeaching Error ${response.statusCode}: ${response.body}');
        return Description(modelName: 'DeepSeek', teaching: 'Error: Could not generate teaching from DeepSeek.');
      }
    } catch (e) {
      // Catch potential network or other errors during the request
      print('DeepSeek generateTeaching Request Error: $e');
      return Description(modelName: 'DeepSeek', teaching: 'Error: Failed to request teaching from DeepSeek.');
    }
  }

  static Future<int> scoreTeaching(String ocrText, Description teachingToScore) async {
    final prompt = """
    Original Text:
    "$ocrText"
    
    Teaching Explanation to Score:
    "${teachingToScore.teaching}"
    
    Task: Evaluate the "Teaching Explanation" based *strictly* on how well it 
    explains the concepts present in the "Original Text". 
    Consider its relevance (does it stick to the text?), 
    accuracy (material factually precise, sufficiently rigorous, and are key nuances addressed?), 
    Organization & Structure( logically sequenced, and clear transitions?), 
    Clarity of Explanation(How clearly are definitions, theorems, steps and reasoning laid out?).
    Assign a score from 1 (Poor) to 100 (Excellent).
    Respond ONLY with the integer score. Do not provide any explanation or other text.
    
    Score (1-100):
    """;

    try {
      final response = await http.post(
        Uri.parse('https://api.deepseek.com/v1/chat/completions'), // Same URL structure
        headers: {
          'Authorization': 'Bearer $_apiKey', // Same header structure
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'deepseek-reasoner', // Using reasoner model, similar to scoreExplanation
          'messages': [{'role': 'user', 'content': prompt}],
        }),
      );

      if (response.statusCode == 200) {
        // Following similar response parsing and extraction
        final content = jsonDecode(response.body)['choices'][0]['message']['content'];
        final scoreMatch = RegExp(r'\d+').firstMatch(content.trim()); // Trim before regex
        if (scoreMatch != null) {
          int score = int.tryParse(scoreMatch.group(0)!) ?? 1; // Default to 1 on parse error
          // score to the required 1-10 range
          if (score < 1) return 1;
          if (score > 100) return 100;
          return score;
        }
        // Similar fallback if parsing fails
        print("DeepSeek scoreTeaching - Could not parse score from: $content");
        return 1; // Return lowest score in the desired range (1-10)
      } else {
        // Similar error handling: log and return default score
        print('DeepSeek scoreTeaching Error ${response.statusCode}: ${response.body}');
        return 1; // Return lowest score in range on API error
      }
    } catch (e) {
      // Catch potential network or other errors during the request
      print('DeepSeek scoreTeaching Request Error: $e');
      return 1; // Return lowest score in range on network/request error
    }
  }
}