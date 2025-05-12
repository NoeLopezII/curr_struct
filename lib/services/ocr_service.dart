import 'dart:convert';
import 'dart:io';
import 'package:flutter/physics.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class OCRService {
  static Future<String> extractText(String imagePath) async {
    final appId = dotenv.get('MATHPIX_APP_ID');
    final apiKey = dotenv.get('MATHPIX_API_KEY');
    final imageFile = File(imagePath);
    final bytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(bytes);

    final response = await http.post(
      Uri.parse('https://api.mathpix.com/v3/text'),
      headers: {
        'app_id': appId,
        'app_key': apiKey,
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'src': 'data:image/jpeg;base64,$base64Image',
        'formats': ['text'],
        'format_options': {'text': {'math_notation': 'latex'}}
      }),
    );

    if (response.statusCode == 200) {
      final jsonResponse = jsonDecode(response.body);
      return jsonResponse['text'] ?? '';
    }
    throw Exception('OCR Failed: ${response.body}');
  }
}