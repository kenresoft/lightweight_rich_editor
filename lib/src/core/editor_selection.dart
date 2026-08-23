import '../utils/clamp_int.dart';

/// A framework-agnostic text selection: a `base`/`extent` offset pair.
///
/// Mirrors the shape of Flutter's `TextSelection` (base/extent rather
/// than a pre-normalized start/end) but lives outside `dart:ui`, so
/// [EditingEngine] and everything below it stays testable without
/// widget bindings.
class EditorSelection {
  /// Where the selection gesture started; equal to [extentOffset] for a
  /// collapsed (caret) selection.
  final int baseOffset;

  /// Where the selection gesture ended — i.e. where the caret is.
  final int extentOffset;

  const EditorSelection({required this.baseOffset, required this.extentOffset});

  const EditorSelection.collapsed(int offset)
      : baseOffset = offset,
        extentOffset = offset;

  /// The lower of [baseOffset]/[extentOffset] — use this and [end] for
  /// any operation that doesn't care about selection direction (which is
  /// almost every editing operation).
  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;

  /// The higher of [baseOffset]/[extentOffset].
  int get end => baseOffset < extentOffset ? extentOffset : baseOffset;

  int get length => end - start;

  bool get isCollapsed => baseOffset == extentOffset;

  EditorSelection clampTo(int length) => EditorSelection(
    baseOffset: clampInt(baseOffset, 0, length),
    extentOffset: clampInt(extentOffset, 0, length),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
          (other is EditorSelection &&
              other.baseOffset == baseOffset &&
              other.extentOffset == extentOffset);

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);

  @override
  String toString() => isCollapsed
      ? 'EditorSelection.collapsed($start)'
      : 'EditorSelection([$start, $end))';
}