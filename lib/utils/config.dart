import 'package:flutter_dotenv/flutter_dotenv.dart';

class Config {
  static String get mathpixAppId => dotenv.get('MATHPIX_APP_ID');
  static String get mathpixApiKey => dotenv.get('MATHPIX_API_KEY');
  static String get openaiApiKey => dotenv.get('OPENAI_API_KEY');
  static String get anthropicApiKey => dotenv.get('ANTHROPIC_API_KEY');
  static String get deepseekApiKey => dotenv.get('DEEPSEEK_API_KEY');
}