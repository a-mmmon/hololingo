import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'saved_screen.dart';
import 'quiz_screen.dart';
import 'dictionary_service.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'database_service.dart';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CameraScreen(),
    );
  }
}

class CameraScreen extends StatefulWidget {
  @override
  _CameraScreenState createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late CameraController _controller;
  bool _isInitialized = false;
  String _detectedWord = 'bottle';
  String _definition = '';
  String _phonetic = '';
  String _example = '';
  bool _showOverlay = false;
  bool _isLoadingWord = false;
  int _currentIndex = 0;
  final FlutterTts _tts = FlutterTts();

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    _controller = CameraController(
      cameras[0],
      ResolutionPreset.high,
    );
    await _controller.initialize();
    setState(() {
      _isInitialized = true;
    });
  }

  Future<void> _lookupWord(String word) async {
    setState(() {
      _isLoadingWord = true;
      _showOverlay = true;
      _detectedWord = word;
    });
    final result = await DictionaryService.getWordInfo(word);
    setState(() {
      _phonetic = result['phonetic'] ?? '';
      _definition = result['definition'] ?? '';
      _example = result['example'] ?? '';
      _isLoadingWord = false;
    });
  }

  Future<void> _speak(String word) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.speak(word);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _isInitialized
          ? Stack(
              children: [
                SizedBox.expand(
                  child: CameraPreview(_controller),
                ),

                // Top bar
                Positioned(
                  top: 50,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Point camera at an object',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ),

                // Search button
                Positioned(
                  top: 100,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: () => _lookupWord('bottle'),
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.search, color: Colors.white),
                  ),
                ),

                // Word overlay card
                if (_showOverlay)
                  Positioned(
                    bottom: 100,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black26, blurRadius: 10),
                        ],
                      ),
                      child: _isLoadingWord
                          ? Center(child: CircularProgressIndicator())
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _detectedWord,
                                      style: TextStyle(
                                        fontSize: 28,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue[800],
                                      ),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.close),
                                      onPressed: () {
                                        setState(() => _showOverlay = false);
                                      },
                                    ),
                                  ],
                                ),
                                Text(
                                  _phonetic,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  _definition,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                  ),
                                ),
                                if (_example.isNotEmpty)
                                  Padding(
                                    padding: EdgeInsets.only(top: 8),
                                    child: Text(
                                      '"$_example"',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                        fontStyle: FontStyle.italic,
                                      ),
                                    ),
                                  ),
                                SizedBox(height: 12),
                                ElevatedButton(
                                  onPressed: () => _lookupWord('bottle'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                  child: Text('Test API: bottle'),
                                ),
                                SizedBox(height: 8),
                                Row(
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () => _speak(_detectedWord),
                                      icon: Icon(Icons.volume_up, size: 18),
                                      label: Text('Pronounce'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        await DatabaseService.saveWord({
                                          'word': _detectedWord,
                                          'phonetic': _phonetic,
                                          'definition': _definition,
                                          'example': _example,
                                        });
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                                '"$_detectedWord" saved!'),
                                            backgroundColor: Colors.green,
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                      icon: Icon(Icons.bookmark, size: 18),
                                      label: Text('Save'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                    ),
                  ),

                // Bottom navigation
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    color: Colors.black87,
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _currentIndex = 0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt,
                                  color: _currentIndex == 0
                                      ? Colors.blue
                                      : Colors.white54,
                                  size: 28),
                              Text('Scan',
                                  style: TextStyle(
                                      color: _currentIndex == 0
                                          ? Colors.blue
                                          : Colors.white54,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => SavedScreen()),
                            );
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bookmark,
                                  color: _currentIndex == 1
                                      ? Colors.blue
                                      : Colors.white54,
                                  size: 28),
                              Text('Saved',
                                  style: TextStyle(
                                      color: _currentIndex == 1
                                          ? Colors.blue
                                          : Colors.white54,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => QuizScreen()),
                            );
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.quiz,
                                  color: _currentIndex == 2
                                      ? Colors.blue
                                      : Colors.white54,
                                  size: 28),
                              Text('Quiz',
                                  style: TextStyle(
                                      color: _currentIndex == 2
                                          ? Colors.blue
                                          : Colors.white54,
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
    );
  }
}