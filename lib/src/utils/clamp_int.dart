/// Clamps `value` to `[min, max]` and returns an `int`.
///
/// Unlike `num.clamp()`, which returns `num` even for `int` inputs, this
/// avoids an explicit cast at every call site.
int clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}