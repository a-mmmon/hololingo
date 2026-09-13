import 'dart:convert';

import 'package:http/http.dart' as http;

class DictionaryService {
  static const String _baseUrl =
      'https://api.dictionaryapi.dev/api/v2/entries/en';

  // Keep these aliases because the object detector may return a slightly
  // different form from the dictionary's canonical word.
  static String normalizeWord(String word) {
    final normalized = word.trim().toLowerCase();

    switch (normalized) {
      case 'scissor':
      case 'scissors':
        return 'scissors';
      case 'cellphone':
      case 'mobile phone':
      case 'mobile':
        return 'cell phone';
      default:
        return normalized;
    }
  }

  static Map<String, String>? getLocalWordInfo(String word) {
    final normalized = normalizeWord(word);
    final fallback = _fallbackVocabulary[normalized];

    if (fallback == null) {
      return null;
    }

    return {
      'word': normalized,
      'phonetic': fallback['phonetic'] ?? '',
      'partOfSpeech': fallback['partOfSpeech'] ?? 'Noun',
      'definition': fallback['definition'] ?? '',
      'example': fallback['example'] ?? '',
      'audio': '',
    };
  }

  static Future<Map<String, String>> getWordInfo(String word) async {
    final normalized = normalizeWord(word);

    if (normalized.isEmpty) {
      return _emptyResult('');
    }

    final localInfo = getLocalWordInfo(normalized);
    if (localInfo != null) {
      return localInfo;
    }

    try {
      final uri = Uri.parse(
        '$_baseUrl/${Uri.encodeComponent(normalized)}',
      );

      final response = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);

        if (decoded is List && decoded.isNotEmpty) {
          final result = _parseEntry(normalized, decoded);
          if (result != null) {
            return result;
          }
        }
      } else {
        // 404 simply means the API could not find that word. Other failures
        // are also handled by the local fallback below.
        // No exception is thrown here because scanning should still work.
        // ignore: avoid_print
        print(
          'Dictionary API returned ${response.statusCode} for "$normalized"',
        );
      }
    } catch (e) {
      // Keep the app usable if the device is offline or the API is unavailable.
      // ignore: avoid_print
      print('Dictionary API error for "$normalized": $e');
    }

    // Small offline fallback for the core objects already used by the app.
    final fallback = _fallbackVocabulary[normalized];
    if (fallback != null) {
      return {
        'word': normalized,
        'phonetic': fallback['phonetic'] ?? '',
        'partOfSpeech': fallback['partOfSpeech'] ?? 'Noun',
        'definition': fallback['definition'] ?? '',
        'example': fallback['example'] ?? '',
        'audio': '',
      };
    }

    return {
      'word': normalized,
      'phonetic': '',
      'partOfSpeech': 'Word',
      'definition': 'No dictionary definition was found for "$normalized".',
      'example': '',
      'audio': '',
    };
  }

  static Map<String, String>? _parseEntry(
    String normalized,
    List<dynamic> entries,
  ) {
    String phonetic = '';
    String audio = '';

    for (final entry in entries) {
      if (entry is! Map) continue;

      if (phonetic.isEmpty) {
        final entryPhonetic = entry['phonetic']?.toString().trim() ?? '';
        if (entryPhonetic.isNotEmpty) {
          phonetic = entryPhonetic;
        }
      }

      final phonetics = entry['phonetics'];
      if (phonetics is List) {
        for (final item in phonetics) {
          if (item is! Map) continue;

          if (phonetic.isEmpty) {
            final text = item['text']?.toString().trim() ?? '';
            if (text.isNotEmpty) {
              phonetic = text;
            }
          }

          if (audio.isEmpty) {
            final value = item['audio']?.toString().trim() ?? '';
            if (value.isNotEmpty) {
              audio = value.startsWith('//') ? 'https:$value' : value;
            }
          }
        }
      }
    }

    // Object labels are normally nouns. Prefer a noun meaning when the API
    // returns several parts of speech, so "scissors" does not accidentally
    // use a verb/adjective meaning.
    Map<String, dynamic>? selectedMeaning;
    Map<String, dynamic>? selectedDefinition;

    for (final entry in entries) {
      if (entry is! Map) continue;
      final meanings = entry['meanings'];
      if (meanings is! List) continue;

      for (final meaning in meanings) {
        if (meaning is! Map) continue;
        final partOfSpeech =
            meaning['partOfSpeech']?.toString().trim().toLowerCase() ?? '';
        final definitions = meaning['definitions'];
        if (definitions is! List || definitions.isEmpty) continue;

        if (selectedMeaning == null) {
          selectedMeaning = Map<String, dynamic>.from(meaning);
          final first = definitions.first;
          if (first is Map) {
            selectedDefinition = Map<String, dynamic>.from(first);
          }
        }

        if (partOfSpeech == 'noun') {
          selectedMeaning = Map<String, dynamic>.from(meaning);
          final first = definitions.first;
          if (first is Map) {
            selectedDefinition = Map<String, dynamic>.from(first);
          }
          break;
        }
      }

      if (selectedMeaning != null &&
          selectedMeaning!['partOfSpeech']?.toString().toLowerCase() ==
              'noun') {
        break;
      }
    }

    if (selectedMeaning == null || selectedDefinition == null) {
      return null;
    }

    final definition =
        selectedDefinition!['definition']?.toString().trim() ?? '';
    if (definition.isEmpty) return null;

    final example =
        selectedDefinition!['example']?.toString().trim() ?? '';
    final partOfSpeech =
        selectedMeaning!['partOfSpeech']?.toString().trim() ?? 'Word';

    return {
      'word': normalized,
      'phonetic': phonetic,
      'partOfSpeech': _titleCase(partOfSpeech),
      'definition': definition,
      'example': example,
      'audio': audio,
    };
  }

  static String _titleCase(String value) {
    if (value.trim().isEmpty) return 'Word';
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static Map<String, String> _emptyResult(String word) {
    return {
      'word': word,
      'phonetic': '',
      'partOfSpeech': 'Word',
      'definition': '',
      'example': '',
      'audio': '',
    };
  }

  static const Map<String, Map<String, String>> _fallbackVocabulary = {
    'laptop': {
      'phonetic': '/ˈlæp.tɒp/',
      'partOfSpeech': 'Noun',
      'definition':
          'A portable computer that can be used for studying, working, browsing the internet, and other tasks.',
      'example': 'I use my laptop to study computer science.',
    },
    'bottle': {
      'phonetic': '/ˈbɒt.əl/',
      'partOfSpeech': 'Noun',
      'definition':
          'A container, usually made of glass or plastic, used for storing liquids.',
      'example': 'She filled the bottle with water.',
    },
    'cup': {
      'phonetic': '/kʌp/',
      'partOfSpeech': 'Noun',
      'definition': 'A small container used for drinking liquids.',
      'example': 'I drink coffee from a cup.',
    },
    'chair': {
      'phonetic': '/tʃeər/',
      'partOfSpeech': 'Noun',
      'definition': 'A piece of furniture designed for one person to sit on.',
      'example': 'Please sit on the chair.',
    },
    'book': {
      'phonetic': '/bʊk/',
      'partOfSpeech': 'Noun',
      'definition':
          'A set of written or printed pages fastened together inside a cover.',
      'example': 'I am reading a book.',
    },
    'bed': {
      'phonetic': '/bed/',
      'partOfSpeech': 'Noun',
      'definition': 'A piece of furniture used for sleeping or resting.',
      'example': 'The cat is sleeping on the bed.',
    },
    'scissors': {
      'phonetic': '/ˈsɪz.əz/',
      'partOfSpeech': 'Noun',
      'definition':
          'A tool used for cutting thin material, consisting of two blades joined at a pivot.',
      'example': 'I used scissors to cut the paper.',
    },
    'plant': {
      'phonetic': '/plɑːnt/',
      'partOfSpeech': 'Noun',
      'definition':
          'A living organism that usually grows in soil and makes its own food using sunlight.',
      'example': 'The plant needs sunlight and water.',
    },
    'flower': {
      'phonetic': '/ˈflaʊ.ər/',
      'partOfSpeech': 'Noun',
      'definition':
          'The part of a plant that usually produces seeds and is often brightly colored.',
      'example': 'The flower is growing in the garden.',
    },
    'table': {
      'phonetic': '/ˈteɪ.bəl/',
      'partOfSpeech': 'Noun',
      'definition':
          'A piece of furniture with a flat top and one or more legs, used for working or placing things on.',
      'example': 'The book is on the table.',
    },
    'desk': {
      'phonetic': '/desk/',
      'partOfSpeech': 'Noun',
      'definition':
          'A piece of furniture with a flat surface used for studying, writing, or working.',
      'example': 'My laptop is on the desk.',
    },
    'pen': {
      'phonetic': '/pen/',
      'partOfSpeech': 'Noun',
      'definition':
          'A writing instrument that uses ink to make marks on paper.',
      'example': 'I wrote my name with a pen.',
    },
    'remote': {
      'phonetic': '/rɪˈməʊt/',
      'partOfSpeech': 'Noun',
      'definition': 'A device used to control a television or other electronic equipment from a distance.',
      'example': 'I used the remote to change the channel.',
    },
    'clock': {
      'phonetic': '/klɒk/',
      'partOfSpeech': 'Noun',
      'definition': 'A device that shows the time.',
      'example': 'The clock is on the wall.',
    },
    'vase': {
      'phonetic': '/vɑːz/',
      'partOfSpeech': 'Noun',
      'definition': 'A container, often decorative, used for holding flowers.',
      'example': 'She put the flowers in a vase.',
    },
    'cell phone': {
      'phonetic': '/ˈsel fəʊn/',
      'partOfSpeech': 'Noun',
      'definition': 'A portable phone that can make calls and send messages over a cellular network.',
      'example': 'I called my friend on my cell phone.',
    },
    'sensor': {
      'phonetic': '/ˈsen.sər/',
      'partOfSpeech': 'Noun',
      'definition': 'A device that detects or measures a physical change or condition.',
      'example': 'The sensor detects movement.',
    },
    'sensors': {
      'phonetic': '/ˈsen.sərz/',
      'partOfSpeech': 'Noun',
      'definition': 'Devices that detect or measure physical changes or conditions.',
      'example': 'The sensors detect movement.',
    },
    'lamp': {
      'phonetic': '/læmp/',
      'partOfSpeech': 'Noun',
      'definition': 'A device that produces light, usually for illuminating a room or area.',
      'example': 'I turned on the lamp to read my book.',
    },
    'phone': {
      'phonetic': '/fəʊn/',
      'partOfSpeech': 'Noun',
      'definition':
          'A device used for calling, messaging, and accessing digital information.',
      'example': 'I left my phone on the table.',
    },
    'keyboard': {
      'phonetic': '/ˈkiː.bɔːd/',
      'partOfSpeech': 'Noun',
      'definition':
          'A set of keys used to enter letters, numbers, and commands into a computer.',
      'example': 'She typed the message on the keyboard.',
    },
    'mouse': {
      'phonetic': '/maʊs/',
      'partOfSpeech': 'Noun',
      'definition':
          'A small device used to control the pointer on a computer screen.',
      'example': 'Move the mouse to the right.',
    },
  };
}
