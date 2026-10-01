/// Block-level code is paragraph metadata, not an inline attribute: every line
/// of a code block is its own paragraph whose block level is [codeBlockLevel]
/// or `code:<language>`. It rides on `ParagraphRecord.headerLevel` (the field
/// that already carries block metadata through split, merge, undo and the
/// interchange format), so a code line is simply a paragraph whose level is not
/// `h1`/`h2`/`h3`.
const String codeBlockLevel = 'code';

/// Whether a paragraph block level denotes a code line.
bool isCodeBlockLevel(String? level) =>
    level != null && (level == codeBlockLevel || level.startsWith('$codeBlockLevel:'));

/// The language label of a code block level, or `null` if unlabelled.
String? codeBlockLanguage(String? level) {
  if (level == null || !level.startsWith('$codeBlockLevel:')) return null;
  final lang = level.substring(codeBlockLevel.length + 1);
  return lang.isEmpty ? null : lang;
}

/// The block level for a code block with an optional [language] label
/// (normalized: trimmed, lower-cased, restricted to `[a-z0-9_+#.-]`).
String codeBlockLevelFor([String? language]) {
  final lang = normalizeCodeLanguage(language);
  return lang == null ? codeBlockLevel : '$codeBlockLevel:$lang';
}

/// Normalizes a fence info string / `class="language-x"` token.
String? normalizeCodeLanguage(String? language) {
  if (language == null) return null;
  final cleaned = language.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9_+#.\-]'), '');
  return cleaned.isEmpty ? null : cleaned;
}
