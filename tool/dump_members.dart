// 리팩터링 도구: 파일 전체의 메서드·필드 오프셋을 JSON으로 덤프한다.
// 사용: dart run tool/dump_members.dart <파일경로>
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

void main(List<String> args) {
  final path = File(args[0]).absolute.path;
  final result = parseFile(
    path: path,
    featureSet: FeatureSet.latestLanguageVersion(),
  );
  final out = <Map<String, Object?>>[];
  result.unit.accept(_Collector(out));
  stdout.writeln(jsonEncode(out));
}

class _Collector extends RecursiveAstVisitor<void> {
  _Collector(this.out);
  final List<Map<String, Object?>> out;

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    out.add({
      'offset': node.offset,
      'end': node.end,
      'name': node.name.lexeme,
      'kind': 'method',
      'static': node.isStatic,
    });
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    out.add({
      'offset': node.offset,
      'end': node.end,
      'name': node.name?.lexeme ?? '<unnamed>',
      'kind': 'ctor',
      'static': false,
    });
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitFieldDeclaration(FieldDeclaration node) {
    out.add({
      'offset': node.offset,
      'end': node.end,
      'name': node.fields.variables.first.name.lexeme,
      'kind': 'field',
      'static': node.isStatic,
    });
    super.visitFieldDeclaration(node);
  }
}

