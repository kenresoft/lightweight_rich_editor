import 'package:flutter/material.dart';
import '../models/attribute_type.dart';
import '../models/document_delta.dart';
import '../models/note_document.dart';
import '../models/text_attribute.dart';
import '../utils/rich_editor_config.dart';
import '../utils/string_utils.dart';

class _StyleEvent {
  final int offset;
  final AttributeType? type;
  final bool isStart;
  final dynamic value;

  _StyleEvent({
    required this.offset,
    required this.type,
    required this.isStart,
    this.value,
  });
}

/// A custom [TextEditingController] that supports rich text attributes.
class RichTextEditingController extends TextEditingController {
  /// The list of attributes currently applied to the text.
  List<TextAttribute> attributes;

  /// The configuration for this controller.
  final RichEditorConfig config;

  String _lastText;

  // History system (Delta-based)
  final List<DocumentDelta> _undoStack = [];
  final List<DocumentDelta> _redoStack = [];
  bool _isUndoingOrRedoing = false;

  // Sticky formatting
  final Map<AttributeType, dynamic> _activeToggles = {};

  int _attributesRevision = 0;

  /// The [FocusNode] used by the editor.
  final FocusNode focusNode;
  final bool _ownsFocusNode;

  /// Creates a [RichTextEditingController].
  RichTextEditingController({
    super.text,
    List<TextAttribute>? initialAttributes,
    FocusNode? focusNode,
    this.config = RichEditorConfig.standard,
  })  : attributes = _sanitize(initialAttributes ?? const [], (text ?? '').length),
        _lastText = text ?? '',
        focusNode = focusNode ?? FocusNode(),
        _ownsFocusNode = focusNode == null {
    _optimizeAttributes();
    this.focusNode.addListener(_handleFocusChange);
  }

  void _handleFocusChange() {
    // Selection handles stability handled by framework default
  }

  @override
  void dispose() {
    focusNode.removeListener(_handleFocusChange);
    if (_ownsFocusNode) focusNode.dispose();
    super.dispose();
  }

  static List<TextAttribute> _sanitize(List<TextAttribute> source, int textLength) {
    final List<TextAttribute> result = [];
    for (final attr in source) {
      final int start = clampInt(attr.start, 0, textLength);
      final int end = clampInt(attr.end, 0, textLength);
      if (end > start) {
        result.add(TextAttribute(start: start, end: end, type: attr.type, value: attr.value));
      }
    }
    return result;
  }

  @override
  set value(TextEditingValue newValue) {
    final String oldText = _lastText;
    final String newText = newValue.text;
    final TextSelection oldSelection = selection;

    if (oldText != newText) {
      final int? cursorHint = oldSelection.start >= 0 ? oldSelection.start : null;

      if (!_isUndoingOrRedoing) {
        final oldAttrs = attributes.map((a) => a.copy()).toList();
        _syncAttributesWithTextChange(oldText, newText, cursorHint: cursorHint);

        _recordDelta(
          oldText: oldText,
          newText: newText,
          oldAttrs: oldAttrs,
          oldSelection: oldSelection,
          newSelection: newValue.selection,
        );
      }
    } else if (newValue.selection != oldSelection) {
      if (config.enableStickyFormatting) {
        _activeToggles.clear();
        for (final type in AttributeType.values) {
          if (_isStyleAt(newValue.selection.start, type)) {
            _activeToggles[type] = _getValueAt(newValue.selection.start, type);
          }
        }
      }
    }

    _lastText = newText;
    super.value = newValue;
  }

  void _recordDelta({
    String? oldText,
    String? newText,
    required List<TextAttribute> oldAttrs,
    required TextSelection oldSelection,
    required TextSelection newSelection,
  }) {
    if (_isUndoingOrRedoing) return;

    final removed = oldAttrs.where((a) => !attributes.contains(a)).toList();
    final added = attributes.where((a) => !oldAttrs.contains(a)).toList();

    if (oldText == newText && removed.isEmpty && added.isEmpty) return;

    _undoStack.add(
      DocumentDelta(
        oldText: oldText == newText ? null : oldText,
        newText: oldText == newText ? null : newText,
        removedAttributes: removed.isEmpty ? null : removed,
        addedAttributes: added.isEmpty ? null : added,
        oldSelection: oldSelection,
        newSelection: newSelection,
      ),
    );

    _redoStack.clear();
    if (_undoStack.length > config.maxHistoryLength) _undoStack.removeAt(0);
  }

