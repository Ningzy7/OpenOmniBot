import 'dart:convert';
import 'dart:math' as math;

enum CodexDiffLineKind { header, add, remove, context, meta }

class CodexDiffLine {
  const CodexDiffLine({
    required this.kind,
    required this.content,
    required this.prefix,
    this.oldLineNumber,
    this.newLineNumber,
  });

  final CodexDiffLineKind kind;
  final String content;
  final String prefix;
  final int? oldLineNumber;
  final int? newLineNumber;
}

class CodexDiffFile {
  const CodexDiffFile({
    required this.oldPath,
    required this.newPath,
    required this.displayPath,
    required this.lines,
    required this.additions,
    required this.deletions,
    required this.isNewFile,
    required this.isDeletedFile,
  });

  final String? oldPath;
  final String? newPath;
  final String displayPath;
  final List<CodexDiffLine> lines;
  final int additions;
  final int deletions;
  final bool isNewFile;
  final bool isDeletedFile;
}

class CodexDiffSummary {
  const CodexDiffSummary({
    required this.files,
    required this.additions,
    required this.deletions,
    required this.sourceText,
  });

  final List<CodexDiffFile> files;
  final int additions;
  final int deletions;
  final String sourceText;

  bool get hasChanges => files.isNotEmpty && (additions > 0 || deletions > 0);
  int get changedFileCount => files.length;

  String get primaryPath {
    for (final file in files) {
      if (file.displayPath.trim().isNotEmpty) {
        return file.displayPath;
      }
    }
    return '';
  }
}

CodexDiffSummary parseCodexDiffText(String diffText) {
  final normalized = _normalizeNewlines(diffText).trimRight();
  if (normalized.trim().isEmpty) {
    return const CodexDiffSummary(
      files: <CodexDiffFile>[],
      additions: 0,
      deletions: 0,
      sourceText: '',
    );
  }

  final parser = _UnifiedDiffParser(normalized);
  return parser.parse();
}

String? extractCodexDiffText(
  dynamic source, {
  String outputText = '',
  String progress = '',
  String summary = '',
}) {
  final candidates = <String>[
    outputText,
    progress,
    summary,
    ..._extractDiffCandidates(source),
  ];
  final unique = <String>{};
  final matches = <String>[];
  for (final candidate in candidates) {
    final normalized = _normalizeNewlines(candidate).trimRight();
    if (normalized.trim().isEmpty ||
        !looksLikeCodexDiff(normalized) ||
        !unique.add(normalized)) {
      continue;
    }
    matches.add(normalized);
  }
  if (matches.isEmpty) {
    return null;
  }
  return matches.join('\n');
}

String? extractCodexDiffPath(dynamic source) {
  return _extractFirstPathCandidate(source);
}

bool looksLikeCodexDiff(String value) {
  final text = _normalizeNewlines(value).trim();
  if (text.isEmpty) {
    return false;
  }
  if (text.contains('diff --git ') ||
      RegExp(r'(^|\n)@@\s+-\d').hasMatch(text)) {
    return true;
  }
  final lines = text.split('\n');
  final hasOldHeader = lines.any((line) => line.startsWith('--- '));
  final hasNewHeader = lines.any((line) => line.startsWith('+++ '));
  final hasHunk = lines.any((line) => line.startsWith('@@ '));
  return hasOldHeader && hasNewHeader && hasHunk;
}

String formatCodexDiffStat({required int additions, required int deletions}) {
  return '+${_compactCount(additions)} -${_compactCount(deletions)}';
}

String summarizeCodexDiff(CodexDiffSummary summary) {
  if (summary.files.isEmpty) {
    return '';
  }
  final fileLabel = summary.files.length == 1
      ? '1 file'
      : '${summary.files.length} files';
  return '$fileLabel · ${formatCodexDiffStat(additions: summary.additions, deletions: summary.deletions)}';
}

