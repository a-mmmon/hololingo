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

        // Get phonetic
        String phonetic = '';
        if (entry['phonetic'] != null) {
          phonetic = entry['phonetic'];
        } else if (entry['phonetics'] != null &&
            entry['phonetics'].isNotEmpty) {
          phonetic = entry['phonetics'][0]['text'] ?? '';
        }

        // Get definition
        String definition = '';
        if (entry['meanings'] != null && entry['meanings'].isNotEmpty) {
          final meanings = entry['meanings'][0];
          if (meanings['definitions'] != null &&
              meanings['definitions'].isNotEmpty) {
            definition = meanings['definitions'][0]['definition'] ?? '';
          }
        }

        // Get example sentence
        String example = '';
        if (entry['meanings'] != null && entry['meanings'].isNotEmpty) {
          final meanings = entry['meanings'][0];
          if (meanings['definitions'] != null &&
              meanings['definitions'].isNotEmpty) {
            example = meanings['definitions'][0]['example'] ?? '';
          }
        }

        return {
          'word': word,
          'phonetic': phonetic,
          'definition': definition,
          'example': example,
        };
      } else {
        return {
          'word': word,
          'phonetic': '',
          'definition': 'Definition not found.',
          'example': '',
        };
      }
    } catch (e) {
      return {
        'word': word,
        'phonetic': '',
        'definition': 'Could not load definition.',
        'example': '',
      };
    }
  }
}