  /// Reverts the last document change.
  void undo() {
    if (_undoStack.isEmpty) return;
    _isUndoingOrRedoing = true;

    final delta = _undoStack.removeLast();
    _redoStack.add(delta);

    final String targetText = delta.oldText ?? text;
    value = TextEditingValue(text: targetText, selection: delta.oldSelection);

    if (delta.addedAttributes != null) {
      attributes.removeWhere((a) => delta.addedAttributes!.contains(a));
    }
    if (delta.removedAttributes != null) {
      attributes.addAll(delta.removedAttributes!.map((a) => a.copy()));
    }
    _optimizeAttributes();

    _attributesRevision++;
    _isUndoingOrRedoing = false;
    notifyListeners();
  }

  /// Re-applies a previously undone document change.
  void redo() {
    if (_redoStack.isEmpty) return;
    _isUndoingOrRedoing = true;

    final delta = _redoStack.removeLast();
    _undoStack.add(delta);

    final String targetText = delta.newText ?? text;
    value = TextEditingValue(text: targetText, selection: delta.newSelection);

    if (delta.removedAttributes != null) {
      attributes.removeWhere((a) => delta.removedAttributes!.contains(a));
    }
    if (delta.addedAttributes != null) {
      attributes.addAll(delta.addedAttributes!.map((a) => a.copy()));
    }
    _optimizeAttributes();

    _attributesRevision++;
    _isUndoingOrRedoing = false;
    notifyListeners();
  }

  /// Whether there are changes that can be undone.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether there are changes that can be redone.
  bool get canRedo => _redoStack.isNotEmpty;

  void _syncAttributesWithTextChange(String oldText, String newText, {int? cursorHint}) {
    final int oldLen = oldText.length;
    final int newLen = newText.length;
    final int minLength = oldLen < newLen ? oldLen : newLen;

    final int prefixMax = commonPrefixLength(oldText, newText, minLength);
    final int suffixMax = commonSuffixLength(oldText, newText, minLength);

    int prefixLength;
    int suffixLength;

    if (prefixMax + suffixMax > minLength) {
      final int ambiguityLow = minLength - suffixMax;
      final int ambiguityHigh = prefixMax;
      if (cursorHint != null && cursorHint >= ambiguityLow && cursorHint <= ambiguityHigh) {
        prefixLength = cursorHint;
      } else {
        prefixLength = ambiguityHigh;
      }
      suffixLength = minLength - prefixLength;
    } else {
      prefixLength = prefixMax;
      suffixLength = suffixMax;
    }

    final int deleteStart = prefixLength;
    final int deleteEnd = oldLen - suffixLength;
    final int insertedLength = (newLen - suffixLength) - prefixLength;

    final bool didDelete = deleteEnd > deleteStart;
    if (didDelete) {
      _shiftForDeletion(deleteStart, deleteEnd);
    }
    if (insertedLength > 0) {
      _shiftForInsertion(deleteStart, insertedLength);
      for (final entry in _activeToggles.entries) {
        attributes.add(
          TextAttribute(
            start: deleteStart,
            end: deleteStart + insertedLength,
            type: entry.key,
            value: entry.value,
          ),
        );
      }
    }

    _optimizeAttributes();
    _attributesRevision++;
  }

  void _shiftForDeletion(int delStart, int delEnd) {
    for (int i = attributes.length - 1; i >= 0; i--) {
      final attr = attributes[i];

      final int delBefore = (delStart < attr.start)
          ? ((delEnd < attr.start ? delEnd : attr.start) - delStart)
          : 0;

      final int intersectionStart = delStart > attr.start ? delStart : attr.start;
      final int intersectionEnd = delEnd < attr.end ? delEnd : attr.end;
      final int delInside = (intersectionStart < intersectionEnd)
          ? (intersectionEnd - intersectionStart)
          : 0;

      attr.start -= delBefore;
      attr.end -= (delBefore + delInside);

      if (attr.start >= attr.end) {
        attributes.removeAt(i);
      }
    }
  }