List<String> _extractDiffCandidates(dynamic value) {
  if (value == null) {
    return const <String>[];
  }
  if (value is String) {
    final decoded = _tryDecodeJson(value);
    if (decoded != null && decoded != value) {
      return <String>[value, ..._extractDiffCandidates(decoded)];
    }
    return <String>[value];
  }
  if (value is Iterable) {
    final out = <String>[];
    for (final item in value) {
      out.addAll(_extractDiffCandidates(item));
    }
    return out;
  }
  if (value is! Map) {
    return <String>[value.toString()];
  }

  final map = value.map((key, nested) => MapEntry(key.toString(), nested));
  final out = <String>[];
  for (final key in const <String>[
    'diff',
    'patch',
    'unifiedDiff',
    'unified_diff',
    'diffText',
    'rawResultJson',
    'resultPreviewJson',
    'argsJson',
    'delta',
    'output',
    'text',
    'content',
  ]) {
    if (map.containsKey(key)) {
      for (final candidate in _extractDiffCandidates(map[key])) {
        out.add(_normalizeDiffCandidateForContainer(candidate, map));
      }
    }
  }

  final oldText = _stringValue(
    map['oldString'] ?? map['oldText'] ?? map['before'],
  );
  final newText = _stringValue(
    map['newString'] ?? map['newText'] ?? map['after'],
  );
  if (oldText != null && newText != null) {
    out.add(
      buildCodexUnifiedDiffFromStrings(
        oldText: oldText,
        newText: newText,
        path: _stringValue(
          map['path'] ??
              map['filePath'] ??
              map['file_path'] ??
              map['filename'] ??
              map['fileName'],
        ),
      ),
    );
  }

  for (final key in const <String>[
    'item',
    'result',
    'changes',
    'files',
    'fileChanges',
    'entries',
  ]) {
    if (map.containsKey(key)) {
      for (final candidate in _extractDiffCandidates(map[key])) {
        out.add(_normalizeDiffCandidateForContainer(candidate, map));
      }
    }
  }
  return out;
}

String _normalizeDiffCandidateForContainer(
  String candidate,
  Map<String, dynamic> container,
) {
  final normalized = _normalizeNewlines(candidate).trimRight();
  if (!_looksLikeHunkOnlyDiff(normalized)) {
    return normalized;
  }
  final pathInfo = _diffPathInfoFromMap(container);
  if (pathInfo == null) {
    return normalized;
  }
  return buildCodexUnifiedDiffFromPatch(
    diffText: normalized,
    oldPath: pathInfo.oldPath,
    newPath: pathInfo.newPath,
    changeKind: pathInfo.changeKind,
  );
}

bool _looksLikeHunkOnlyDiff(String value) {
  final text = _normalizeNewlines(value).trimLeft();
  if (text.isEmpty ||
      text.contains('diff --git ') ||
      text.startsWith('--- ') ||
      text.startsWith('+++ ')) {
    return false;
  }
  return RegExp(r'^@@\s+-\d').hasMatch(text);
}

_DiffPathInfo? _diffPathInfoFromMap(Map<String, dynamic> map) {
  final changeKind = _changeKindFromMap(map);
  final basePath = _stringValue(
    map['path'] ??
        map['filePath'] ??
        map['file_path'] ??
        map['filename'] ??
        map['fileName'],
  );
  final oldPath =
      _stringValue(
        map['oldPath'] ??
            map['old_path'] ??
            map['sourcePath'] ??
            map['source_path'] ??
            map['fromPath'] ??
            map['from_path'],
      ) ??
      basePath;
  final newPath =
      _stringValue(
        map['newPath'] ??
            map['new_path'] ??
            map['targetPath'] ??
            map['target_path'] ??
            map['movePath'] ??
            map['move_path'] ??
            map['toPath'] ??
            map['to_path'],
      ) ??
      basePath;
  if (oldPath == null && newPath == null) {
    return null;
  }
  return _DiffPathInfo(
    oldPath: oldPath,
    newPath: newPath,
    changeKind: changeKind,
  );
}

String? _changeKindFromMap(Map<String, dynamic> map) {
  final kind = map['kind'];
  if (kind is Map) {
    return _stringValue(kind['type'] ?? kind['kind']);
  }
  return _stringValue(kind ?? map['changeKind'] ?? map['change_kind']);
}

class _DiffPathInfo {
  const _DiffPathInfo({this.oldPath, this.newPath, this.changeKind});

  final String? oldPath;
  final String? newPath;
  final String? changeKind;
}

