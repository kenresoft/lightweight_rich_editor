import 'dart:ui';
import 'attribute_type.dart';

/// Represents a rich text attribute applied to a specific range of text.
class TextAttribute {
  /// The 0-based start index of the attribute (inclusive).
  int start;

  /// The 0-based end index of the attribute (exclusive).
  int end;

  /// The type of attribute.
  final AttributeType type;

  /// The value associated with the attribute (e.g., [Color] for color, [String] for link).
  final dynamic value;

  /// Creates a [TextAttribute].
  TextAttribute({
    required this.start,
    required this.end,
    required this.type,
    this.value,
  });

  /// Whether this attribute covers the given [index].
  bool contains(int index) => index >= start && index < end;

  /// Creates a copy of this attribute.
  TextAttribute copy() => TextAttribute(
        start: start,
        end: end,
        type: type,
        value: value,
      );

  /// Converts this attribute to a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      's': start,
      'e': end,
      't': type.index,
      if (value != null) 'v': _serializeValue(value),
    };
  }

  /// Creates a [TextAttribute] from a JSON-compatible map.
  static TextAttribute fromJson(Map<String, dynamic> json) {
    return TextAttribute(
      start: json['s'] as int,
      end: json['e'] as int,
      type: AttributeType.values[json['t'] as int],
      value: _deserializeValue(json['v']),
    );
  }

  static dynamic _serializeValue(dynamic val) {
    if (val is Color) return val.toARGB32();
    return val;
  }

  static dynamic _deserializeValue(dynamic val) {
    if (val is int && val > 0xFFFFFF) return Color(val);
    return val;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TextAttribute &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          type == other.type &&
          value == other.value;

  @override
  int get hashCode =>
      start.hashCode ^ end.hashCode ^ type.hashCode ^ value.hashCode;

  @override
  String toString() => 'TextAttribute($type, $start-$end, value: $value)';
}
