#!/usr/bin/env dart

// Grok Build and GitHub Copilot dart-analyze hook.
//
// after-save  — PostToolUse after a write. Fix ERROR/WARNING in saved files.
//               Diagnostics only in other files may wait during a multi-file
//               refactor.
// before-run  — PreToolUse before flutter/dart test or run. Deny unless the
//               workspace is clean.
//
// Invoke with `dart` so Linux, macOS, and Windows share one entrypoint.

import 'dart:convert';
import 'dart:io';

final _editTools = RegExp(
  r'(search_replace|write|Write|Edit|create|edit|str_replace_editor|'
  r'apply_patch|MultiEdit)$',
  caseSensitive: false,
);
final _launchTools = RegExp('launch_app', caseSensitive: false);
final _runCommand = RegExp(
  r'(?:^|[;&|\n]|\b(?:then|do|if)\b)\s*&?\s*'
  r'(?:flutter|dart)(?:\.bat|\.cmd|\.exe)?\s+'
  r'(?:test|run|drive)\b',
  caseSensitive: false,
);
final _analyzeSelf = RegExp(
  r'\b(?:dart|flutter)(?:\.bat|\.cmd|\.exe)?\s+analyze\b|'
  r'dart_analyze_hook\.(?:dart|py)\b',
  caseSensitive: false,
);

void main(List<String> args) {
  if (args.length != 1 ||
      (args.first != 'after-save' && args.first != 'before-run')) {
    stderr.writeln('usage: dart_analyze_hook.dart after-save|before-run');
    return;
  }
  try {
    final event = _readEvent();
    if (args.first == 'after-save') {
      _afterSave(event);
    } else {
      _beforeRun(event);
    }
  } catch (error, stack) {
    stderr.writeln('dart_analyze_hook: $error\n$stack');
    if (args.first == 'before-run') {
      _deny(
        'Could not complete workspace dart analyze. Fix the hook failure '
        'before flutter test, dart test, flutter run, or launching the '
        'example.\n$error',
      );
    }
  }
}

Map<String, Object?> _readEvent() {
  final bytes = <int>[];
  while (true) {
    final byte = stdin.readByteSync();
    if (byte < 0) {
      break;
    }
    bytes.add(byte);
  }
  final raw = utf8.decode(bytes);
  if (raw.trim().isEmpty) {
    return const {};
  }
  final decoded = jsonDecode(raw);
  if (decoded is Map<String, Object?>) {
    return decoded;
  }
  if (decoded is Map) {
    return decoded.map((key, value) => MapEntry('$key', value));
  }
  return const {};
}

String _toolName(Map<String, Object?> event) {
  for (final key in ['toolName', 'tool_name']) {
    final value = event[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return '';
}

Map<String, Object?> _toolInput(Map<String, Object?> event) {
  for (final key in ['toolInput', 'tool_input', 'toolArgs', 'tool_args']) {
    var value = event[key];
    if (value is String) {
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const {};
      }
    }
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry('$key', item));
    }
  }
  return const {};
}

Directory _workspace(Map<String, Object?> event) {
  final scriptRoot = File.fromUri(Platform.script).parent.parent.parent;
  if (File.fromUri(scriptRoot.uri.resolve('pubspec.yaml')).existsSync()) {
    return scriptRoot;
  }
  for (final candidate in [
    Platform.environment['GROK_WORKSPACE_ROOT'],
    Platform.environment['CLAUDE_PROJECT_DIR'],
    event['workspaceRoot'],
    event['workspace_root'],
    event['cwd'],
  ]) {
    if (candidate is String && candidate.isNotEmpty) {
      final dir = Directory(candidate);
      if (dir.existsSync() &&
          File.fromUri(dir.uri.resolve('pubspec.yaml')).existsSync()) {
        return dir;
      }
    }
  }
  try {
    final git = Process.runSync('git', ['rev-parse', '--show-toplevel']);
    if (git.exitCode == 0) {
      final path = (git.stdout as String).trim();
      if (path.isNotEmpty) {
        return Directory(path);
      }
    }
  } catch (_) {}
  return Directory.current;
}