  void _shiftForInsertion(int index, int length) {
    for (final attr in attributes) {
      if (index <= attr.start) {
        attr.start += length;
        attr.end += length;
      } else if (index > attr.start && index <= attr.end) {
        attr.end += length;
      }
    }
  }

  /// Toggles an attribute for the current selection.
  void toggleAttribute(AttributeType type) {
    if (selection.isCollapsed) {
      if (_activeToggles.containsKey(type)) {
        _activeToggles.remove(type);
      } else {
        _activeToggles[type] = null;
      }
      notifyListeners();
      return;
    }

    final oldAttrs = attributes.map((a) => a.copy()).toList();
    final oldSelection = selection;

    final int start = selection.start;
    final int end = selection.end;

    final bool hasAttribute = attributes.any(
      (attr) => attr.type == type && attr.start <= start && attr.end >= end,
    );

    if (hasAttribute) {
      final List<TextAttribute> newAttrs = [];
      for (final attr in attributes) {
        if (attr.type == type && attr.start <= start && attr.end >= end) {
          if (attr.start < start) {
            newAttrs.add(TextAttribute(start: attr.start, end: start, type: type, value: attr.value));
          }
          if (attr.end > end) {
            newAttrs.add(TextAttribute(start: end, end: attr.end, type: type, value: attr.value));
          }
        } else {
          newAttrs.add(attr);
        }
      }
      attributes = newAttrs;
      _activeToggles.remove(type);
    } else {
      attributes.add(TextAttribute(start: start, end: end, type: type));
      _activeToggles[type] = null;
    }

    _optimizeAttributes(type);
    _attributesRevision++;

    _recordDelta(
      oldAttrs: oldAttrs,
      oldSelection: oldSelection,
      newSelection: selection,
    );
    notifyListeners();
  }