String buildCodexUnifiedDiffFromPatch({
  required String diffText,
  String? oldPath,
  String? newPath,
  String? changeKind,
}) {
  final normalized = _normalizeNewlines(diffText).trimRight();
  if (normalized.trim().isEmpty || !_looksLikeHunkOnlyDiff(normalized)) {
    return normalized;
  }

  final normalizedKind = (changeKind ?? '').trim().toLowerCase();
  final isAdd = const <String>{
    'add',
    'added',
    'create',
    'created',
    'new',
  }.contains(normalizedKind);
  final isDelete = const <String>{
    'delete',
    'deleted',
    'remove',
    'removed',
  }.contains(normalizedKind);
  final effectiveOldPath = oldPath?.trim().isNotEmpty == true
      ? oldPath!.trim()
      : newPath?.trim();
  final effectiveNewPath = newPath?.trim().isNotEmpty == true
      ? newPath!.trim()
      : oldPath?.trim();
  final displayPath = effectiveNewPath?.trim().isNotEmpty == true
      ? effectiveNewPath!
      : effectiveOldPath;
  if (displayPath == null || displayPath.trim().isEmpty) {
    return normalized;
  }

  final oldHeaderPath = isAdd
      ? '/dev/null'
      : 'a/${effectiveOldPath ?? displayPath}';
  final newHeaderPath = isDelete
      ? '/dev/null'
      : 'b/${effectiveNewPath ?? displayPath}';
  final diffOldPath = effectiveOldPath ?? displayPath;
  final diffNewPath = effectiveNewPath ?? displayPath;
  return <String>[
    'diff --git a/$diffOldPath b/$diffNewPath',
    '--- $oldHeaderPath',
    '+++ $newHeaderPath',
    normalized,
  ].join('\n');
}

String buildCodexUnifiedDiffFromStrings({
  required String oldText,
  required String newText,
  String? path,
}) {
  final displayPath = path?.trim().isNotEmpty == true ? path!.trim() : 'file';
  final oldLines = _normalizeNewlines(oldText).split('\n');
  final newLines = _normalizeNewlines(newText).split('\n');
  final oldCount = oldText.isEmpty ? 0 : oldLines.length;
  final newCount = newText.isEmpty ? 0 : newLines.length;
  final lines = <String>[
    '--- a/$displayPath',
    '+++ b/$displayPath',
    '@@ -1,$oldCount +1,$newCount @@',
    ..._buildLineDiff(oldText, newText),
  ];
  return lines.join('\n');
}

List<String> _buildLineDiff(String oldText, String newText) {
  final oldLines = oldText.isEmpty
      ? <String>[]
      : _normalizeNewlines(oldText).split('\n');
  final newLines = newText.isEmpty
      ? <String>[]
      : _normalizeNewlines(newText).split('\n');
  final m = oldLines.length;
  final n = newLines.length;
  final dp = List<List<int>>.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
  for (var i = m - 1; i >= 0; i -= 1) {
    for (var j = n - 1; j >= 0; j -= 1) {
      if (oldLines[i] == newLines[j]) {
        dp[i][j] = dp[i + 1][j + 1] + 1;
      } else {
        dp[i][j] = math.max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
  }

  final out = <String>[];
  var i = 0;
  var j = 0;
  while (i < m && j < n) {
    if (oldLines[i] == newLines[j]) {
      out.add(' ${oldLines[i]}');
      i += 1;
      j += 1;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      out.add('-${oldLines[i]}');
      i += 1;
    } else {
      out.add('+${newLines[j]}');
      j += 1;
    }
  }
  while (i < m) {
    out.add('-${oldLines[i]}');
    i += 1;
  }
  while (j < n) {
    out.add('+${newLines[j]}');
    j += 1;
  }
  return out;
}

dynamic _tryDecodeJson(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty ||
      !(trimmed.startsWith('{') || trimmed.startsWith('['))) {
    return null;
  }
  try {
    return jsonDecode(trimmed);
  } catch (_) {
    return null;
  }
}

String? _stringValue(dynamic value) {
  final text = value?.toString();
  if (text == null || text.trim().isEmpty) {
    return null;
  }
  return text;
}

String? _extractFirstPathCandidate(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final decoded = _tryDecodeJson(value);
    if (decoded != null && decoded != value) {
      return _extractFirstPathCandidate(decoded);
    }
    final trimmed = value.trim();
    if (_looksLikePathString(trimmed)) {
      return trimmed;
    }
    return null;
  }
  if (value is Iterable) {
    for (final item in value) {
      final path = _extractFirstPathCandidate(item);
      if (path != null) {
        return path;
      }
    }
    return null;
  }
  if (value is! Map) {
    return null;
  }

  final map = value.map((key, nested) => MapEntry(key.toString(), nested));
  final direct = _stringValue(
    map['path'] ??
        map['filePath'] ??
        map['file_path'] ??
        map['filename'] ??
        map['fileName'] ??
        map['newPath'] ??
        map['new_path'] ??
        map['targetPath'] ??
        map['target_path'] ??
        map['movePath'] ??
        map['move_path'] ??
        map['oldPath'] ??
        map['old_path'] ??
        map['sourcePath'] ??
        map['source_path'],
  );
  if (direct != null) {
    return direct;
  }

  for (final key in const <String>[
    'changes',
    'files',
    'fileChanges',
    'entries',
    'arguments',
    'args',
    'input',
    'item',
    'result',
    'rawResultJson',
    'resultPreviewJson',
    'argsJson',
  ]) {
    if (!map.containsKey(key)) {
      continue;
    }
    final path = _extractFirstPathCandidate(map[key]);
    if (path != null) {
      return path;
    }
  }
  return null;
}

