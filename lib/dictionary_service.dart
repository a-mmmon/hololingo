import 'dart:convert';
import 'package:http/http.dart' as http;

class DictionaryService {
  static Future<Map<String, String>> getWordInfo(String word) async {
    try {
      final response = await http.get(
        Uri.parse('https://api.dictionaryapi.dev/api/v2/entries/en/$word'),
      );

      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        final entry = data[0];

        // Phonetic
        String phonetic = '';
        if (entry['phonetic'] != null) {
          phonetic = entry['phonetic'];
        } else if (entry['phonetics'] != null &&
            entry['phonetics'].isNotEmpty) {
          phonetic = entry['phonetics'][0]['text'] ?? '';
        }

        // Part of speech + definition + example
        String partOfSpeech = 'Noun';
        String definition = '';
        String example = '';

        if (entry['meanings'] != null && entry['meanings'].isNotEmpty) {
          final meaning = entry['meanings'][0];
          partOfSpeech = _capitalize(meaning['partOfSpeech'] ?? 'noun');

          if (meaning['definitions'] != null &&
              meaning['definitions'].isNotEmpty) {
            final def = meaning['definitions'][0];
            definition = def['definition'] ?? '';
            example = def['example'] ?? '';
          }
        }

        return {
          'word': word,
          'phonetic': phonetic,
          'partOfSpeech': partOfSpeech,
          'definition': definition,
          'example': example,
        };
      } else {
        return {
          'word': word,
          'phonetic': '',
          'partOfSpeech': 'Noun',
          'definition': 'Definition not found.',
          'example': '',
        };
      }
    } catch (e) {
      return {
        'word': word,
        'phonetic': '',
        'partOfSpeech': 'Noun',
        'definition': 'Could not load definition.',
        'example': '',
      };
    }
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}