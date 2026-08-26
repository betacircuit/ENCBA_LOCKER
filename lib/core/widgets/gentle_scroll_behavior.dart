import 'package:flutter/material.dart';

/// 짧은 드래그가 과도한 플링으로 이어지지 않도록 앱 전체 스크롤 속도를 제한한다.
class GentleScrollBehavior extends MaterialScrollBehavior {
  const GentleScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => GentleScrollPhysics(
    parent: AlwaysScrollableScrollPhysics(
      parent: super.getScrollPhysics(context),
    ),
  );
}

class GentleScrollPhysics extends ScrollPhysics {
  const GentleScrollPhysics({super.parent});

  @override
  GentleScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      GentleScrollPhysics(parent: buildParent(ancestor));

  @override
  double get maxFlingVelocity => 2400;

  @override
  double carriedMomentum(double existingVelocity) =>
      super.carriedMomentum(existingVelocity).clamp(-1200.0, 1200.0);
}
