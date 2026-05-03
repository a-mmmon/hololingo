import 'package:flutter/material.dart';

class QuizScreen extends StatefulWidget {
  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  int _currentQuestion = 0;
  int _score = 0;
  bool _answered = false;
  int? _selectedIndex;

  final List<Map<String, dynamic>> _questions = [
    {
      'question': 'What is this object called?',
      'image': '🍶',
      'correct': 'bottle',
      'options': ['bottle', 'cup', 'bowl', 'jar'],
    },
    {
      'question': 'Which word means a seat for one person?',
      'image': '🪑',
      'correct': 'chair',
      'options': ['table', 'chair', 'desk', 'stool'],
    },
    {
      'question': 'What is a written or printed work called?',
      'image': '📖',
      'correct': 'book',
      'options': ['paper', 'note', 'book', 'letter'],
    },
  ];

  void _answer(int index) {
    if (_answered) return;
    setState(() {
      _answered = true;
      _selectedIndex = index;
      if (_questions[_currentQuestion]['options'][index] ==
          _questions[_currentQuestion]['correct']) {
        _score++;
      }
    });
  }

  void _next() {
    if (_currentQuestion < _questions.length - 1) {
      setState(() {
        _currentQuestion++;
        _answered = false;
        _selectedIndex = null;
      });
    } else {
      // Show score
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text('Quiz Complete! 🎉'),
          content: Text(
            'Your score: $_score / ${_questions.length}',
            style: TextStyle(fontSize: 20),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                setState(() {
                  _currentQuestion = 0;
                  _score = 0;
                  _answered = false;
                  _selectedIndex = null;
                });
              },
              child: Text('Try Again'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: Text('Back to Home'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = _questions[_currentQuestion];

    return Scaffold(
      appBar: AppBar(
        title: Text('Quiz'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            // Progress indicator
            LinearProgressIndicator(
              value: (_currentQuestion + 1) / _questions.length,
              backgroundColor: Colors.grey[300],
              color: Colors.blue,
            ),
            SizedBox(height: 8),
            Text(
              'Question ${_currentQuestion + 1} of ${_questions.length}',
              style: TextStyle(color: Colors.grey),
            ),

            SizedBox(height: 30),

            // Emoji image
            Text(
              question['image'],
              style: TextStyle(fontSize: 80),
            ),

            SizedBox(height: 20),

            // Question text
            Text(
              question['question'],
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: 30),

            // Answer options
            ...List.generate(question['options'].length, (index) {
              Color buttonColor = Colors.white;
              Color textColor = Colors.black87;

              if (_answered) {
                if (question['options'][index] == question['correct']) {
                  buttonColor = Colors.green[100]!;
                  textColor = Colors.green[800]!;
                } else if (index == _selectedIndex) {
                  buttonColor = Colors.red[100]!;
                  textColor = Colors.red[800]!;
                }
              }

              return GestureDetector(
                onTap: () => _answer(index),
                child: Container(
                  width: double.infinity,
                  margin: EdgeInsets.only(bottom: 12),
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: buttonColor,
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    question['options'][index],
                    style: TextStyle(
                      fontSize: 18,
                      color: textColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            }),

          

            // Next button
            if (_answered)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _currentQuestion < _questions.length - 1
                        ? 'Next Question'
                        : 'See Results',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}