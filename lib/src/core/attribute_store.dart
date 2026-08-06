import '../models/attribute_type.dart';
import '../models/text_attribute.dart';
import '../utils/clamp_int.dart';

/// Owns every [TextAttribute] span for a document and every operation
/// that keeps them consistent as the underlying text changes.
///
/// Nothing outside this class should hold a mutable reference to spans or
/// reimplement span math — the old controller manipulated
/// `List<TextAttribute>` directly in half a dozen places (toggle, set,
/// clear, undo, redo, sync-on-edit), which is exactly how the identity-
/// equality undo bug and the scattered clamping logic happened. Every one
/// of those call sites becomes a method here instead.
///
/// [AttributeStore] does not know about the document's text or selection
/// — it only knows offsets. Callers (the `EditingEngine`) are
/// responsible for calling [shiftForInsertion] / [shiftForDeletion] in
/// step with the corresponding [TextBuffer] edit, and for calling
/// [clampTo] after any edit that isn't routed through those two methods
/// (e.g. a full document reset).
class AttributeStore {
  final List<TextAttribute> _spans = [];
  bool _sorted = true;

  /// Bumped on every mutation. The `Renderer` (Phase 4) uses this as a
  /// cheap cache-invalidation key instead of diffing the span list on
  /// every rebuild — same role the old controller's `_attributesRevision`
  /// played, just owned by the class whose state it actually tracks.
  int _revision = 0;

  int get revision => _revision;

  AttributeStore();

  /// Builds a store from existing spans. Does not clamp or optimize —
  /// call [clampTo] and [optimize] afterward if the input isn't already
  /// known-clean (e.g. spans just loaded from storage).
  factory AttributeStore.fromSpans(Iterable<TextAttribute> spans) {
    final store = AttributeStore();
    store._spans.addAll(spans.where((s) => !s.isCollapsed));
    store._sorted = false;
    return store;
  }

  /// Every span, always returned sorted by start offset. Read-only —
  /// mutate through the methods below, not this list.
  List<TextAttribute> get spans {
    _sort();
    return List.unmodifiable(_spans);
  }

  int get length => _spans.length;

  bool get isEmpty => _spans.isEmpty;

  void _sort() {
    if (_sorted) return;
    _spans.sort((a, b) {
      final cmp = a.start.compareTo(b.start);
      return cmp != 0 ? cmp : a.end.compareTo(b.end);
    });
    _sorted = true;
  }

  // ---------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------

  /// Adds a span. Zero-width spans are silently dropped. Does not merge
  /// neighbors — call [optimize] after a batch of inserts.
  void insert(TextAttribute attribute) {
    if (attribute.isCollapsed) return;
    _spans.add(attribute);
    _sorted = false;
    _revision++;
  }

  /// Removes every span equal (by value) to `attribute`.
  void remove(TextAttribute attribute) {
    if (_spans.remove(attribute)) _revision++;
  }

  /// Removes every span for which `test` returns true.
  void removeWhere(bool Function(TextAttribute) test) {
    final before = _spans.length;
    _spans.removeWhere(test);
    if (_spans.length != before) _revision++;
  }

  /// Replaces the first span equal to `oldAttribute` with `newAttribute`.
  /// No-op if `oldAttribute` isn't present.
  void replace(TextAttribute oldAttribute, TextAttribute newAttribute) {
    final index = _spans.indexWhere((s) => s == oldAttribute);
    if (index == -1) return;
    if (newAttribute.isCollapsed) {
      _spans.removeAt(index);
    } else {
      _spans[index] = newAttribute;
      _sorted = false;
    }
    _revision++;
  }

  void clear() {
    if (_spans.isEmpty) return;
    _spans.clear();
    _sorted = true;
    _revision++;
  }

  // ---------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------

  /// Every span (optionally filtered to `type`) active at `position`.
  List<TextAttribute> findAt(int position, {AttributeType? type}) {
    return _spans
        .where((s) => s.contains(position) && (type == null || s.type == type))
        .toList(growable: false);
  }

  /// Every span (optionally filtered to `type`) overlapping
  /// `[start, end)` at all.
  List<TextAttribute> findIntersecting(int start, int end, {AttributeType? type}) {
    return _spans
        .where((s) => s.intersects(start, end) && (type == null || s.type == type))
        .toList(growable: false);
  }

  /// Every span (optionally filtered to `type`) fully contained within
  /// `[start, end]`.
  List<TextAttribute> findRange(int start, int end, {AttributeType? type}) {
    return _spans
        .where((s) => s.start >= start && s.end <= end && (type == null || s.type == type))
        .toList(growable: false);
  }

  /// True if some span of `type` fully covers `[start, end)` — the
  /// question "is the whole selection bold?" reduces to this.
  bool coversRange(int start, int end, AttributeType type) {
    return _spans.any((s) => s.type == type && s.covers(start, end));
  }

  // ---------------------------------------------------------------------
  // Structural edits
  // ---------------------------------------------------------------------