void _pathsFrom(Object? node, List<String> found) {
  if (node is String && node.isNotEmpty) {
    found.add(node);
    return;
  }
  if (node is List) {
    for (final item in node) {
      _pathsFrom(item, found);
    }
    return;
  }
  if (node is! Map) {
    return;
  }
  for (final key in ['file_path', 'filePath', 'path', 'target_file']) {
    final value = node[key];
    if (value is String && value.isNotEmpty) {
      found.add(value);
    }
  }
  for (final key in ['files', 'edits']) {
    if (node.containsKey(key)) {
      _pathsFrom(node[key], found);
    }
  }
}

bool _isAnalyzeTarget(File path) {
  final name = path.uri.pathSegments.isEmpty
      ? path.path
      : path.uri.pathSegments.last;
  if (name == 'pubspec.yaml' || name == 'analysis_options.yaml') {
    return true;
  }
  return name.endsWith('.dart');
}

void _emit(Map<String, Object?> payload) {
  stdout.writeln(jsonEncode(payload));
}

void _allow() {
  _emit(const {'decision': 'allow', 'permissionDecision': 'allow'});
}

void _deny(String msg) {
  _emit({
    'decision': 'deny',
    'reason': msg,
    'permissionDecision': 'deny',
    'permissionDecisionReason': msg,
  });
}

class _AnalyzeResult {
  const _AnalyzeResult.ok(this.diags) : failed = false, error = '';

  const _AnalyzeResult.failed(this.error) : diags = const [], failed = true;

  final List<Map<String, String>> diags;
  final bool failed;
  final String error;
}

