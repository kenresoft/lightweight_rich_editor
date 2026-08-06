/// Clamps `value` to `[min, max]` and returns an `int`.
///
/// `num.clamp()` — inherited by `int` — returns `num`, not `int`, even
/// when called with `int` bounds, so `someInt.clamp(0, 10)` doesn't
/// assign to an `int`-typed variable without an explicit cast. This is a
/// well-known Dart pitfall; this function exists purely to avoid
/// littering the codebase with `.clamp(...).toInt()` at every offset
/// calculation, which is most of them.
int clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}