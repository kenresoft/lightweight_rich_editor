import 'package:flutter/foundation.dart' show immutable;
import 'package:flutter/painting.dart';

/// What a highlighted run of code is.
enum CodeTokenKind { comment, string, number, keyword, type, literal }

/// A highlighted range of a code block's text (`[start, end)`, relative to the
/// text that was tokenised).
class CodeToken {
  const CodeToken(this.start, this.end, this.kind);
  final int start;
  final int end;
  final CodeTokenKind kind;
}

/// Token colours for a code block. Presentation only — never stored in the
/// document, and only ever changes a glyph's colour, so it cannot move a line.
@immutable
class CodeSyntaxColors {
  const CodeSyntaxColors({
    required this.comment,
    required this.string,
    required this.number,
    required this.keyword,
    required this.type,
    required this.literal,
  });

  final Color comment;
  final Color string;
  final Color number;
  final Color keyword;
  final Color type;
  final Color literal;

  /// For a light code background.
  static const light = CodeSyntaxColors(
    comment: Color(0xFF6A737D),
    string: Color(0xFF0A5C36),
    number: Color(0xFF0B57B0),
    keyword: Color(0xFFC62828),
    type: Color(0xFF7B3FC4),
    literal: Color(0xFF0B57B0),
  );

  /// For a dark code background.
  static const dark = CodeSyntaxColors(
    comment: Color(0xFF8B949E),
    string: Color(0xFFA5D6FF),
    number: Color(0xFF79C0FF),
    keyword: Color(0xFFFF7B72),
    type: Color(0xFFD2A8FF),
    literal: Color(0xFF79C0FF),
  );

  Color colorOf(CodeTokenKind kind) => switch (kind) {
    CodeTokenKind.comment => comment,
    CodeTokenKind.string => string,
    CodeTokenKind.number => number,
    CodeTokenKind.keyword => keyword,
    CodeTokenKind.type => type,
    CodeTokenKind.literal => literal,
  };

  @override
  bool operator ==(Object other) =>
      other is CodeSyntaxColors &&
      other.comment == comment &&
      other.string == string &&
      other.number == number &&
      other.keyword == keyword &&
      other.type == type &&
      other.literal == literal;

  @override
  int get hashCode => Object.hash(comment, string, number, keyword, type, literal);
}

class _Lang {
  const _Lang({
    this.lineComments = const [],
    this.blockComment,
    this.quotes = '\'"',
    this.tripleQuotes = false,
    this.keywords = const {},
    this.literals = const {'true', 'false', 'null'},
    this.caseInsensitive = false,
    this.capitalisedIsType = true,
    this.markup = false,
  });

  final List<String> lineComments;
  final (String, String)? blockComment;
  final String quotes;
  final bool tripleQuotes;
  final Set<String> keywords;
  final Set<String> literals;
  final bool caseInsensitive;
  final bool capitalisedIsType;
  final bool markup;
}

const _cLikeComments = ['//'];
const _cBlock = ('/*', '*/');

const _dart = _Lang(
  lineComments: _cLikeComments,
  blockComment: _cBlock,
  keywords: {
    'abstract', 'as', 'assert', 'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'covariant', 'default', 'deferred', 'do', 'dynamic', 'else', 'enum', 'export', 'extends', 'extension',
    'external', 'factory', 'final', 'finally', 'for', 'get', 'hide', 'if', 'implements', 'import', 'in',
    'interface', 'is', 'late', 'library', 'mixin', 'new', 'of', 'on', 'operator', 'part', 'required',
    'rethrow', 'return', 'sealed', 'set', 'show', 'static', 'super', 'switch', 'sync', 'this', 'throw', 'try',
    'typedef', 'var', 'void', 'when', 'while', 'with', 'yield',
  },
);

