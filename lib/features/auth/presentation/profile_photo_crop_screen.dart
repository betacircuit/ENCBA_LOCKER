import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 프로필 원형 표시 범위를 확인하면서 사진을 확대·이동하는 화면.
/// 사진 바깥은 중립 회색으로 렌더링해 원본 가장자리가 원 안에 걸려도 결과가
/// 투명하거나 검게 저장되지 않게 한다.
class ProfilePhotoCropScreen extends StatefulWidget {
  const ProfilePhotoCropScreen({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  State<ProfilePhotoCropScreen> createState() => _ProfilePhotoCropScreenState();
}

class _ProfilePhotoCropScreenState extends State<ProfilePhotoCropScreen> {
  final _boundaryKey = GlobalKey();
  final _transform = TransformationController();
  bool _saving = false;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    await WidgetsBinding.instance.endOfFrame;
    final boundary =
        _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null || !mounted) {
      setState(() => _saving = false);
      return;
    }
    final logicalWidth = boundary.size.width;
    final image = await boundary.toImage(pixelRatio: 512 / logicalWidth);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (!mounted) return;
    if (data == null) {
      setState(() => _saving = false);
      return;
    }
    Navigator.pop(
      context,
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('프로필 사진 맞추기')),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          children: [
            const Text('사진을 움직이거나 확대해 점선 원 안에 얼굴을 맞춰 주세요.'),
            const SizedBox(height: 18),
            Expanded(
              child: Center(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest.shortestSide.clamp(
                      220.0,
                      520.0,
                    );
                    return SizedBox.square(
                      dimension: size,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          RepaintBoundary(
                            key: _boundaryKey,
                            child: ClipRect(
                              child: ColoredBox(
                                color: const Color(0xFFE5E7EB),
                                child: InteractiveViewer(
                                  transformationController: _transform,
                                  boundaryMargin: EdgeInsets.all(size),
                                  minScale: .6,
                                  maxScale: 5,
                                  child: SizedBox.square(
                                    dimension: size,
                                    child: Image.memory(
                                      widget.bytes,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const IgnorePointer(
                            child: CustomPaint(painter: _CropGuidePainter()),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _finish,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('이 영역으로 사용'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CropGuidePainter extends CustomPainter {
  const _CropGuidePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, Paint()..color = Colors.black38);

    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    const dashRadians = .075;
    const gapRadians = .045;
    for (var angle = 0.0; angle < 6.28319; angle += dashRadians + gapRadians) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        dashRadians,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_CropGuidePainter oldDelegate) => false;
}
