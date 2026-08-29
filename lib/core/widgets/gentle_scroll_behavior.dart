import 'package:flutter/material.dart';

/// 짧은 드래그가 과도한 플링으로 이어지지 않도록 앱 전체 스크롤 속도를 제한한다.
class GentleScrollBehavior extends MaterialScrollBehavior {
  const GentleScrollBehavior();

  // AlwaysScrollableScrollPhysics를 씌우지 않는다.
  //
  // 그건 당겨서 새로고침이 오버스크롤을 받아야 해서 넣었던 것인데, 내용이
  // 화면보다 짧은 목록까지 끌리고 튕기게 만들어 손짓 한 번에 화면이
  // 흔들리는 것처럼 보였다. 새로고침을 걷어낸 지금은 필요 없다.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      GentleScrollPhysics(parent: super.getScrollPhysics(context));
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