bool _looksLikePathString(String value) {
  if (value.isEmpty ||
      value.contains('\n') ||
      looksLikeCodexDiff(value) ||
      value.trim().startsWith('{') ||
      value.trim().startsWith('[')) {
    return false;
  }
  return value.contains('/') ||
      value.contains(r'\') ||
      RegExp(r'^[\w.-]+\.[A-Za-z0-9]{1,12}$').hasMatch(value);
}

String _normalizeNewlines(String value) =>
    value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String _compactCount(int value) {
  if (value.abs() >= 1000000) {
    return '${(value / 1000000).toStringAsFixed(1)}m';
  }
  if (value.abs() >= 1000) {
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
  return value.toString();
}

class _UnifiedDiffParser {
  _UnifiedDiffParser(this.diffText);

  final String diffText;
  final List<CodexDiffFile> _files = <CodexDiffFile>[];

  String? _oldPath;
  String? _newPath;
  String? _displayPath;
  int _additions = 0;
  int _deletions = 0;
  int? _oldLine;
  int? _newLine;
  bool _inHunk = false;
  final List<CodexDiffLine> _lines = <CodexDiffLine>[];

  CodexDiffSummary parse() {
    for (final line in diffText.split('\n')) {
      _parseLine(line);
    }
    _finishFile();
    final additions = _files.fold<int>(0, (sum, file) => sum + file.additions);
    final deletions = _files.fold<int>(0, (sum, file) => sum + file.deletions);
    return CodexDiffSummary(
      files: List<CodexDiffFile>.unmodifiable(_files),
      additions: additions,
      deletions: deletions,
      sourceText: diffText,
    );
  }

  void _parseLine(String line) {
    if (line.startsWith('diff --git ')) {
      _finishFile();
      _startFileFromDiffGit(line);
      return;
    }
    if (line.startsWith('--- ')) {
      if (_inHunk || _lines.isNotEmpty) {
        _finishFile();
      }
      _ensureFile();
      _oldPath = _cleanDiffPath(line.substring(4));
      _displayPath = _chooseDisplayPath();
      return;
    }
    if (line.startsWith('+++ ')) {
      _ensureFile();
      _newPath = _cleanDiffPath(line.substring(4));
      _displayPath = _chooseDisplayPath();
      return;
    }
    if (line.startsWith('@@')) {
      _ensureFile();
      final hunk = _parseHunkHeader(line);
      _oldLine = hunk?.oldStart;
      _newLine = hunk?.newStart;
      _inHunk = true;
      _lines.add(
        CodexDiffLine(
          kind: CodexDiffLineKind.header,
          content: line,
          prefix: '',
        ),
      );
      return;
    }
    if (!_inHunk) {
      if (line.trim().isNotEmpty) {
        _ensureFile();
        _addMeta(line);
      }
      return;
    }

    if (line.startsWith('+')) {
      _ensureFile();
      _lines.add(
        CodexDiffLine(
          kind: CodexDiffLineKind.add,
          content: line.substring(1),
          prefix: '+',
          newLineNumber: _newLine,
        ),
      );
      _newLine = (_newLine ?? 0) + 1;
      _additions += 1;
      return;
    }
    if (line.startsWith('-')) {
      _ensureFile();
      _lines.add(
        CodexDiffLine(
          kind: CodexDiffLineKind.remove,
          content: line.substring(1),
          prefix: '-',
          oldLineNumber: _oldLine,
        ),
      );
      _oldLine = (_oldLine ?? 0) + 1;
      _deletions += 1;
      return;
    }
    if (line.startsWith(r'\ No newline')) {
      _lines.add(
        CodexDiffLine(
          kind: CodexDiffLineKind.header,
          content: line,
          prefix: '',
        ),
      );
      return;
    }

    final content = line.startsWith(' ') ? line.substring(1) : line;
    _lines.add(
      CodexDiffLine(
        kind: CodexDiffLineKind.context,
        content: content,
        prefix: ' ',
        oldLineNumber: _oldLine,
        newLineNumber: _newLine,
      ),
    );
    _oldLine = (_oldLine ?? 0) + 1;
    _newLine = (_newLine ?? 0) + 1;
  }

  void _startFileFromDiffGit(String line) {
    final match = RegExp(r'^diff --git\s+(.+?)\s+(.+)$').firstMatch(line);
    _oldPath = match == null ? null : _cleanDiffPath(match.group(1)!);
    _newPath = match == null ? null : _cleanDiffPath(match.group(2)!);
    _displayPath = _chooseDisplayPath();
  }

  void _ensureFile() {
    _displayPath ??= _chooseDisplayPath();
  }

  void _addMeta(String line) {
    _lines.add(
      CodexDiffLine(kind: CodexDiffLineKind.meta, content: line, prefix: ''),
    );
  }

  void _finishFile() {
    if (_displayPath == null && _lines.isEmpty) {
      return;
    }
    final oldPath = _oldPath;
    final newPath = _newPath;
    final displayPath = _displayPath ?? _chooseDisplayPath() ?? 'Changes';
    _files.add(
      CodexDiffFile(
        oldPath: oldPath,
        newPath: newPath,
        displayPath: displayPath,
        lines: List<CodexDiffLine>.unmodifiable(_lines),
        additions: _additions,
        deletions: _deletions,
        isNewFile: oldPath == null || oldPath == '/dev/null',
        isDeletedFile: newPath == null || newPath == '/dev/null',
      ),
    );
    _oldPath = null;
    _newPath = null;
    _displayPath = null;
    _oldLine = null;
    _newLine = null;
    _inHunk = false;
    _additions = 0;
    _deletions = 0;
    _lines.clear();
  }

  String? _chooseDisplayPath() {
    final next = _pathOrNull(_newPath);
    if (next != null) {
      return next;
    }
    return _pathOrNull(_oldPath);
  }

  String? _pathOrNull(String? value) {
    if (value == null || value == '/dev/null') {
      return null;
    }
    return value;
  }
}

class _HunkHeader {
  const _HunkHeader({required this.oldStart, required this.newStart});

  final int oldStart;
  final int newStart;
}

_HunkHeader? _parseHunkHeader(String line) {
  final match = RegExp(
    r'^@@\s+-(\d+)(?:,\d+)?\s+\+(\d+)(?:,\d+)?',
  ).firstMatch(line);
  if (match == null) {
    return null;
  }
  return _HunkHeader(
    oldStart: int.tryParse(match.group(1) ?? '') ?? 0,
    newStart: int.tryParse(match.group(2) ?? '') ?? 0,
  );
}

String _cleanDiffPath(String raw) {
  var path = raw.trim();
  if (path.startsWith('"') && path.endsWith('"') && path.length >= 2) {
    path = path.substring(1, path.length - 1);
  }
  final tabIndex = path.indexOf('\t');
  if (tabIndex >= 0) {
    path = path.substring(0, tabIndex);
  }
  if (path == '/dev/null') {
    return path;
  }
  if (path.startsWith('a/') || path.startsWith('b/')) {
    return path.substring(2);
  }
  return path;
}
