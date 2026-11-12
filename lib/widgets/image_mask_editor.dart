import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class MaskStroke {
  MaskStroke({required this.width, required this.points});
  final double width;
  final List<Offset> points;
}

void paintMaskStrokes(
    Canvas canvas, Size size, List<MaskStroke> strokes, Paint paint) {
  for (final stroke in strokes) {
    paint.strokeWidth = stroke.width * size.width;
    final points = stroke.points
        .map((e) => Offset(e.dx * size.width, e.dy * size.height))
        .toList();
    if (points.length == 1) {
      canvas.drawCircle(points.first, paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill);
      paint.style = PaintingStyle.stroke;
    } else {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }
}

Future<Uint8List> renderImageMask(
    int width, int height, List<MaskStroke> strokes) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final size = Size(width.toDouble(), height.toDouble());
  canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
  paintMaskStrokes(
      canvas,
      size,
      strokes,
      Paint()
        ..blendMode = BlendMode.clear
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

class ImageMaskEditor extends StatefulWidget {
  const ImageMaskEditor({super.key, required this.image});
  final Uint8List image;

  @override
  State<ImageMaskEditor> createState() => _ImageMaskEditorState();
}

class _ImageMaskEditorState extends State<ImageMaskEditor> {
  ui.Image? _image;
  String? _error;
  final _strokes = <MaskStroke>[];
  double _brush = .06;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.image);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      setState(() => _image = frame.image);
    } catch (_) {
      if (mounted) setState(() => _error = '无法读取参考图片。');
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final bytes =
          await renderImageMask(_image!.width, _image!.height, _strokes);
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '遮罩生成失败，请重试。';
        });
      }
    }
  }

  Offset _normalized(Offset value, Size size) => Offset(
      (value.dx / size.width).clamp(0, 1),
      (value.dy / size.height).clamp(0, 1));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('编辑区域'), actions: [
          IconButton(
              tooltip: '撤销',
              onPressed: _saving || _strokes.isEmpty
                  ? null
                  : () => setState(_strokes.removeLast),
              icon: const Icon(Icons.undo)),
          IconButton(
              tooltip: '清除涂抹',
              onPressed: _saving || _strokes.isEmpty
                  ? null
                  : () => setState(_strokes.clear),
              icon: const Icon(Icons.delete_sweep_outlined)),
        ]),
        body: Column(children: [
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
              child: _image == null
                  ? Center(
                      child: _error == null
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.broken_image_outlined))
                  : Padding(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                          child: AspectRatio(
                        aspectRatio: _image!.width / _image!.height,
                        child: LayoutBuilder(builder: (context, constraints) {
                          final size =
                              Size(constraints.maxWidth, constraints.maxHeight);
                          return GestureDetector(
                            onPanStart: _saving
                                ? null
                                : (details) => setState(() => _strokes.add(
                                        MaskStroke(width: _brush, points: [
                                      _normalized(details.localPosition, size)
                                    ]))),
                            onPanUpdate: _saving
                                ? null
                                : (details) => setState(() =>
                                    _strokes.last.points.add(_normalized(
                                        details.localPosition, size))),
                            onTapUp: _saving
                                ? null
                                : (details) => setState(() => _strokes.add(
                                        MaskStroke(width: _brush, points: [
                                      _normalized(details.localPosition, size)
                                    ]))),
                            child: CustomPaint(
                                painter: _MaskPainter(_image!, _strokes),
                                size: size),
                          );
                        }),
                      )))),
          SafeArea(
              top: false,
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      const Icon(Icons.brush_outlined),
                      Expanded(
                          child: Slider(
                              value: _brush,
                              min: .01,
                              max: .2,
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() => _brush = v)))
                    ]),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed:
                                _image == null || _strokes.isEmpty || _saving
                                    ? null
                                    : _save,
                            icon: const Icon(Icons.check),
                            label: Text(_saving ? '保存中' : '确认区域'))),
                  ]))),
        ]),
      );
}

class _MaskPainter extends CustomPainter {
  _MaskPainter(this.image, this.strokes);
  final ui.Image image;
  final List<MaskStroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint());
    canvas.saveLayer(Offset.zero & size, Paint());
    paintMaskStrokes(
        canvas,
        size,
        strokes,
        Paint()
          ..color = const Color(0x8894d8ca)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MaskPainter oldDelegate) => true;
}