const _js = _Lang(
  lineComments: _cLikeComments,
  blockComment: _cBlock,
  quotes: '\'"`',
  keywords: {
    'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue', 'debugger', 'default', 'delete',
    'do', 'else', 'export', 'extends', 'finally', 'for', 'from', 'function', 'if', 'import', 'in', 'instanceof',
    'let', 'new', 'of', 'return', 'static', 'super', 'switch', 'this', 'throw', 'try', 'typeof', 'var', 'void',
    'while', 'with', 'yield', 'interface', 'type', 'enum', 'implements', 'public', 'private', 'protected',
    'readonly', 'abstract', 'declare', 'namespace', 'as', 'is', 'keyof',
  },
  literals: {'true', 'false', 'null', 'undefined', 'NaN', 'Infinity'},
);

const _java = _Lang(
  lineComments: _cLikeComments,
  blockComment: _cBlock,
  keywords: {
    'abstract', 'assert', 'break', 'case', 'catch', 'class', 'continue', 'default', 'do', 'else', 'enum',
    'extends', 'final', 'finally', 'for', 'if', 'implements', 'import', 'instanceof', 'interface', 'native',
    'new', 'package', 'private', 'protected', 'public', 'return', 'static', 'super', 'switch', 'synchronized',
    'this', 'throw', 'throws', 'try', 'void', 'volatile', 'while', 'var', 'record',
    // Kotlin / C# overlap
    'fun', 'val', 'when', 'object', 'is', 'in', 'as', 'override', 'open', 'data', 'companion', 'lateinit',
    'namespace', 'using', 'readonly', 'sealed', 'string', 'int', 'bool', 'double', 'float', 'long', 'char',
    'byte', 'short', 'boolean',
  },
);

const _swift = _Lang(
  lineComments: _cLikeComments,
  blockComment: _cBlock,
  keywords: {
    'associatedtype', 'class', 'deinit', 'enum', 'extension', 'fileprivate', 'func', 'import', 'init', 'inout',
    'internal', 'let', 'open', 'operator', 'private', 'protocol', 'public', 'static', 'struct', 'subscript',
    'typealias', 'var', 'break', 'case', 'continue', 'default', 'defer', 'do', 'else', 'fallthrough', 'for',
    'guard', 'if', 'in', 'repeat', 'return', 'switch', 'where', 'while', 'as', 'catch', 'is', 'super', 'self',
    'throw', 'throws', 'try', 'async', 'await', 'some', 'any',
  },
  literals: {'true', 'false', 'nil'},
);

const _c = _Lang(
  lineComments: _cLikeComments,
  blockComment: _cBlock,
  keywords: {
    'auto', 'break', 'case', 'char', 'const', 'continue', 'default', 'do', 'double', 'else', 'enum', 'extern',
    'float', 'for', 'goto', 'if', 'inline', 'int', 'long', 'register', 'return', 'short', 'signed', 'sizeof',
    'static', 'struct', 'switch', 'typedef', 'union', 'unsigned', 'void', 'volatile', 'while', 'class',
    'namespace', 'template', 'typename', 'public', 'private', 'protected', 'virtual', 'new', 'delete', 'this',
    'using', 'bool', 'try', 'catch', 'throw', 'constexpr', 'nullptr', 'override', 'final', 'explicit',
  },
  literals: {'true', 'false', 'NULL', 'nullptr'},
);

const _go = _Lang(
  lineComments: _cLikeComments,
  blockComment: _cBlock,
  quotes: '\'"`',
  keywords: {
    'break', 'case', 'chan', 'const', 'continue', 'default', 'defer', 'else', 'fallthrough', 'for', 'func',
    'go', 'goto', 'if', 'import', 'interface', 'map', 'package', 'range', 'return', 'select', 'struct',
    'switch', 'type', 'var',
  },
  literals: {'true', 'false', 'nil', 'iota'},
);

const _rust = _Lang(
  lineComments: _cLikeComments,
  blockComment: _cBlock,
  keywords: {
    'as', 'async', 'await', 'break', 'const', 'continue', 'crate', 'dyn', 'else', 'enum', 'extern', 'fn', 'for',
    'if', 'impl', 'in', 'let', 'loop', 'match', 'mod', 'move', 'mut', 'pub', 'ref', 'return', 'self', 'Self',
    'static', 'struct', 'super', 'trait', 'type', 'unsafe', 'use', 'where', 'while',
  },
);

