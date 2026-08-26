import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 화면 왼쪽 가장자리에서 충분히 안쪽으로 이동해야만 나가는 뒤로가기 제스처.
/// 앱바 영역은 덮지 않으므로 기본 뒤로가기 버튼도 그대로 동작한다.
class GentleBackSwipe extends StatefulWidget {
  const GentleBackSwipe({super.key, required this.child});

  final Widget child;

  @override
  State<GentleBackSwipe> createState() => _GentleBackSwipeState();
}

class _GentleBackSwipeState extends State<GentleBackSwipe> {
  double _distance = 0;
  double? _startX;
  Stopwatch? _stopwatch;
  bool _popping = false;

  void _start(DragStartDetails details) {
    _distance = 0;
    _startX = details.globalPosition.dx;
    _stopwatch = Stopwatch()..start();
  }

  void _update(DragUpdateDetails details) {
    final startX = _startX;
    if (startX != null) {
      _distance = (details.globalPosition.dx - startX).clamp(
        0,
        double.infinity,
      );
    }
  }

  void _cancel() {
    _distance = 0;
    _startX = null;
    _stopwatch?.stop();
    _stopwatch = null;
    _startX = null;
  }

  void _end(DragEndDetails details) {
    final elapsed = _stopwatch?.elapsed ?? Duration.zero;
    _stopwatch?.stop();
    _stopwatch = null;
    final width = MediaQuery.sizeOf(context).width;
    final enoughDistance = _distance >= width * .30;
    final deliberateFling =
        _distance >= 96 &&
        (details.primaryVelocity ?? 0) >= 1200 &&
        elapsed >= const Duration(milliseconds: 80);
    if (_popping || (!enoughDistance && !deliberateFling)) {
      _distance = 0;
      return;
    }
    _popping = true;
    unawaited(
      Navigator.of(context).maybePop().whenComplete(() {
        if (mounted) setState(() => _popping = false);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      PositionedDirectional(
        start: 0,
        top: MediaQuery.paddingOf(context).top + kToolbarHeight,
        bottom: 0,
        width: 32,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: _start,
          onHorizontalDragUpdate: _update,
          onHorizontalDragEnd: _end,
          onHorizontalDragCancel: _cancel,
        ),
      ),
    ],
  );
}
