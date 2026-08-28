import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'package:encba_locker/core/theme/app_theme.dart';

/// 시·분·초를 각각 드래그해서 고르는 피커. iOS 시계 앱의 타이머와 같은
/// 모양이라 손에 익은 방식 그대로 쓸 수 있다.
///
/// 시간 입력은 텍스트로 받으면 오타가 나고, Material의 시계 다이얼은
/// 분 단위를 정확히 맞추기 번거로웠다. 세 개의 휠이면 어느 자리든 바로
/// 굴려서 맞출 수 있다.
@immutable
class WheelTime {
  const WheelTime(this.hour, this.minute, [this.second = 0]);

  WheelTime.fromDateTime(DateTime value)
    : hour = value.hour,
      minute = value.minute,
      second = value.second;

  final int hour;
  final int minute;
  final int second;

  /// [date]의 날짜에 이 시각을 붙인 DateTime.
  DateTime onDate(DateTime date) =>
      DateTime(date.year, date.month, date.day, hour, minute, second);

  String get label =>
      '${hour.toString().padLeft(2, '0')}:'
      '${minute.toString().padLeft(2, '0')}:'
      '${second.toString().padLeft(2, '0')}';
}

/// 시각 하나를 고르는 시트를 연다. 취소하면 null을 돌려준다.
Future<WheelTime?> showTimeWheelPicker({
  required BuildContext context,
  required String title,
  required WheelTime initial,
  String confirmLabel = '확인',
  String? helperText,
}) => showModalBottomSheet<WheelTime>(
  context: context,
  // 휠 세 개와 버튼 줄을 담으려면 기본 높이(화면 절반)로는 모자란다.
  isScrollControlled: true,
  showDragHandle: true,
  builder: (sheetContext) => _TimeWheelSheet(
    title: title,
    initial: initial,
    confirmLabel: confirmLabel,
    helperText: helperText,
  ),
);

class _TimeWheelSheet extends StatefulWidget {
  const _TimeWheelSheet({
    required this.title,
    required this.initial,
    required this.confirmLabel,
    this.helperText,
  });

  final String title;
  final WheelTime initial;
  final String confirmLabel;
  final String? helperText;

  @override
  State<_TimeWheelSheet> createState() => _TimeWheelSheetState();
}

class _TimeWheelSheetState extends State<_TimeWheelSheet> {
  late int _hour = widget.initial.hour;
  late int _minute = widget.initial.minute;
  late int _second = widget.initial.second;

  late final _hourController = FixedExtentScrollController(initialItem: _hour);
  late final _minuteController = FixedExtentScrollController(
    initialItem: _minute,
  );
  late final _secondController = FixedExtentScrollController(
    initialItem: _second,
  );

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    _secondController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
          if (widget.helperText case final String helper) ...[
            const SizedBox(height: 4),
            Text(
              helper,
              style: const TextStyle(color: EncbaColors.muted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: Stack(
              children: [
                // 가운데 선택 칸. iOS 타이머처럼 고른 값이 띠 안에 들어온다.
                Center(
                  child: Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: EncbaColors.highlight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _WheelColumn(
                        controller: _hourController,
                        count: 24,
                        unit: '시',
                        onChanged: (value) => setState(() => _hour = value),
                      ),
                    ),
                    Expanded(
                      child: _WheelColumn(
                        controller: _minuteController,
                        count: 60,
                        unit: '분',
                        onChanged: (value) => setState(() => _minute = value),
                      ),
                    ),
                    Expanded(
                      child: _WheelColumn(
                        controller: _secondController,
                        count: 60,
                        unit: '초',
                        onChanged: (value) => setState(() => _second = value),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    WheelTime(_hour, _minute, _second),
                  ),
                  child: Text(widget.confirmLabel),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _WheelColumn extends StatelessWidget {
  const _WheelColumn({
    required this.controller,
    required this.count,
    required this.unit,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int count;
  final String unit;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => CupertinoPicker(
    scrollController: controller,
    itemExtent: 40,
    squeeze: 1.1,
    diameterRatio: 1.4,
    selectionOverlay: const SizedBox.shrink(),
    onSelectedItemChanged: onChanged,
    children: [
      for (var value = 0; value < count; value++)
        Center(
          child: Text(
            '$value$unit',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: EncbaColors.ink,
            ),
          ),
        ),
    ],
  );
}
