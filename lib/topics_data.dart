import 'package:flutter/material.dart';

class TopicWord {
  final String word;
  final String translation;

  const TopicWord(this.word, this.translation);
}

class TopicDef {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  final Offset pos;
  final List<TopicWord> words;
  final bool isPremium;

  const TopicDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.pos,
    required this.words,
    this.isPremium = false,
  });

  /// Topics now live in Firestore (the `topics` collection) so new topics
  /// and words can be added without an app update. `icon` is stored as a
  /// name string and looked up in [kTopicIcons] below, since IconData can't
  /// be reconstructed from arbitrary data once icon tree-shaking is on —
  /// a genuinely new icon (not already in that map) still needs a one-line
  /// code addition there, everything else about a topic does not.
  factory TopicDef.fromFirestore(
    String id,
    Map<String, dynamic> data,
  ) {
    final rawWords = data['words'];

    final words = rawWords is List
        ? rawWords
            .whereType<Map>()
            .map(
              (w) => TopicWord(
                (w['word'] ?? '').toString(),
                (w['translation'] ?? '').toString(),
              ),
            )
            .toList()
        : <TopicWord>[];

    return TopicDef(
      id: id,
      name: (data['name'] ?? '').toString(),
      icon: kTopicIcons[data['icon']?.toString()] ??
          Icons.help_outline_rounded,
      color: _colorFromHex(
        data['color']?.toString(),
      ),
      pos: Offset(
        ((data['pos_x'] as num?) ?? 0.5).toDouble(),
        ((data['pos_y'] as num?) ?? 0.5).toDouble(),
      ),
      words: words,
      isPremium: data['is_premium'] == true,
    );
  }

  static Color _colorFromHex(
    String? hex,
  ) {
    const fallback = Color(0xFF00C4C4);

    if (hex == null || hex.isEmpty) return fallback;

    final cleaned = hex.replaceFirst('#', '');

    final value = int.tryParse(
      cleaned,
      radix: 16,
    );

    if (value == null) return fallback;

    return Color(
      cleaned.length <= 6 ? (0xFF000000 | value) : value,
    );
  }
}

/// Fixed name -> IconData lookup for topics loaded from Firestore. Adding a
/// topic that reuses one of these icons needs zero code changes; adding one
/// with a genuinely new icon needs one new line here.
const Map<String, IconData> kTopicIcons = {
  'home_rounded': Icons.home_rounded,
  'pets_rounded': Icons.pets_rounded,
  'chair_rounded': Icons.chair_rounded,
  'restaurant_rounded': Icons.restaurant_rounded,
  'directions_car_rounded': Icons.directions_car_rounded,
};

/// One-time migration data only — used by FirestoreService.seedTopicsOnce()
/// to populate the `topics` collection the first time the app runs against
/// an empty database. Not read by the app's normal topic-loading path
/// (that reads from Firestore via TopicDef.fromFirestore). Safe to ignore
/// once your Firestore `topics` collection already has data; new topics
/// and words from then on are added directly in the Firebase Console, not
/// by editing this list.
const List<Map<String, dynamic>> kTopicsSeedData = [
  {
    'id': 'things_around_me',
    'order': 0,
    'name': 'Things Around Me',
    'icon': 'home_rounded',
    'color': '#00C4C4',
    'pos_x': 0.16,
    'pos_y': 0.88,
    'words': [
      {'word': 'Bottle', 'translation': 'ขวด'},
      {'word': 'Chair', 'translation': 'เก้าอี้'},
      {'word': 'Laptop', 'translation': 'แล็ปท็อป'},
      {'word': 'Cell Phone', 'translation': 'โทรศัพท์มือถือ'},
      {'word': 'Clock', 'translation': 'นาฬิกา'},
      {'word': 'Remote', 'translation': 'รีโมต'},
      {'word': 'Vase', 'translation': 'แจกัน'},
      {'word': 'Scissors', 'translation': 'กรรไกร'},
      {'word': 'Cup', 'translation': 'ถ้วย'},
    ],
  },
  {
    'id': 'animals',
    'order': 1,
    'name': 'Animals',
    'icon': 'pets_rounded',
    'color': '#4CAF50',
    'pos_x': 0.72,
    'pos_y': 0.62,
    'words': [
      {'word': 'Bird', 'translation': 'นก'},
      {'word': 'Cat', 'translation': 'แมว'},
      {'word': 'Dog', 'translation': 'สุนัข'},
      {'word': 'Horse', 'translation': 'ม้า'},
      {'word': 'Sheep', 'translation': 'แกะ'},
      {'word': 'Cow', 'translation': 'วัว'},
      {'word': 'Elephant', 'translation': 'ช้าง'},
      {'word': 'Bear', 'translation': 'หมี'},
      {'word': 'Zebra', 'translation': 'ม้าลาย'},
      {'word': 'Giraffe', 'translation': 'ยีราฟ'},
    ],
  },
  {
    'id': 'furniture',
    'order': 2,
    'name': 'Furniture',
    'icon': 'chair_rounded',
    'color': '#7C5CBF',
    'pos_x': 0.24,
    'pos_y': 0.40,
    'words': [
      {'word': 'Chair', 'translation': 'เก้าอี้'},
      {'word': 'Couch', 'translation': 'โซฟา'},
      {'word': 'Bed', 'translation': 'เตียง'},
      {'word': 'Dining Table', 'translation': 'โต๊ะรับประทานอาหาร'},
      {'word': 'Bench', 'translation': 'ม้านั่ง'},
    ],
  },
  {
    'id': 'food',
    'order': 3,
    'name': 'Food',
    'icon': 'restaurant_rounded',
    'color': '#FFB300',
    'pos_x': 0.82,
    'pos_y': 0.10,
    'words': [
      {'word': 'Apple', 'translation': 'แอปเปิล'},
      {'word': 'Banana', 'translation': 'กล้วย'},
      {'word': 'Orange', 'translation': 'ส้ม'},
      {'word': 'Pizza', 'translation': 'พิซซ่า'},
      {'word': 'Cake', 'translation': 'เค้ก'},
      {'word': 'Sandwich', 'translation': 'แซนด์วิช'},
      {'word': 'Hot Dog', 'translation': 'ฮอตดอก'},
      {'word': 'Broccoli', 'translation': 'บรอกโคลี'},
      {'word': 'Carrot', 'translation': 'แครอท'},
      {'word': 'Donut', 'translation': 'โดนัท'},
    ],
  },
  {
    'id': 'vehicles',
    'order': 4,
    'name': 'Vehicles',
    'icon': 'directions_car_rounded',
    'color': '#42A5F5',
    'pos_x': 0.40,
    'pos_y': 0.24,
    'is_premium': true,
    'words': [
      {'word': 'Bicycle', 'translation': 'จักรยาน'},
      {'word': 'Car', 'translation': 'รถยนต์'},
      {'word': 'Motorcycle', 'translation': 'รถจักรยานยนต์'},
      {'word': 'Airplane', 'translation': 'เครื่องบิน'},
      {'word': 'Bus', 'translation': 'รถบัส'},
      {'word': 'Train', 'translation': 'รถไฟ'},
      {'word': 'Truck', 'translation': 'รถบรรทุก'},
      {'word': 'Boat', 'translation': 'เรือ'},
    ],
  },
];