  /// Inserts rich text at the current cursor position.
  void insertRichText(String insertedText, List<TextAttribute> incomingAttributes) {
    final String oldText = text;
    final TextSelection oldSelection = selection;
    final oldAttrs = attributes.map((a) => a.copy()).toList();

    final int start = oldSelection.start;
    final int end = oldSelection.end;

    final String newText = oldText.replaceRange(start, end, insertedText);

    if (end > start) {
      _shiftForDeletion(start, end);
    }
    if (insertedText.isNotEmpty) {
      _shiftForInsertion(start, insertedText.length);

      for (final attr in incomingAttributes) {
        attributes.add(
          TextAttribute(
            start: start + attr.start,
            end: start + attr.end,
            type: attr.type,
            value: attr.value,
          ),
        );
      }
    }

    _isUndoingOrRedoing = true;
    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insertedText.length),
    );
    _lastText = newText;
    _isUndoingOrRedoing = false;

    _optimizeAttributes();
    _attributesRevision++;

    _recordDelta(
      oldText: oldText,
      newText: newText,
      oldAttrs: oldAttrs,
      oldSelection: oldSelection,
      newSelection: selection,
    );

    notifyListeners();
  }

  /// Serializes the attributes to JSON-compatible data.
  List<Map<String, dynamic>> serializeAttributes() {
    return attributes.map((a) => a.toJson()).toList();
  }

  /// Loads attributes from JSON-compatible data.
  void deserializeAttributes(List<dynamic> jsonList) {
    attributes = jsonList.map((j) => TextAttribute.fromJson(j as Map<String, dynamic>)).toList();
    _optimizeAttributes();
    _attributesRevision++;
    notifyListeners();
  }

  /// Converts the current state to a [NoteDocument].
  NoteDocument toDocument() {
    return NoteDocument(
      text: text,
      attributes: attributes.map((a) => a.copy()).toList(),
    );
  }

  /// Loads state from a [NoteDocument].
  void fromDocument(NoteDocument doc) {
    _isUndoingOrRedoing = true;
    value = TextEditingValue(
      text: doc.text,
      selection: const TextSelection.collapsed(offset: 0),
    );
    attributes = doc.attributes.map((a) => a.copy()).toList();
    _lastText = doc.text;
    _optimizeAttributes();
    _attributesRevision++;
    _undoStack.clear();
    _redoStack.clear();
    _isUndoingOrRedoing = false;
    notifyListeners();
  }

  /// Removes all formatting from the current selection.
  void clearFormatting() {
    if (selection.isCollapsed) return;

    final oldAttrs = attributes.map((a) => a.copy()).toList();
    final oldSelection = selection;

    final int start = selection.start;
    final int end = selection.end;

    final List<TextAttribute> nextAttrs = [];
    for (final attr in attributes) {
      if (attr.end <= start || attr.start >= end) {
        nextAttrs.add(attr);
      } else {
        if (attr.start < start) {
          nextAttrs.add(
            TextAttribute(start: attr.start, end: start, type: attr.type, value: attr.value),
          );
        }
        if (attr.end > end) {
          nextAttrs.add(TextAttribute(start: end, end: attr.end, type: attr.type, value: attr.value));
        }
      }
    }
    attributes = nextAttrs;
    _optimizeAttributes();
    _activeToggles.clear();
    _attributesRevision++;

    _recordDelta(
      oldAttrs: oldAttrs,
      oldSelection: oldSelection,
      newSelection: selection,
    );
    notifyListeners();
  }

  /// Sets a specific attribute (e.g., color, header) for the current selection.
  void setAttribute(AttributeType type, dynamic value) {
    int start = selection.start;
    int end = selection.end;
    final bool isHeader = type == AttributeType.header;

    if (isHeader && start >= 0) {
      final bounds = _getParagraphBounds(selection);
      start = bounds.start;
      end = bounds.end;
    }

    if (selection.isCollapsed && !isHeader) {
      _activeToggles.remove(type);
      if (value != null) _activeToggles[type] = value;
      notifyListeners();
      return;
    }

    if (start == end && selection.isCollapsed) {
      _activeToggles.remove(type);
      if (value != null) _activeToggles[type] = value;
      notifyListeners();
      return;
    }

    final oldAttrs = attributes.map((a) => a.copy()).toList();
    final oldSelection = selection;

    attributes.removeWhere((attr) => attr.type == type && attr.end > start && attr.start < end);

    if (value != null) {
      attributes.add(TextAttribute(start: start, end: end, type: type, value: value));
      _activeToggles[type] = value;
    } else {
      _activeToggles.remove(type);
    }

    _optimizeAttributes(type);
    _attributesRevision++;

    _recordDelta(
      oldAttrs: oldAttrs,
      oldSelection: oldSelection,
      newSelection: selection,
    );
    notifyListeners();
  }

  void _clampAttributes() {
    final int len = text.length;
    for (int i = attributes.length - 1; i >= 0; i--) {
      final attr = attributes[i];
      attr.start = clampInt(attr.start, 0, len);
      attr.end = clampInt(attr.end, 0, len);
      if (attr.start >= attr.end) {
        attributes.removeAt(i);
      }
    }
  }

  TextRange _getParagraphBounds(TextSelection sel) {
    if (text.isEmpty) return const TextRange(start: 0, end: 0);

    final int start = sel.start;
    final int end = sel.end;

    int pStart = start <= 0 ? -1 : text.lastIndexOf('\n', start - 1);
    pStart = pStart == -1 ? 0 : pStart + 1;

    int pEnd = text.indexOf('\n', end);
    pEnd = pEnd == -1 ? text.length : pEnd;

    return TextRange(start: pStart, end: pEnd);
  }

  void _optimizeAttributes([AttributeType? targetType]) {
    _clampAttributes();
    final List<AttributeType> typesToOptimize = targetType != null ? [targetType] : AttributeType.values;

    for (final type in typesToOptimize) {
      final typeAttrs = attributes.where((attr) => attr.type == type).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

      if (typeAttrs.isEmpty) continue;

      final List<TextAttribute> merged = [];
      for (final current in typeAttrs) {
        if (merged.isEmpty) {
          merged.add(current);
          continue;
        }

        final last = merged.last;
        if (current.start <= last.end && current.value == last.value) {
          if (current.end > last.end) last.end = current.end;
        } else {
          merged.add(current);
        }
      }

      attributes.removeWhere((attr) => attr.type == type);
      attributes.addAll(merged);
    }

    attributes.sort((a, b) {
      final int cmp = a.start.compareTo(b.start);
      if (cmp != 0) return cmp;
      return a.end.compareTo(b.end);
    });
  }

  // buildTextSpan cache
  TextSpan? _cachedSpan;
  String? _cachedText;
  int? _cachedRevision;
  TextStyle? _cachedStyle;
  TextRange? _cachedComposing;
  bool? _cachedWithComposing;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final String currentText = text;
    final TextRange composing = value.composing;

    if (_cachedSpan != null &&
        _cachedText == currentText &&
        _cachedRevision == _attributesRevision &&
        _cachedStyle == style &&
        _cachedComposing == composing &&
        _cachedWithComposing == withComposing) {
      return _cachedSpan!;
    }

    final TextSpan span = _buildTextSpan(currentText, style, withComposing, composing);

    _cachedSpan = span;
    _cachedText = currentText;
    _cachedRevision = _attributesRevision;
    _cachedStyle = style;
    _cachedComposing = composing;
    _cachedWithComposing = withComposing;
    return span;
  }

  TextSpan _buildTextSpan(
    String currentText,
    TextStyle? style,
    bool withComposing,
    TextRange composing,
  ) {
    if (currentText.isEmpty) {
      return TextSpan(text: currentText, style: style);
    }

    final int length = currentText.length;
    final bool hasComposing = withComposing && composing.isValid && composing.end > composing.start;

    if (attributes.isEmpty && !hasComposing) {
      return TextSpan(text: currentText, style: style);
    }

    final List<_StyleEvent> events = [];
    for (final attr in attributes) {
      final int start = clampInt(attr.start, 0, length);
      final int end = clampInt(attr.end, 0, length);
      if (end <= start) continue;
      events.add(_StyleEvent(offset: start, type: attr.type, isStart: true, value: attr.value));
      events.add(_StyleEvent(offset: end, type: attr.type, isStart: false, value: attr.value));
    }
    if (hasComposing) {
      final int cs = clampInt(composing.start, 0, length);
      final int ce = clampInt(composing.end, 0, length);
      if (ce > cs) {
        events.add(_StyleEvent(offset: cs, type: null, isStart: true));
        events.add(_StyleEvent(offset: ce, type: null, isStart: false));
      }
    }

    if (events.isEmpty) {
      return TextSpan(text: currentText, style: style);
    }

    events.sort((a, b) {
      final int cmp = a.offset.compareTo(b.offset);
      if (cmp != 0) return cmp;
      return (a.isStart ? 1 : 0) - (b.isStart ? 1 : 0);
    });

    final List<TextSpan> children = [];
    int currentPos = 0;

    final List<List<dynamic>> activeStates = List.generate(AttributeType.values.length, (_) => []);
    int activeComposing = 0;

    int eventIdx = 0;
    while (currentPos < length) {
      while (eventIdx < events.length && events[eventIdx].offset <= currentPos) {
        final event = events[eventIdx];
        if (event.type == null) {
          activeComposing += event.isStart ? 1 : -1;
        } else {
          final int typeIdx = event.type!.index;
          if (event.isStart) {
            activeStates[typeIdx].add(event.value);
          } else {
            activeStates[typeIdx].remove(event.value);
          }
        }
        eventIdx++;
      }

      final int nextPos = eventIdx < events.length
          ? clampInt(events[eventIdx].offset, 0, length)
          : length;

      if (nextPos > currentPos) {
        final String segmentText = currentText.substring(currentPos, nextPos);

        final bool isBold = activeStates[AttributeType.bold.index].isNotEmpty;
        final bool isItalic = activeStates[AttributeType.italic.index].isNotEmpty;
        final bool isUnderline = activeStates[AttributeType.underline.index].isNotEmpty;
        final bool isStrike = activeStates[AttributeType.strikethrough.index].isNotEmpty;
        final bool isHighlighted = activeStates[AttributeType.highlight.index].isNotEmpty;
        final bool isCode = activeStates[AttributeType.code.index].isNotEmpty;
        final bool isComposing = activeComposing > 0;

        final List<dynamic> headerStack = activeStates[AttributeType.header.index];
        final dynamic headerVal = headerStack.isEmpty ? null : headerStack.last;

        final List<dynamic> colorStack = activeStates[AttributeType.color.index];
        final dynamic colorVal = colorStack.isEmpty ? null : colorStack.last;

        final List<dynamic> sizeStack = activeStates[AttributeType.size.index];
        final dynamic sizeVal = sizeStack.isEmpty ? null : sizeStack.last;

        final List<dynamic> linkStack = activeStates[AttributeType.link.index];
        final dynamic linkVal = linkStack.isEmpty ? null : linkStack.last;

        TextStyle segmentStyle = style ?? const TextStyle();

        final List<TextDecoration> decorations = [];
        if (isUnderline || isComposing || linkVal != null) decorations.add(TextDecoration.underline);
        if (isStrike) decorations.add(TextDecoration.lineThrough);

        double finalFontSize = style?.fontSize ?? config.fontSize;
        FontWeight finalFontWeight = isBold ? FontWeight.bold : (style?.fontWeight ?? FontWeight.normal);

        if (headerVal == 'h1') {
          finalFontSize = 28.0;
          finalFontWeight = FontWeight.bold;
        } else if (headerVal == 'h2') {
          finalFontSize = 22.0;
          finalFontWeight = FontWeight.bold;
        } else if (sizeVal != null) {
          finalFontSize = (sizeVal as num).toDouble();
        }

        final double effectiveHeight = config.lineHeight / finalFontSize;

        segmentStyle = segmentStyle.copyWith(
          fontSize: finalFontSize,
          fontWeight: finalFontWeight,
          height: effectiveHeight,
          fontStyle: isItalic ? FontStyle.italic : (style?.fontStyle ?? FontStyle.normal),
          color: colorVal is Color ? colorVal : (linkVal != null ? config.linkColor : style?.color),
          backgroundColor: isHighlighted
              ? config.highlightColor
              : (isCode ? config.codeBackgroundColor : style?.backgroundColor),
          decoration: decorations.isEmpty ? TextDecoration.none : TextDecoration.combine(decorations),
          fontFamily: isCode ? 'monospace' : style?.fontFamily,
        );

        children.add(TextSpan(text: segmentText, style: segmentStyle));
      }
      currentPos = nextPos;
    }

    return TextSpan(style: style, children: children);
  }

  /// Whether the given attribute is active at the current cursor or selection.
  bool isAttributeActive(AttributeType type) {
    final int start = selection.start;
    final int end = selection.end;

    if (selection.isCollapsed) {
      return _activeToggles.containsKey(type) || _isStyleAt(start, type);
    }

    int i = _findUpperBound(start);
    while (--i >= 0) {
      final attr = attributes[i];
      if (attr.type == type && attr.start <= start && attr.end >= end) {
        return true;
      }
    }
    return false;
  }

  bool _isStyleAt(int pos, AttributeType type) {
    if (pos < 0 || pos >= text.length) return false;

    int i = _findUpperBound(pos);
    while (--i >= 0) {
      final attr = attributes[i];
      if (attr.type == type && pos >= attr.start && pos < attr.end) {
        return true;
      }
    }
    return false;
  }

  dynamic _getValueAt(int pos, AttributeType type) {
    if (pos < 0 || pos >= text.length) return null;

    int i = _findUpperBound(pos);
    while (--i >= 0) {
      final attr = attributes[i];
      if (attr.type == type && pos >= attr.start && pos < attr.end) {
        return attr.value;
      }
    }
    return null;
  }

  int _findUpperBound(int pos) {
    int low = 0;
    int high = attributes.length;
    while (low < high) {
      final int mid = (low + high) ~/ 2;
      if (attributes[mid].start <= pos) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }
}
