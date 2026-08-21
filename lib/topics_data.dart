/// Simple data model + static content for the Topics map.
/// Keep this file data-only — no widgets — so Person 3 can later swap
/// `topicWords` for a Firestore-backed source without touching UI files.

class TopicNode {
  final String id;
  final String name;
  final String icon; // emoji shown on the map node
  final double mapX; // 0.0–1.0 horizontal position on the map art
  final double mapY; // 0.0–1.0 vertical position on the map art
  final int wordCount;

  const TopicNode({
    required this.id,
    required this.name,
    required this.icon,
    required this.mapX,
    required this.mapY,
    required this.wordCount,
  });
}

/// Nodes shown on the Topics map, positioned to roughly match the
/// "Topics.png" design (Animals top-left, unlock node top-right,
/// Furniture centre, Food bottom-left).
const List<TopicNode> topicNodes = [
  TopicNode(
      id: 'animals',
      name: 'Animals',
      icon: '🐾',
      mapX: 0.22,
      mapY: 0.18,
      wordCount: 10),
  TopicNode(
      id: 'colors',
      name: 'Colors',
      icon: '🎨',
      mapX: 0.78,
      mapY: 0.30,
      wordCount: 8),
  TopicNode(
      id: 'furniture',
      name: 'Furniture',
      icon: '🏠',
      mapX: 0.58,
      mapY: 0.55,
      wordCount: 12),
  TopicNode(
      id: 'food',
      name: 'Food',
      icon: '🍽️',
      mapX: 0.18,
      mapY: 0.80,
      wordCount: 10),
];

/// word: {"en": "Cat", "th": "แมว", "status": "done" | "locked" | "normal"}
const Map<String, List<Map<String, String>>> topicWords = {
  'animals': [
    {'en': 'Cat', 'th': 'แมว', 'status': 'done'},
    {'en': 'Dog', 'th': 'หมา', 'status': 'done'},
    {'en': 'Bird', 'th': 'นก', 'status': 'done'},
    {'en': 'Fish', 'th': 'ปลา', 'status': 'done'},
    {'en': 'Horse', 'th': 'ม้า', 'status': 'normal'},
    {'en': 'Cow', 'th': 'วัว', 'status': 'normal'},
    {'en': 'Sheep', 'th': 'แกะ', 'status': 'normal'},
    {'en': 'Rabbit', 'th': 'กระต่าย', 'status': 'locked'},
    {'en': 'Duck', 'th': 'เป็ด', 'status': 'locked'},
    {'en': 'Frog', 'th': 'กบ', 'status': 'locked'},
  ],
  'colors': [
    {'en': 'Red', 'th': 'แดง', 'status': 'done'},
    {'en': 'Blue', 'th': 'น้ำเงิน', 'status': 'done'},
    {'en': 'Green', 'th': 'เขียว', 'status': 'normal'},
    {'en': 'Yellow', 'th': 'เหลือง', 'status': 'normal'},
    {'en': 'Purple', 'th': 'ม่วง', 'status': 'locked'},
    {'en': 'Orange', 'th': 'ส้ม', 'status': 'locked'},
    {'en': 'Black', 'th': 'ดำ', 'status': 'locked'},
    {'en': 'White', 'th': 'ขาว', 'status': 'locked'},
  ],
  'furniture': [
    {'en': 'Chair', 'th': 'เก้าอี้', 'status': 'normal'},
    {'en': 'Table', 'th': 'โต๊ะ', 'status': 'normal'},
    {'en': 'Sofa', 'th': 'โซฟา', 'status': 'locked'},
    {'en': 'Bed', 'th': 'เตียง', 'status': 'locked'},
    {'en': 'Lamp', 'th': 'โคมไฟ', 'status': 'locked'},
    {'en': 'Shelf', 'th': 'ชั้นวาง', 'status': 'locked'},
    {'en': 'Mirror', 'th': 'กระจก', 'status': 'locked'},
    {'en': 'Desk', 'th': 'โต๊ะทำงาน', 'status': 'locked'},
    {'en': 'Rug', 'th': 'พรม', 'status': 'locked'},
    {'en': 'Curtain', 'th': 'ผ้าม่าน', 'status': 'locked'},
    {'en': 'Closet', 'th': 'ตู้เสื้อผ้า', 'status': 'locked'},
    {'en': 'Stool', 'th': 'เก้าอี้สตูล', 'status': 'locked'},
  ],
  'food': [
    {'en': 'Rice', 'th': 'ข้าว', 'status': 'locked'},
    {'en': 'Bread', 'th': 'ขนมปัง', 'status': 'locked'},
    {'en': 'Egg', 'th': 'ไข่', 'status': 'locked'},
    {'en': 'Apple', 'th': 'แอปเปิ้ล', 'status': 'locked'},
    {'en': 'Banana', 'th': 'กล้วย', 'status': 'locked'},
    {'en': 'Milk', 'th': 'นม', 'status': 'locked'},
    {'en': 'Water', 'th': 'น้ำ', 'status': 'locked'},
    {'en': 'Noodle', 'th': 'บะหมี่', 'status': 'locked'},
    {'en': 'Soup', 'th': 'ซุป', 'status': 'locked'},
    {'en': 'Cake', 'th': 'เค้ก', 'status': 'locked'},
  ],
};

int doneCount(String topicId) =>
    (topicWords[topicId] ?? []).where((w) => w['status'] == 'done').length;

bool isTopicComplete(String topicId) {
  final words = topicWords[topicId] ?? [];
  return words.isNotEmpty && words.every((w) => w['status'] == 'done');
}

/// The next topic that isn't finished yet — drives the "Continue X" button.
TopicNode? nextIncompleteTopic() {
  for (final t in topicNodes) {
    if (!isTopicComplete(t.id)) return t;
  }
  return null;
}