  /// Splits every span (optionally filtered to `type`) that straddles
  /// `position` into two spans meeting exactly at `position`. The set of
  /// formatted characters is unchanged — this only affects span
  /// boundaries, which matters when a caller needs to attach independent
  /// metadata to each side of a cursor position.
  void split(int position, {AttributeType? type}) {
    final toSplit = _spans
        .where((s) =>
    (type == null || s.type == type) && s.start < position && s.end > position)
        .toList(growable: false);
    if (toSplit.isEmpty) return;
    for (final span in toSplit) {
      _spans.remove(span);
      _spans.add(span.copyWith(end: position));
      _spans.add(span.copyWith(start: position));
    }
    _sorted = false;
    _revision++;
  }

  /// Removes formatting (optionally filtered to `type`) from
  /// `[start, end)`, trimming boundary spans so text outside the range
  /// keeps its formatting untouched. This is "clear formatting" and the
  /// removal half of "set attribute" from the old controller, unified.
  void clearRange(int start, int end, {AttributeType? type}) {
    final affected = findIntersecting(start, end, type: type);
    if (affected.isEmpty) return;
    for (final span in affected) {
      _spans.remove(span);
      if (span.start < start) {
        _spans.add(span.copyWith(end: start));
      }
      if (span.end > end) {
        _spans.add(span.copyWith(start: end));
      }
    }
    _sorted = false;
    _revision++;
  }

  /// Shifts spans to account for `length` characters inserted at
  /// `index`. Spans starting at or after `index` move forward whole;
  /// a span straddling `index` grows to absorb the insertion (so typing
  /// in the middle of bold text stays bold).
  void shiftForInsertion(int index, int length) {
    if (length <= 0) return;
    for (var i = 0; i < _spans.length; i++) {
      final s = _spans[i];
      if (index <= s.start) {
        _spans[i] = s.copyWith(start: s.start + length, end: s.end + length);
      } else if (index > s.start && index <= s.end) {
        _spans[i] = s.copyWith(end: s.end + length);
      }
    }
    _revision++;
  }

  /// Shifts spans to account for deleting `[start, end)`. Spans entirely
  /// inside the deleted range are dropped; spans straddling either edge
  /// shrink by however much of them was deleted.
  void shiftForDeletion(int start, int end) {
    if (end <= start) return;
    for (var i = _spans.length - 1; i >= 0; i--) {
      final s = _spans[i];

      final removedBefore =
      start < s.start ? (end < s.start ? end : s.start) - start : 0;

      final overlapStart = start > s.start ? start : s.start;
      final overlapEnd = end < s.end ? end : s.end;
      final removedInside = overlapStart < overlapEnd ? overlapEnd - overlapStart : 0;

      final newStart = s.start - removedBefore;
      final newEnd = s.end - removedBefore - removedInside;

      if (newStart >= newEnd) {
        _spans.removeAt(i);
      } else {
        _spans[i] = s.copyWith(start: newStart, end: newEnd);
      }
    }
    _revision++;
  }

  /// Clamps every span to `[0, textLength]`, dropping any that collapse
  /// to zero width. Call this after any edit that bypasses
  /// [shiftForInsertion]/[shiftForDeletion] — e.g. loading a document,
  /// or applying an undo delta that replaces the text wholesale.
  void clampTo(int textLength) {
    var changed = false;
    for (var i = _spans.length - 1; i >= 0; i--) {
      final s = _spans[i];
      final start = clampInt(s.start, 0, textLength);
      final end = clampInt(s.end, 0, textLength);
      if (start >= end) {
        _spans.removeAt(i);
        changed = true;
      } else if (start != s.start || end != s.end) {
        _spans[i] = s.copyWith(start: start, end: end);
        changed = true;
      }
    }
    if (changed) _revision++;
  }

  /// Merges adjacent or overlapping spans of the same type and value
  /// (optionally restricted to `type`, which is cheaper — pass it
  /// whenever the caller knows which type it just touched, exactly as
  /// the old controller did for single-attribute toggles).
  ///
  /// This is what keeps the span count bounded after repeated edits —
  /// without it, toggling bold on then off a thousand times would leave
  /// a thousand dead spans behind.
  void optimize({AttributeType? type}) {
    final types = type != null ? [type] : AttributeType.values;
    for (final t in types) {
      final ofType = _spans.where((s) => s.type == t).toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      if (ofType.isEmpty) continue;

      final merged = <TextAttribute>[ofType.first];
      for (final current in ofType.skip(1)) {
        final last = merged.last;
        if (current.start <= last.end && current.value == last.value) {
          if (current.end > last.end) {
            merged[merged.length - 1] = last.copyWith(end: current.end);
          }
        } else {
          merged.add(current);
        }
      }

      _spans.removeWhere((s) => s.type == t);
      _spans.addAll(merged);
    }
    _sorted = false;
    _revision++;
  }

  // ---------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------

  List<Map<String, dynamic>> serialize() => spans.map((s) => s.toJson()).toList(growable: false);

  static AttributeStore deserialize(List<dynamic> json) {
    return AttributeStore.fromSpans(
      json.map((j) => TextAttribute.fromJson(j as Map<String, dynamic>)),
    );
  }
}