String _canon(String path) {
  final normalized = File(path).absolute.path.replaceAll(r'\', '/');
  if (Platform.isWindows) {
    return normalized.toLowerCase();
  }
  return normalized;
}

bool _sameFile(String left, File right) => _canon(left) == _canon(right.path);

_AnalyzeResult _analyze(Directory root, List<File>? targets) {
  final args = <String>['analyze', '--format=json'];
  if (targets != null) {
    args.addAll(targets.map((file) => file.path));
  }
  final ProcessResult proc;
  try {
    proc = Process.runSync(
      Platform.resolvedExecutable,
      args,
      workingDirectory: root.path,
    );
  } catch (error) {
    return _AnalyzeResult.failed('$error');
  }
  final blob = '${proc.stdout}${proc.stderr}';
  final start = blob.indexOf('{');
  if (start < 0) {
    if (proc.exitCode == 0) {
      return const _AnalyzeResult.ok([]);
    }
    final detail = blob.trim();
    return _AnalyzeResult.failed(
      detail.isEmpty ? 'dart analyze exit ${proc.exitCode}' : detail,
    );
  }
  Object? data;
  try {
    data = jsonDecode(blob.substring(start));
  } catch (error) {
    return _AnalyzeResult.failed('dart analyze JSON: $error');
  }
  if (data is! Map) {
    return const _AnalyzeResult.failed('dart analyze JSON was not an object');
  }
  final diags = data['diagnostics'];
  if (diags is! List) {
    if (proc.exitCode == 0) {
      return const _AnalyzeResult.ok([]);
    }
    return const _AnalyzeResult.failed('dart analyze omitted diagnostics');
  }
  final out = <Map<String, String>>[];
  for (final item in diags) {
    if (item is! Map) {
      continue;
    }
    final severity = '${item['severity'] ?? ''}'.toUpperCase();
    if (severity != 'ERROR' && severity != 'WARNING') {
      continue;
    }
    final loc = item['location'] is Map
        ? item['location'] as Map
        : const <String, Object?>{};
    final file = '${loc['file'] ?? loc['path'] ?? ''}';
    final range = loc['range'] is Map
        ? loc['range'] as Map
        : const <String, Object?>{};
    final startLoc = range['start'] is Map
        ? range['start'] as Map
        : const <String, Object?>{};
    final line = '${startLoc['line'] ?? loc['line'] ?? ''}';
    final message = '${item['problemMessage'] ?? item['message'] ?? ''}';
    final code = '${item['code'] ?? ''}';
    out.add({
      'severity': severity,
      'file': file,
      'line': line,
      'code': code,
      'message': message,
    });
  }
  return _AnalyzeResult.ok(out);
}

String _formatDiags(List<Map<String, String>> diags, {int limit = 20}) {
  final lines = <String>[];
  for (final item in diags.take(limit)) {
    var loc = item['file'] ?? '';
    final line = item['line'] ?? '';
    if (line.isNotEmpty) {
      loc = '$loc:$line';
    }
    final code = (item['code'] ?? '').isEmpty ? '' : ' (${item['code']})';
    lines.add('- ${item['severity']} $loc$code: ${item['message']}');
  }
  final extra = diags.length - limit;
  if (extra > 0) {
    lines.add('- … $extra more');
  }
  return lines.join('\n');
}

String _rel(Directory root, File path) {
  final rootCanon = _canon(root.path);
  final fileCanon = _canon(path.path);
  if (fileCanon.startsWith('$rootCanon/')) {
    return fileCanon.substring(rootCanon.length + 1);
  }
  return path.path;
}

void _afterSave(Map<String, Object?> event) {
  final name = _toolName(event);
  if (name.isNotEmpty && !_editTools.hasMatch(name)) {
    return;
  }
  final payload = _toolInput(event);
  final rawPaths = <String>[];
  _pathsFrom(payload, rawPaths);
  if (rawPaths.isEmpty && name.isEmpty) {
    return;
  }
  final root = _workspace(event);
  final saved = <File>[];
  for (final raw in rawPaths) {
    var path = File(raw);
    if (!path.isAbsolute) {
      path = File.fromUri(root.uri.resolve(raw.replaceAll(r'\', '/')));
    }
    if (_isAnalyzeTarget(path)) {
      saved.add(path);
    }
  }
  if (saved.isEmpty) {
    return;
  }
  final result = _analyze(root, saved);
  if (result.failed) {
    return;
  }
  final inSaved = result.diags
      .where((item) => saved.any((path) => _sameFile(item['file'] ?? '', path)))
      .toList();
  if (inSaved.isEmpty) {
    return;
  }
  final listed = saved.map((path) => _rel(root, path)).join(', ');
  final msg =
      'dart analyze found issues in the file(s) just saved. Fix these now. '
      'Errors in other files may wait only while a multi-file refactor is '
      'still in flight.\nSaved: $listed\n${_formatDiags(inSaved)}';
  _emit({
    'decision': 'block',
    'reason': msg,
    'additionalContext': msg,
    'hookSpecificOutput': {
      'hookEventName': 'PostToolUse',
      'additionalContext': msg,
    },
  });
}

String _commandText(Map<String, Object?> event) {
  final payload = _toolInput(event);
  for (final key in ['command', 'cmd', 'script']) {
    final value = payload[key];
    if (value is String) {
      return value;
    }
  }
  final extra = payload['extra_args'];
  if (extra is List) {
    return extra.map((item) => '$item').join(' ');
  }
  return '';
}

void _beforeRun(Map<String, Object?> event) {
  final name = _toolName(event);
  final command = _commandText(event);
  final launch = name.isNotEmpty && _launchTools.hasMatch(name);
  final run = command.isNotEmpty && _runCommand.hasMatch(command);
  if (name.isEmpty && command.isEmpty) {
    _deny(
      'before-run hook received no tool name or command. Denying test/run '
      'until the event can be parsed.',
    );
    return;
  }
  if (!launch && !run) {
    _allow();
    return;
  }
  if (command.isNotEmpty && _analyzeSelf.hasMatch(command)) {
    _allow();
    return;
  }
  final root = _workspace(event);
  final result = _analyze(root, null);
  if (result.failed) {
    _deny(
      'Could not complete workspace dart analyze. Fix this before flutter '
      'test, dart test, flutter run, or launching the example.\n'
      '${result.error}',
    );
    return;
  }
  if (result.diags.isEmpty) {
    _allow();
    return;
  }
  _deny(
    'Workspace dart analyze is not clean. Fix every ERROR and WARNING '
    'before flutter test, dart test, flutter run, or launching the '
    'example.\n${_formatDiags(result.diags)}',
  );
}
