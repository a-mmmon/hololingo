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
}

const List<TopicDef> kTopics = [
  TopicDef(
    id: 'things_around_me',
    name: 'Things Around Me',
    icon: Icons.home_rounded,
    color: Color(0xFF00C4C4),
    pos: Offset(0.16, 0.88),
    words: [
      TopicWord('Bottle', 'ขวด'),
      TopicWord('Chair', 'เก้าอี้'),
      TopicWord('Laptop', 'แล็ปท็อป'),
      TopicWord('Cell Phone', 'โทรศัพท์มือถือ'),
      TopicWord('Clock', 'นาฬิกา'),
      TopicWord('Remote', 'รีโมต'),
      TopicWord('Vase', 'แจกัน'),
      TopicWord('Scissors', 'กรรไกร'),
      TopicWord('Cup', 'ถ้วย'),
    ],
  ),
  TopicDef(
    id: 'animals',
    name: 'Animals',
    icon: Icons.pets_rounded,
    color: Color(0xFF4CAF50),
    pos: Offset(0.72, 0.62),
    words: [
      TopicWord('Bird', 'นก'),
      TopicWord('Cat', 'แมว'),
      TopicWord('Dog', 'สุนัข'),
      TopicWord('Horse', 'ม้า'),
      TopicWord('Sheep', 'แกะ'),
      TopicWord('Cow', 'วัว'),
      TopicWord('Elephant', 'ช้าง'),
      TopicWord('Bear', 'หมี'),
      TopicWord('Zebra', 'ม้าลาย'),
      TopicWord('Giraffe', 'ยีราฟ'),
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
      TopicWord('Couch', 'โซฟา'),
      TopicWord('Bed', 'เตียง'),
      TopicWord('Dining Table', 'โต๊ะรับประทานอาหาร'),
      TopicWord('Bench', 'ม้านั่ง'),
    ],
  ),
  TopicDef(
    id: 'food',
    name: 'Food',
    icon: Icons.restaurant_rounded,
    color: Color(0xFFFFB300),
    pos: Offset(0.82, 0.10),
    words: [
      TopicWord('Apple', 'แอปเปิล'),
      TopicWord('Banana', 'กล้วย'),
      TopicWord('Orange', 'ส้ม'),
      TopicWord('Pizza', 'พิซซ่า'),
      TopicWord('Cake', 'เค้ก'),
      TopicWord('Sandwich', 'แซนด์วิช'),
      TopicWord('Hot Dog', 'ฮอตดอก'),
      TopicWord('Broccoli', 'บรอกโคลี'),
      TopicWord('Carrot', 'แครอท'),
      TopicWord('Donut', 'โดนัท'),
    ],
  ),
  TopicDef(
    id: 'vehicles',
    name: 'Vehicles',
    icon: Icons.directions_car_rounded,
    color: Color(0xFF42A5F5),
    pos: Offset(0.40, 0.24),
    isPremium: true,
    words: [
      TopicWord('Bicycle', 'จักรยาน'),
      TopicWord('Car', 'รถยนต์'),
      TopicWord('Motorcycle', 'รถจักรยานยนต์'),
      TopicWord('Airplane', 'เครื่องบิน'),
      TopicWord('Bus', 'รถบัส'),
      TopicWord('Train', 'รถไฟ'),
      TopicWord('Truck', 'รถบรรทุก'),
      TopicWord('Boat', 'เรือ'),
    ],
  ),
];
