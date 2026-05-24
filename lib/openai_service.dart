import 'dart:convert';
import 'package:http/http.dart' as http;
import 'firestore_service.dart';

class OpenAIService {
  // ⚠️ In production, move this to a Cloud Function or env variable
  static const _apiKey = 'YOUR_OPENAI_API_KEY_HERE';
  static const _endpoint = 'https://api.openai.com/v1/chat/completions';

  static Future<String> chat({
    required List<Map<String, String>> history,
    required String userMessage,
  }) async {
    // Get user's real saved words from Firestore
    final words = await FirestoreService.getSavedWords();
    final wordList = words.map((w) => w['word'] as String).join(', ');

    final systemPrompt = '''
You are Holo AI tutor, a friendly English language learning assistant in the HoloLingo app.

The user's saved vocabulary words are: ${wordList.isEmpty ? '(none yet)' : wordList}

Your responsibilities:
- Help the user practice their saved words
- Use words in natural example sentences when asked
- Explain differences between similar words clearly  
- Quiz the user on their vocabulary if asked
- Keep responses SHORT and conversational (2-4 sentences max)
- If referencing a saved word, mention it naturally
- Always be encouraging and positive

Do not use markdown formatting. Write in plain conversational English.
''';

    final messages = [
      {'role': 'system', 'content': systemPrompt},
      ...history.take(10), // last 10 messages for context
      {'role': 'user', 'content': userMessage},
    ];

    try {
      final response = await http.post(
        Uri.parse(_endpoint),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': messages,
          'max_tokens': 300,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        debugPrint('OpenAI error: ${response.body}');
        return 'Sorry, I had trouble connecting. Please try again!';
      }
    } catch (e) {
      debugPrint('OpenAI exception: $e');
      return 'Sorry, something went wrong. Check your connection!';
    }
  }
}

// ignore: avoid_print
void debugPrint(String msg) => print(msg);