const _python = _Lang(
  lineComments: ['#'],
  tripleQuotes: true,
  keywords: {
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def', 'del', 'elif', 'else',
    'except', 'finally', 'for', 'from', 'global', 'if', 'import', 'in', 'is', 'lambda', 'nonlocal', 'not',
    'or', 'pass', 'raise', 'return', 'try', 'while', 'with', 'yield', 'self', 'match', 'case',
  },
  literals: {'True', 'False', 'None'},
);

const _shell = _Lang(
  lineComments: ['#'],
  keywords: {
    'if', 'then', 'else', 'elif', 'fi', 'for', 'while', 'until', 'do', 'done', 'case', 'esac', 'in', 'function',
    'select', 'return', 'exit', 'export', 'local', 'readonly', 'unset', 'source', 'alias', 'echo', 'cd', 'sudo',
  },
  capitalisedIsType: false,
);

const _sql = _Lang(
  lineComments: ['--'],
  blockComment: _cBlock,
  quotes: '\'',
  caseInsensitive: true,
  capitalisedIsType: false,
  keywords: {
    'select', 'from', 'where', 'insert', 'into', 'values', 'update', 'set', 'delete', 'create', 'table', 'alter',
    'drop', 'index', 'view', 'join', 'inner', 'left', 'right', 'outer', 'full', 'cross', 'on', 'as', 'and', 'or',
    'not', 'in', 'is', 'like', 'between', 'group', 'by', 'order', 'having', 'limit', 'offset', 'union', 'all',
    'distinct', 'case', 'when', 'then', 'else', 'end', 'primary', 'key', 'foreign', 'references', 'default',
    'constraint', 'unique', 'with', 'exists', 'asc', 'desc', 'begin', 'commit', 'rollback', 'int', 'integer',
    'text', 'varchar', 'boolean', 'date', 'timestamp',
  },
);

const _json = _Lang(quotes: '"', capitalisedIsType: false);

const _yaml = _Lang(lineComments: ['#'], capitalisedIsType: false, literals: {'true', 'false', 'null', 'yes', 'no'});

const _css = _Lang(blockComment: _cBlock, capitalisedIsType: false, literals: {});

const _markup = _Lang(markup: true, quotes: '\'"', capitalisedIsType: false);

const Map<String, _Lang> _languages = {
  'dart': _dart,
  'javascript': _js, 'js': _js, 'jsx': _js, 'mjs': _js, 'typescript': _js, 'ts': _js, 'tsx': _js,
  'java': _java, 'kotlin': _java, 'kt': _java, 'csharp': _java, 'cs': _java, 'c#': _java, 'scala': _java,
  'swift': _swift,
  'c': _c, 'cpp': _c, 'c++': _c, 'cc': _c, 'h': _c, 'hpp': _c, 'objc': _c,
  'go': _go, 'golang': _go,
  'rust': _rust, 'rs': _rust,
  'python': _python, 'py': _python,
  'shell': _shell, 'sh': _shell, 'bash': _shell, 'zsh': _shell, 'terminal': _shell, 'console': _shell,
  'sql': _sql,
  'json': _json, 'jsonc': _json,
  'yaml': _yaml, 'yml': _yaml, 'toml': _yaml,
  'css': _css, 'scss': _css,
  'html': _markup, 'xml': _markup, 'svg': _markup, 'xhtml': _markup,
};

/// Whether [language] (a normalised label such as `dart`) has a tokenizer.
bool canHighlight(String? language) => language != null && _languages.containsKey(language);

