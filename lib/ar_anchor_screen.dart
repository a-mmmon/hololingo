import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:arcore_flutter_plugin/arcore_flutter_plugin.dart';
import 'package:vector_math/vector_math_64.dart' as vector;
import 'app_theme.dart';
import 'vocab_detail_screen.dart';

/// Opens after a word has already been identified (via the existing
/// TFLite detection flow in CameraTab). Lets the user tap a real-world
/// surface to drop a floating, AR-anchored label for that word.
/// Tapping the placed label opens the Vocabulary Detail page.
class ArAnchorScreen extends StatefulWidget {
  final String word;
  final String phonetic;
  final String definition;
  final String example;

  const ArAnchorScreen({
    super.key,
    required this.word,
    required this.phonetic,
    required this.definition,
    required this.example,
  });

  @override
  State<ArAnchorScreen> createState() => _ArAnchorScreenState();
}

class _ArAnchorScreenState extends State<ArAnchorScreen> {
  ArCoreController? _controller;
  bool _placed = false;
  String? _placedNodeName;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onArCoreViewCreated(ArCoreController controller) {
    _controller = controller;
    controller.onPlaneTap = _onPlaneTap;
    controller.onNodeTap = _onNodeTap;
  }

  Future<void> _onPlaneTap(List<ArCoreHitTestResult> hits) async {
    if (_placed || hits.isEmpty) return;
    final hit = hits.first;

    final textureBytes = await _renderWordTexture(widget.word);
    final nodeName = 'word_${DateTime.now().millisecondsSinceEpoch}';

    final material = ArCoreMaterial(
      color: Colors.white,
      textureBytes: textureBytes,
      metallic: 0.0,
    );
    final shape = ArCoreCube(
      materials: [material],
      size: vector.Vector3(0.3, 0.12, 0.01),
    );
    final node = ArCoreNode(
      name: nodeName,
      shape: shape,
      position: hit.pose.translation,
      rotation: hit.pose.rotation,
    );

    await _controller?.addArCoreNodeWithAnchor(node);

    if (mounted) {
      setState(() {
        _placed = true;
        _placedNodeName = nodeName;
      });
    }
  }

  void _onNodeTap(String nodeName) {
    if (nodeName != _placedNodeName) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VocabDetailScreen(
          word: widget.word,
          phonetic: widget.phonetic,
          definition: widget.definition,
          example: widget.example,
        ),
      ),
    );
  }

  /// Renders the word as a rounded label onto a transparent PNG, used as
  /// the texture on the flat AR node so it reads like a floating tag.
  Future<Uint8List> _renderWordTexture(String text) async {
    const width = 512.0, height = 200.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final bgPaint = Paint()..color = const Color(0xFF0F0F13).withValues(alpha: 0.85);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, width, height), const Radius.circular(36)),
      bgPaint,
    );
    final borderPaint = Paint()
      ..color = AppColors.cyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          const Rect.fromLTWH(3, 3, width - 6, height - 6), const Radius.circular(34)),
      borderPaint,
    );

    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 72,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width - 40);
    textPainter.paint(
      canvas,
      Offset((width - textPainter.width) / 2, (height - textPainter.height) / 2),
    );

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          ArCoreView(
            onArCoreViewCreated: _onArCoreViewCreated,
            enableTapRecognizer: true,
          ),
          Positioned(
            top: 56,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    _placed
                        ? 'Tap the floating "${widget.word}" label to view details'
                        : 'Move around, then tap a surface to place "${widget.word}"',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 56,
            left: 16,
            child: SafeArea(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}