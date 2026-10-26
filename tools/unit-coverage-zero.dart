import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

// Conservative classification for libraries to which the VM assigns no lines.
// Any concrete body, constructor, mutable field or unknown declaration refuses.
bool hasNoExecutableDeclarations(String path) {
  final unit = parseString(
    content: File(path).readAsStringSync(),
    path: path,
    throwIfDiagnostics: true,
  ).unit;
  return unit.declarations.every((declaration) {
    if (declaration is TopLevelVariableDeclaration) {
      return declaration.variables.isConst;
    }
    if (declaration is GenericTypeAlias || declaration is FunctionTypeAlias) {
      return true;
    }
    if (declaration is ClassDeclaration &&
        declaration.abstractKeyword != null) {
      return declaration.body.members.every(
        (member) =>
            member is MethodDeclaration && member.body is EmptyFunctionBody,
      );
    }
    return false;
  });
}

void main(List<String> arguments) {
  if (arguments.isNotEmpty && arguments.first == '--references') {
    final references = <String, String?>{};
    for (final path in arguments.skip(1)) {
      final unit = parseString(
        content: File(path).readAsStringSync(),
        path: path,
        throwIfDiagnostics: true,
      ).unit;
      String? selected;
      for (final declaration in unit.declarations) {
        if (declaration is ClassDeclaration) {
          final name = declaration.namePart.beginToken.lexeme;
          if (!name.startsWith('_')) {
            selected = name;
            break;
          }
        }
      }
      if (selected == null) {
        for (final declaration in unit.declarations) {
          if (declaration is FunctionDeclaration &&
              !declaration.isGetter &&
              !declaration.isSetter &&
              !declaration.name.lexeme.startsWith('_')) {
            selected = declaration.name.lexeme;
            break;
          }
        }
      }
      references[path] = selected;
    }
    stdout.writeln(jsonEncode(references));
    return;
  }
  final result = <String>[];
  for (final path in arguments) {
    if (hasNoExecutableDeclarations(path)) result.add(path);
  }
  stdout.writeln(jsonEncode(result));
}
