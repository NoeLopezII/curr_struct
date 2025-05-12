import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/explanation.dart';
import 'dart:convert';

class ClaudeService {
  static final _apiKey = dotenv.get('ANTHROPIC_API_KEY');

  static Future<Explanation> x(String text) async {
    return Explanation(subject: 'Physics', reasoning: 'Basic trigonometry concept');
  }

  static Future<Explanation> getExplanation(String text, List<String> subjects) async {
    final subjectList = subjects.map((s) => '"$s"').join(', ');
    final response = await http.post(
      Uri.parse('https://api.anthropic.com/v1/messages'),
      headers: {
        'x-api-key': _apiKey,
        'Content-Type': 'application/json',
        'anthropic-version': '2023-06-01'
      },
      body: jsonEncode({
        'model': 'claude-3-7-sonnet-20250219',
        'max_tokens': 2000,
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
      final raw = jsonDecode(response.body)['content'][0]['text'];
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

  static Future<int> scoreExplanation(String text, Explanation explanation) async {
    try {
      final prompt = "Here is a piece of textual data: ${text}. The following explanation claims "
          "that it belongs to ${explanation.subject}: ${explanation.reasoning}. Please evaluate the "
          "accuracy of this claim. Consider factors such as whether the textual data indeed belongs "
          "to the claimed subject, the relevance of the explanation, the depth of the explanation, "
          "consistency with established knowledge, likely-hood of mainly being taught in that specific subject/class and logical flow. Provide only the numerical "
          "score from 0 to 100, where 100 means the claim is completely accurate and 0 means it is "
          "completely inaccurate.";

      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey,
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01'
        },
        body: jsonEncode({
          'model': 'claude-3-7-sonnet-20250219',
          'max_tokens': 2000,
          'messages': [{
            'role': 'user',
            'content': prompt
          }]
        }),
      );

      if (response.statusCode == 200) {
        final responseBody = jsonDecode(response.body);
        final scoreText = responseBody['content'][0]['text'];
        final scoreMatch = RegExp(r'\d+').firstMatch(scoreText);
        if (scoreMatch != null) {
          final score = int.parse(scoreMatch.group(0)!);
          return score.clamp(0, 100);
        }
        return 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }



  static Future<Description> generateTeaching(String ocrText) async {
    final prompt = """
    Based *strictly* on the content of the following text, provide a concise teaching of the core concept presented.
    Focus only on what is mentioned in the text. Do not introduce outside information, examples, or analogies that are not specific to the text.
    Keep the explanation brief but *enough* for the specific concept to be learnt by the user. The user should be able to solve the problem 
    and be able to teach whatever is in the text to other students after your teaching. Keep in mind the: relevance, accuracy, Organization & Structure, Clarity of Explanation.
    Use LaTeX format for any equation if you decide to use any.


    Text:
    "$ocrText"
    
    Concise Explanation (focused on the text provided):
    """;

    try {
      final response = await http.post(
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey,
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-7-sonnet-20250219',
          'max_tokens': 2000,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final content = jsonDecode(response.body)['content'][0]['text'];
        return Description(
          modelName: 'Claude', // Updated to match style
          teaching: content.trim(),
        );
      } else {
        print('Claude generateTeaching Error ${response.statusCode}: ${response.body}');
        return Description(
          modelName: 'Claude',
          teaching: 'Error: Could not generate teaching from Claude.',
        );
      }
    } catch (e) {
      print('Claude generateTeaching Request Error: $e');
      return Description(
        modelName: 'Claude',
        teaching: 'Error: Failed to request teaching from Claude.',
      );
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
        Uri.parse('https://api.anthropic.com/v1/messages'),
        headers: {
          'x-api-key': _apiKey,
          'Content-Type': 'application/json',
          'anthropic-version': '2023-06-01',
        },
        body: jsonEncode({
          'model': 'claude-3-7-sonnet-20250219',
          'max_tokens': 2000,
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
        }),
      );

      if (response.statusCode == 200) {
        final content = jsonDecode(response.body)['content'][0]['text'];
        final scoreMatch = RegExp(r'\d+').firstMatch(content.trim());
        if (scoreMatch != null) {
          int score = int.tryParse(scoreMatch.group(0)!) ?? 1;
          if (score < 1) return 1;
          if (score > 100) return 100;
          return score;
        }
        print('Claude scoreTeaching - Could not parse score from: $content');
        return 1;
      } else {
        print('Claude scoreTeaching Error ${response.statusCode}: ${response.body}');
        return 1;
      }
    } catch (e) {
      print('Claude scoreTeaching Request Error: $e');
      return 1;
    }
  }
}
