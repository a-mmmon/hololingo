import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class DictionaryService {
  static final Map<String, Map<String, String>?> _assetCache = {};
  static final Map<String, Map<String, String>?> _onlineCache = {};

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
      // The following are detector class labels (compound/hyphenated names
      // from the training dataset) that don't exist as headwords in the
      // dictionary assets, but the object they refer to does under a
      // simpler name. Verified against the actual dictionary JSON files —
      // don't add more of these without checking a candidate word exists.
      case 'computer-monitor':
        return 'monitor';
      case 'lamp post':
        return 'lamppost';
      case 'stop-sign':
      case 'traffic-sign':
        return 'sign';
      case 'door-handle':
        return 'handle';
      case 'rubiks_cube':
        return 'cube';
      case 'potted plant':
        return 'plant';
      case 'paper cup':
        return 'cup';
      case 'waterbottle':
        // The dictionary's own "waterbottle" entry is just a stub
        // ("Alternative form of water bottle") with no phonetic data at
        // all, and the concatenated spelling also makes TTS mispronounce
        // it. "water bottle" isn't in the dictionary assets as its own
        // headword either, so this relies on the curated fallback entry
        // below rather than a real dictionary lookup.
        return 'water bottle';
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
      // Local entries keep object scanning usable without network access.
      debugPrint('Dictionary local hit: "$normalized"');
      return localInfo;
    }

    final assetInfo = await _getAssetWordInfo(normalized);
    if (assetInfo != null) {
      // The bundled offline dataset never includes phonetic data at all
      // (verified directly against the JSON — it only has word/etymologies),
      // so supplement from a real online dictionary when there's a
      // connection. Best-effort: keeps the offline definition either way
      // if the network call fails or the word isn't found online.
      if ((assetInfo['phonetic'] ?? '').isEmpty) {
        final online = await _getOnlineWordInfo(normalized);
        final onlinePhonetic = online?['phonetic'] ?? '';
        if (onlinePhonetic.isNotEmpty) {
          assetInfo['phonetic'] = onlinePhonetic;
        }
      }
      return assetInfo;
    }

    final online = await _getOnlineWordInfo(normalized);
    if (online != null) {
      debugPrint('Dictionary online hit: "$normalized"');
      return online;
    }

    return {
      'word': normalized,
      'phonetic': '',
      'partOfSpeech': 'Word',
      'definition':
          'The word "$normalized" was detected, but its full definition is not available offline yet.',
      'example': '',
      'audio': '',
    };
  }

  /// Falls back to a real online dictionary (dictionaryapi.dev) for words
  /// the bundled offline dataset can't fully answer — mainly phonetics,
  /// which the offline dataset never has, but also as a last-resort full
  /// lookup for words missing from the offline dataset entirely. Cached
  /// in memory so a word is only ever fetched once per app session.
  /// Network failures/timeouts are deliberately NOT cached, since a
  /// temporary connectivity issue shouldn't permanently block retrying.
  static Future<Map<String, String>?> _getOnlineWordInfo(
    String normalized,
  ) async {
    if (_onlineCache.containsKey(normalized)) {
      return _onlineCache[normalized];
    }

    try {
      final uri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/en/'
        '${Uri.encodeComponent(normalized)}',
      );

      final response = await http.get(uri).timeout(
            const Duration(seconds: 6),
          );

      if (response.statusCode != 200) {
        // A real "not found" (404) — cache it so we don't keep asking.
        _onlineCache[normalized] = null;
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        _onlineCache[normalized] = null;
        return null;
      }

      final result = _parseEntry(normalized, decoded);
      _onlineCache[normalized] = result;
      return result;
    } catch (e) {
      debugPrint('Dictionary online lookup failed for "$normalized": $e');
      return null;
    }
  }

  static Future<Map<String, String>?> _getAssetWordInfo(
    String normalized,
  ) async {
    final cached = _assetCache[normalized];
    if (_assetCache.containsKey(normalized)) return cached;

    final prefix = normalized.replaceAll(RegExp(r'[^a-z]'), '');
    if (prefix.isEmpty) {
      _assetCache[normalized] = null;
      return null;
    }

    final filePrefix = prefix.length == 1 ? prefix : prefix.substring(0, 2);
    final assetPath = 'assets/dictionary/${filePrefix[0]}/$filePrefix.json';

    try {
      final decoded = jsonDecode(await rootBundle.loadString(assetPath));
      final raw = decoded is Map ? decoded[normalized] : null;
      if (raw is! Map) {
        _assetCache[normalized] = null;
        return null;
      }

      String? definition;
      String partOfSpeech = 'Noun';
      final etymologies = raw['etymologies'];
      if (etymologies is List) {
        for (final etymology in etymologies) {
          final parts = etymology is Map ? etymology['partsOfSpeech'] : null;
          if (parts is! List) continue;
          for (final part in parts) {
            if (part is! Map) continue;
            final senses = part['senses'];
            if (senses is! List) continue;
            final candidate = senses.firstWhere(
              (sense) =>
                  sense is Map &&
                  (sense['sense']?.toString().trim().isNotEmpty ?? false),
              orElse: () => null,
            );
            if (candidate is Map) {
              final candidateText = candidate['sense']?.toString().trim();
              if (candidateText != null && candidateText.isNotEmpty) {
                final candidatePart = part['partsOfSpeech']?.toString() ?? '';
                if (definition == null ||
                    candidatePart.toLowerCase() == 'noun') {
                  definition = _stripHtml(candidateText);
                  partOfSpeech = candidatePart.isEmpty ? 'Noun' : candidatePart;
                }
                if (candidatePart.toLowerCase() == 'noun') break;
              }
            }
          }
          if (definition != null && partOfSpeech.toLowerCase() == 'noun') break;
        }
      }

      if (definition == null || definition.isEmpty) {
        _assetCache[normalized] = null;
        return null;
      }

      final result = {
        'word': normalized,
        'phonetic': '',
        'partOfSpeech': _titleCase(partOfSpeech),
        'definition': definition,
        'example': '',
        'audio': '',
      };
      _assetCache[normalized] = result;
      debugPrint('Dictionary asset hit: "$normalized"');
      return result;
    } catch (e) {
      debugPrint('Dictionary asset lookup failed for "$normalized": $e');
      _assetCache[normalized] = null;
      return null;
    }
  }

  static String _stripHtml(String value) {
    return value
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .trim();
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

    final example = selectedDefinition!['example']?.toString().trim() ?? '';
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
      'definition':
          'A device used to control a television or other electronic equipment from a distance.',
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
      'definition':
          'A portable phone that can make calls and send messages over a cellular network.',
      'example': 'I called my friend on my cell phone.',
    },
    'sensor': {
      'phonetic': '/ˈsen.sər/',
      'partOfSpeech': 'Noun',
      'definition':
          'A device that detects or measures a physical change or condition.',
      'example': 'The sensor detects movement.',
    },
    'sensors': {
      'phonetic': '/ˈsen.sərz/',
      'partOfSpeech': 'Noun',
      'definition':
          'Devices that detect or measure physical changes or conditions.',
      'example': 'The sensors detect movement.',
    },
    'lamp': {
      'phonetic': '/læmp/',
      'partOfSpeech': 'Noun',
      'definition':
          'A device that produces light, usually for illuminating a room or area.',
      'example': 'I turned on the lamp to read my book.',
    },
    'water bottle': {
      'phonetic': '/ˈwɔː.tər ˌbɒt.əl/',
      'partOfSpeech': 'Noun',
      'definition':
          'A container, usually made of plastic or metal, used for carrying drinking water.',
      'example': 'She filled her water bottle before the hike.',
    },
    'monitor': {
      'phonetic': '/ˈmɒn.ɪ.tər/',
      'partOfSpeech': 'Noun',
      'definition':
          'A screen used to display output from a computer, similar to a television.',
      'example': 'The information flashed up on the monitor.',
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
    'umbrella': {
      'phonetic': '/ʌmˈbrel.ə/',
      'partOfSpeech': 'Noun',
      'definition':
          'A folding cover held above the head to protect a person from rain or sunlight.',
      'example': 'I carried an umbrella because it was raining.',
    },
    'bird': {
      'phonetic': '/bɜːd/',
      'partOfSpeech': 'Noun',
      'definition':
          'An animal with feathers, wings, and a beak that usually lays eggs.',
      'example': 'A small bird landed on the window.',
    },
    'cat': {
      'phonetic': '/kæt/',
      'partOfSpeech': 'Noun',
      'definition':
          'A small domesticated animal with fur, four legs, and a long tail.',
      'example': 'The cat is sleeping on the sofa.',
    },
    'dog': {
      'phonetic': '/dɒɡ/',
      'partOfSpeech': 'Noun',
      'definition':
          'A domesticated animal often kept as a companion or trained to work.',
      'example': 'The dog is playing in the garden.',
    },
    'horse': {
      'phonetic': '/hɔːs/',
      'partOfSpeech': 'Noun',
      'definition':
          'A large animal with four legs that people ride or use for work.',
      'example': 'The horse ran across the field.',
    },
    'sheep': {
      'phonetic': '/ʃiːp/',
      'partOfSpeech': 'Noun',
      'definition':
          'A farm animal with woolly fur that is often kept in groups.',
      'example': 'The sheep are eating grass.',
    },
    'cow': {
      'phonetic': '/kaʊ/',
      'partOfSpeech': 'Noun',
      'definition':
          'A large farm animal kept for milk, meat, and other products.',
      'example': 'The cow is standing near the fence.',
    },
    'elephant': {
      'phonetic': '/ˈel.ɪ.fənt/',
      'partOfSpeech': 'Noun',
      'definition': 'A very large animal with a trunk, tusks, and big ears.',
      'example': 'The elephant used its trunk to drink water.',
    },
    'bear': {
      'phonetic': '/beər/',
      'partOfSpeech': 'Noun',
      'definition':
          'A large, strong wild animal with thick fur and a short tail.',
      'example': 'We saw a bear in the wildlife park.',
    },
    'zebra': {
      'phonetic': '/ˈziː.brə/',
      'partOfSpeech': 'Noun',
      'definition':
          'An African horse-like animal with black-and-white stripes.',
      'example': 'The zebra stood beside the giraffe.',
    },
    'giraffe': {
      'phonetic': '/dʒɪˈrɑːf/',
      'partOfSpeech': 'Noun',
      'definition':
          'A tall African animal with a very long neck and patterned skin.',
      'example': 'The giraffe reached the leaves easily.',
    },
    'couch': {
      'phonetic': '/kaʊtʃ/',
      'partOfSpeech': 'Noun',
      'definition': 'A long, comfortable seat for two or more people.',
      'example': 'We sat on the couch to watch a movie.',
    },
    'dining table': {
      'phonetic': '/ˈdaɪ.nɪŋ ˌteɪ.bəl/',
      'partOfSpeech': 'Noun',
      'definition': 'A table used for eating meals.',
      'example': 'The plates are on the dining table.',
    },
    'bench': {
      'phonetic': '/bentʃ/',
      'partOfSpeech': 'Noun',
      'definition':
          'A long seat for two or more people, often made of wood or metal.',
      'example': 'We sat on a bench in the park.',
    },
    'key': {
      'phonetic': '/kiː/',
      'partOfSpeech': 'Noun',
      'definition':
          'A small piece of shaped metal used to open or lock a door, start a vehicle, or operate a device.',
      'example': 'I used my key to unlock the door.',
    },
    'swan': {
      'phonetic': '/swɒn/',
      'partOfSpeech': 'Noun',
      'definition':
          'A large water bird with a long graceful neck and usually white feathers.',
      'example': 'A swan was swimming across the lake.',
    },
    'apple': {
      'phonetic': '/ˈæp.əl/',
      'partOfSpeech': 'Noun',
      'definition':
          'A round fruit with firm flesh and skin that can be red, green, or yellow.',
      'example': 'I packed an apple for lunch.',
    },
    'banana': {
      'phonetic': '/bəˈnɑː.nə/',
      'partOfSpeech': 'Noun',
      'definition':
          'A long, curved fruit with yellow skin and soft sweet flesh.',
      'example': 'She ate a banana after breakfast.',
    },
    'orange': {
      'phonetic': '/ˈɒr.ɪndʒ/',
      'partOfSpeech': 'Noun',
      'definition':
          'A round citrus fruit with orange skin and juicy sections inside.',
      'example': 'He peeled an orange.',
    },
    'pizza': {
      'phonetic': '/ˈpiːt.sə/',
      'partOfSpeech': 'Noun',
      'definition':
          'A flat baked dough covered with tomato sauce, cheese, and other toppings.',
      'example': 'We ordered a pizza for dinner.',
    },
    'cake': {
      'phonetic': '/keɪk/',
      'partOfSpeech': 'Noun',
      'definition':
          'A sweet baked food made from flour, sugar, eggs, and other ingredients.',
      'example': 'We shared a chocolate cake.',
    },
    'sandwich': {
      'phonetic': '/ˈsæn.wɪdʒ/',
      'partOfSpeech': 'Noun',
      'definition':
          'Food made by putting a filling between two pieces of bread.',
      'example': 'I made a cheese sandwich.',
    },
    'hot dog': {
      'phonetic': '/ˈhɒt dɒɡ/',
      'partOfSpeech': 'Noun',
      'definition': 'A cooked sausage served in a long split roll.',
      'example': 'He added mustard to his hot dog.',
    },
    'broccoli': {
      'phonetic': '/ˈbrɒk.əl.i/',
      'partOfSpeech': 'Noun',
      'definition':
          'A green vegetable with a thick stem and small flowering heads.',
      'example': 'The broccoli is ready to eat.',
    },
    'carrot': {
      'phonetic': '/ˈkær.ət/',
      'partOfSpeech': 'Noun',
      'definition':
          'A long orange root vegetable that is often eaten raw or cooked.',
      'example': 'The rabbit is eating a carrot.',
    },
    'donut': {
      'phonetic': '/ˈdəʊ.nʌt/',
      'partOfSpeech': 'Noun',
      'definition': 'A small sweet fried cake, often shaped like a ring.',
      'example': 'She chose a donut with chocolate icing.',
    },
    'bicycle': {
      'phonetic': '/ˈbaɪ.sɪ.kəl/',
      'partOfSpeech': 'Noun',
      'definition': 'A vehicle with two wheels moved by pedals.',
      'example': 'I ride my bicycle to school.',
    },
    'car': {
      'phonetic': '/kɑːr/',
      'partOfSpeech': 'Noun',
      'definition':
          'A road vehicle with an engine and four wheels for carrying people.',
      'example': 'Their car is parked outside.',
    },
    'motorcycle': {
      'phonetic': '/ˈməʊ.təˌsaɪ.kəl/',
      'partOfSpeech': 'Noun',
      'definition': 'A two-wheeled vehicle powered by an engine.',
      'example': 'He travels to work by motorcycle.',
    },
    'airplane': {
      'phonetic': '/ˈeə.pleɪn/',
      'partOfSpeech': 'Noun',
      'definition': 'A powered flying vehicle with fixed wings.',
      'example': 'The airplane took off on time.',
    },
    'bus': {
      'phonetic': '/bʌs/',
      'partOfSpeech': 'Noun',
      'definition': 'A large road vehicle that carries many passengers.',
      'example': 'I take the bus to work.',
    },
    'train': {
      'phonetic': '/treɪn/',
      'partOfSpeech': 'Noun',
      'definition': 'A series of connected vehicles that travel on a railway.',
      'example': 'The train arrived at the station.',
    },
    'truck': {
      'phonetic': '/trʌk/',
      'partOfSpeech': 'Noun',
      'definition': 'A large road vehicle used for carrying goods.',
      'example': 'The truck delivered the boxes.',
    },
    'boat': {
      'phonetic': '/bəʊt/',
      'partOfSpeech': 'Noun',
      'definition': 'A small vessel used for travelling on water.',
      'example': 'They crossed the lake by boat.',
    },
    'boot': {
      'phonetic': '/buːt/',
      'partOfSpeech': 'Noun',
      'definition': 'A strong shoe that covers the foot and part of the leg.',
      'example': 'She wore a pair of black boots.',
    },
    'glove': {
      'phonetic': '/ɡlʌv/',
      'partOfSpeech': 'Noun',
      'definition':
          'A covering for the hand with separate sections for the fingers.',
      'example': 'I put on a glove to protect my hand.',
    },
    'flowerpot': {
      'phonetic': '/ˈflaʊ.ə.pɒt/',
      'partOfSpeech': 'Noun',
      'definition': 'A container used for growing a plant or flower.',
      'example': 'The flowerpot is beside the window.',
    },
    'jacket': {
      'phonetic': '/ˈdʒæk.ɪt/',
      'partOfSpeech': 'Noun',
      'definition': 'A short coat that covers the upper body and arms.',
      'example': 'Take a jacket because it is cold outside.',
    },
    'spoon': {
      'phonetic': '/spuːn/',
      'partOfSpeech': 'Noun',
      'definition':
          'A utensil with a shallow bowl used for eating or serving food.',
      'example': 'Use a spoon to stir the soup.',
    },
  };
}
