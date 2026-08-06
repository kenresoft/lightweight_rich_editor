import 'attribute_type.dart';

/// An immutable formatting span applied to the half-open range
/// `[start, end)` of a document's text.
///
/// Every transformation — shifting on edit, splitting at a boundary,
/// merging with a neighbor — produces a *new* [TextAttribute] rather than
/// mutating this one. That immutability is deliberate: it's what makes
/// value equality meaningful, which in turn is what lets [HistoryManager]
/// (Phase 3) diff "before" and "after" span lists correctly. The previous
/// controller mutated spans in place and relied on identity equality for
/// undo diffing, which silently recorded every span as changed on every
/// edit — see the accompanying analysis.
///
/// `value` is deliberately framework-agnostic: colors are stored as ARGB
/// `int`s and links as `String` URLs rather than `dart:ui` types, so this
/// model layer has zero Flutter dependency and can be unit-tested without
/// a widget binding. Converting `value` into a `Color`/`TextStyle` is the
/// Renderer's job (Phase 4), not this class's.
class TextAttribute {
  /// Inclusive start offset, in UTF-16 code units.
  final int start;

  /// Exclusive end offset, in UTF-16 code units.
  final int end;

  final AttributeType type;

  /// The attribute's payload. `null` for toggle attributes
  /// ([AttributeType.isToggle]); for value attributes this is an ARGB
  /// `int` (color), a `num` (size), a `String` (link, or header level
  /// like `'h1'`/`'h2'`).
  final Object? value;

  const TextAttribute({
    required this.start,
    required this.end,
    required this.type,
    this.value,
  }) : assert(end >= start, 'TextAttribute.end must not be before start');

  int get length => end - start;

  bool get isCollapsed => start == end;

  /// True if this span shares any character with `[rangeStart, rangeEnd)`.
  bool intersects(int rangeStart, int rangeEnd) =>
      start < rangeEnd && end > rangeStart;

  /// True if this span fully covers `[rangeStart, rangeEnd)`.
  bool covers(int rangeStart, int rangeEnd) =>
      start <= rangeStart && end >= rangeEnd;

  /// True if `position` falls inside this span.
  bool contains(int position) => position >= start && position < end;

  TextAttribute copyWith({
    int? start,
    int? end,
    AttributeType? type,
    Object? value,
  }) {
    return TextAttribute(
      start: start ?? this.start,
      end: end ?? this.end,
      type: type ?? this.type,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'type': type.name,
    if (value != null) 'value': value,
  };

  factory TextAttribute.fromJson(Map<String, dynamic> json) {
    return TextAttribute(
      start: json['start'] as int,
      end: json['end'] as int,
      type: AttributeType.values.byName(json['type'] as String),
      value: json['value'],
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TextAttribute &&
        other.start == start &&
        other.end == end &&
        other.type == type &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(start, end, type, value);

  @override
  String toString() =>
      'TextAttribute($type, [$start, $end)${value != null ? ', value: $value' : ''})';
}