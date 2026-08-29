import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 동아리 창립 연도. 가입 연도는 이보다 앞설 수 없다.
const encbaFoundedYear = 1977;

/// 학번·가입년도 피커가 거슬러 올라가는 햇수. 재학 중인 부원을 모두 담고도
/// 목록이 길어지지 않는 선이다.
const _pickerYearSpan = 26;

/// 학번 피커의 선택지. 올해 학번이 항상 맨 위에 오도록 현재 연도에서
/// 계산한다. 예전에는 25까지만 적어 둬서 해가 바뀌면 새 학번을 고를 수
/// 없었다.
List<String> get studentYearPickerOptions {
  final current = DateTime.now().year % 100;
  return List.generate(
    _pickerYearSpan,
    (i) => ((current - i + 100) % 100).toString().padLeft(2, '0'),
  );
}

/// 가입년도 피커의 선택지. 올해부터 거슬러 올라간다.
List<String> get joinedYearPickerOptions {
  final current = DateTime.now().year;
  return List.generate(
    _pickerYearSpan,
    (i) => (current - i).toString(),
  ).where((year) => int.parse(year) >= encbaFoundedYear).toList();
}

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