bool _isIdentStart(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x24;
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isIdentPart(int c) => _isIdentStart(c) || _isDigit(c);

/// Splits [code] into highlighted runs for [language]; runs not returned are
/// plain. A single pass, linear in the text length, with no regular
/// expressions. An unknown or null language yields no tokens.
List<CodeToken> tokenizeCode(String code, String? language) {
  final lang = language == null ? null : _languages[language];
  if (lang == null || code.isEmpty) return const [];
  final out = <CodeToken>[];
  final n = code.length;
  var i = 0;

  bool startsWith(String s, int at) => code.startsWith(s, at);

  while (i < n) {
    final c = code.codeUnitAt(i);

    if (lang.markup) {
      if (startsWith('<!--', i)) {
        final end = code.indexOf('-->', i + 4);
        final stop = end == -1 ? n : end + 3;
        out.add(CodeToken(i, stop, CodeTokenKind.comment));
        i = stop;
        continue;
      }
      if (c == 0x3C) {
        // <tag or </tag
        var j = i + 1;
        if (j < n && code.codeUnitAt(j) == 0x2F) j++;
        final nameStart = j;
        while (j < n && (_isIdentPart(code.codeUnitAt(j)) || code.codeUnitAt(j) == 0x2D || code.codeUnitAt(j) == 0x3A)) {
          j++;
        }
        if (j > nameStart) out.add(CodeToken(nameStart, j, CodeTokenKind.keyword));
        i = j > i + 1 ? j : i + 1;
        continue;
      }
    }

    // Comments
    var matchedComment = false;
    for (final prefix in lang.lineComments) {
      if (startsWith(prefix, i)) {
        var end = code.indexOf('\n', i);
        if (end == -1) end = n;
        out.add(CodeToken(i, end, CodeTokenKind.comment));
        i = end;
        matchedComment = true;
        break;
      }
    }
    if (matchedComment) continue;
    final block = lang.blockComment;
    if (block != null && startsWith(block.$1, i)) {
      final end = code.indexOf(block.$2, i + block.$1.length);
      final stop = end == -1 ? n : end + block.$2.length;
      out.add(CodeToken(i, stop, CodeTokenKind.comment));
      i = stop;
      continue;
    }

    // Strings
    if (lang.quotes.codeUnits.contains(c)) {
      final q = String.fromCharCode(c);
      var j = i + 1;
      var stop = n;
      if (lang.tripleQuotes && startsWith(q * 3, i)) {
        final end = code.indexOf(q * 3, i + 3);
        stop = end == -1 ? n : end + 3;
      } else {
        final multiline = q == '`';
        while (j < n) {
          final d = code.codeUnitAt(j);
          if (d == 0x5C) {
            j += 2;
            continue;
          }
          if (d == c) {
            stop = j + 1;
            break;
          }
          if (d == 0x0A && !multiline) {
            stop = j; // an unterminated string ends with its line
            break;
          }
          j++;
        }
        if (j >= n) stop = n;
      }
      out.add(CodeToken(i, stop, CodeTokenKind.string));
      i = stop;
      continue;
    }

    // Numbers (not the tail of an identifier)
    if (_isDigit(c) && (i == 0 || !_isIdentPart(code.codeUnitAt(i - 1)))) {
      var j = i + 1;
      while (j < n) {
        final d = code.codeUnitAt(j);
        if (_isDigit(d) || d == 0x2E || d == 0x5F || (d >= 0x61 && d <= 0x66) || (d >= 0x41 && d <= 0x46) || d == 0x78 || d == 0x58) {
          j++;
        } else {
          break;
        }
      }
      out.add(CodeToken(i, j, CodeTokenKind.number));
      i = j;
      continue;
    }

    // Words
    if (_isIdentStart(c)) {
      var j = i + 1;
      while (j < n && _isIdentPart(code.codeUnitAt(j))) {
        j++;
      }
      final word = code.substring(i, j);
      final key = lang.caseInsensitive ? word.toLowerCase() : word;
      if (lang.keywords.contains(key)) {
        out.add(CodeToken(i, j, CodeTokenKind.keyword));
      } else if (lang.literals.contains(key)) {
        out.add(CodeToken(i, j, CodeTokenKind.literal));
      } else if (lang.capitalisedIsType && c >= 0x41 && c <= 0x5A && j - i > 1 && word != word.toUpperCase()) {
        out.add(CodeToken(i, j, CodeTokenKind.type));
      }
      i = j;
      continue;
    }

    i++;
  }
  return out;
}
