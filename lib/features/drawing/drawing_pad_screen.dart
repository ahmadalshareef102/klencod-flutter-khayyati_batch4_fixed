import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/image_store.dart';
import '../../core/ui.dart';

class _Stroke {
  _Stroke(this.color, this.width);
  final Color color;
  final double width;
  final List<Offset> points = [];
}

class _SketchPainter extends CustomPainter {
  _SketchPainter(this.strokes, this.repaint) : super(repaint: repaint);
  final List<_Stroke> strokes;
  final ValueNotifier<int> repaint;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (s.points.length == 1) {
        canvas.drawCircle(s.points.first, s.width / 2, paint..style = PaintingStyle.fill);
      } else {
        final path = Path()..moveTo(s.points.first.dx, s.points.first.dy);
        for (final p in s.points.skip(1)) {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SketchPainter old) => true;
}

/// لوحة رسم باليد لموديل الطلب. تُرجع المسار النسبي للصورة المحفوظة.
class DrawingPadScreen extends StatefulWidget {
  const DrawingPadScreen({super.key});

  @override
  State<DrawingPadScreen> createState() => _DrawingPadScreenState();
}

class _DrawingPadScreenState extends State<DrawingPadScreen> {
  final List<_Stroke> _strokes = [];
  final _tick = ValueNotifier<int>(0);
  final _canvasKey = GlobalKey();
  Color _color = const Color(0xFF1A2B4C);
  double _width = 3;
  bool _saving = false;

  static const _palette = [
    Color(0xFF1A2B4C),
    Colors.black,
    Colors.red,
    Colors.green,
    Colors.orange,
  ];

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_strokes.isEmpty) {
      showMsg(context, 'ارسم شيئاً أولاً');
      return;
    }
    setState(() => _saving = true);
    try {
      final box = _canvasKey.currentContext!.findRenderObject()! as RenderBox;
      final size = box.size;
      const scale = 2.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(scale);
      _SketchPainter(_strokes, _tick).paint(canvas, size);
      final img = await recorder
          .endRecording()
          .toImage((size.width * scale).round(), (size.height * scale).round());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      final rel = await ImageStore.saveBytes(data!.buffer.asUint8List(),
          folder: 'sketches');
      if (mounted) context.pop(rel);
    } catch (_) {
      if (mounted) {
        showMsg(context, 'تعذّر حفظ الرسم');
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('رسم الموديل'),
        actions: [
          IconButton(
            tooltip: 'تراجع',
            icon: const Icon(Icons.undo),
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() {
                      _strokes.removeLast();
                      _tick.value++;
                    }),
          ),
          IconButton(
            tooltip: 'مسح الكل',
            icon: const Icon(Icons.layers_clear_outlined),
            onPressed: _strokes.isEmpty
                ? null
                : () => setState(() {
                      _strokes.clear();
                      _tick.value++;
                    }),
          ),
          IconButton(
            tooltip: 'حفظ',
            icon: const Icon(Icons.check),
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).colorScheme.outline),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: GestureDetector(
                onPanStart: (d) {
                  _strokes.add(_Stroke(_color, _width)..points.add(d.localPosition));
                  _tick.value++;
                },
                onPanUpdate: (d) {
                  _strokes.last.points.add(d.localPosition);
                  _tick.value++;
                },
                onPanEnd: (_) => setState(() {}),
                child: RepaintBoundary(
                  key: _canvasKey,
                  child: CustomPaint(
                    painter: _SketchPainter(_strokes, _tick),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                            width: 3,
                            color: _color == c
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent),
                      ),
                    ),
                  ),
                Expanded(
                  child: Slider(
                    min: 1,
                    max: 12,
                    value: _width,
                    onChanged: (v) => setState(() => _width = v),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
