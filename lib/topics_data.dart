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
  final Offset pos; // fractional position on the map
  final List<TopicWord> words;

  const TopicDef({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    required this.pos,
    required this.words,
  });
}

// Ordered start → finish, matching the walking path on the map.
const List<TopicDef> kTopics = [
  TopicDef(
    id: 'colors',
    name: 'Colors',
    icon: Icons.palette_rounded,
    color: Color(0xFF00C4C4),
    pos: Offset(0.16, 0.88),
    words: [
      TopicWord('Red', 'สีแดง'),
      TopicWord('Blue', 'สีฟ้า'),
      TopicWord('Green', 'สีเขียว'),
      TopicWord('Yellow', 'สีเหลือง'),
      TopicWord('Purple', 'สีม่วง'),
      TopicWord('Orange', 'สีส้ม'),
    ],
  ),
  TopicDef(
    id: 'animals',
    name: 'Animals',
    icon: Icons.pets_rounded,
    color: Color(0xFF4CAF50),
    pos: Offset(0.72, 0.62),
    words: [
      TopicWord('Cat', 'แมว'),
      TopicWord('Dog', 'หมา'),
      TopicWord('Bird', 'นก'),
      TopicWord('Fish', 'ปลา'),
      TopicWord('Elephant', 'ช้าง'),
      TopicWord('Rabbit', 'กระต่าย'),
    ],
  ),
  TopicDef(
    id: 'furniture',
    name: 'Furniture',
    icon: Icons.chair_rounded,
    color: Color(0xFF7C5CBF),
    pos: Offset(0.24, 0.40),
    words: [
      TopicWord('Chair', 'เก้าอี้'),
      TopicWord('Table', 'โต๊ะ'),
      TopicWord('Bed', 'เตียง'),
      TopicWord('Sofa', 'โซฟา'),
      TopicWord('Lamp', 'โคมไฟ'),
      TopicWord('Shelf', 'ชั้นวาง'),
    ],
  ),
  TopicDef(
    id: 'food',
    name: 'Food',
    icon: Icons.restaurant_rounded,
    color: Color(0xFFFFB300),
    pos: Offset(0.80, 0.14),
    words: [
      TopicWord('Rice', 'ข้าว'),
      TopicWord('Bread', 'ขนมปัง'),
      TopicWord('Egg', 'ไข่'),
      TopicWord('Fruit', 'ผลไม้'),
      TopicWord('Water', 'น้ำ'),
      TopicWord('Noodle', 'ก๋วยเตี๋ยว'),
    ],
  ),
];