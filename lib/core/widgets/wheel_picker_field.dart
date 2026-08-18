import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 학번 피커의 선택지. 최근 가입자 기준으로 00~25만 다룬다.
final List<String> studentYearPickerOptions = List.generate(
  26,
  (i) => (25 - i).toString().padLeft(2, '0'),
);

/// 가입년도 피커의 선택지. 학번과 같은 범위를 연도로 표현한다.
final List<String> joinedYearPickerOptions = List.generate(
  26,
  (i) => (2025 - i).toString(),
);

/// 텍스트 입력 대신 휠을 드래그해 값을 고르는 필드. 학번·가입년도처럼
/// 범위가 정해진 숫자 입력에서 오타를 원천적으로 막는다.
class WheelPickerField extends StatelessWidget {
  const WheelPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(4),
    onTap: () => _openPicker(context),
    child: InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(value, style: const TextStyle(fontSize: 16)),
    ),
  );

  Future<void> _openPicker(BuildContext context) async {
    var pending = value;
    final initialIndex = options.indexOf(value).clamp(0, options.length - 1);
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: 260,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: const Text('확인'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: CupertinoPicker(
                  scrollController: FixedExtentScrollController(
                    initialItem: initialIndex,
                  ),
                  itemExtent: 40,
                  onSelectedItemChanged: (index) => pending = options[index],
                  children: options
                      .map((option) => Center(child: Text(option)))
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    onChanged(pending);
  }
}
