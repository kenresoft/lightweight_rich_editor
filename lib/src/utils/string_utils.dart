/// Clamps an [int] to `[min, max]`.
int clampInt(int value, int min, int max) {
  if (value < min) return min;
  if (value > max) return max;
  return value;
}

/// Longest run where `a[0..k)` equals `b[0..k)`, capped at [maxLen].
int commonPrefixLength(String a, String b, int maxLen) {
  int i = 0;
  while (i < maxLen && a[i] == b[i]) {
    i++;
  }
  return i;
}

/// Longest run where the tail of `a` equals the tail of `b`, capped at [maxLen].
int commonSuffixLength(String a, String b, int maxLen) {
  int i = 0;
  while (i < maxLen && a[a.length - 1 - i] == b[b.length - 1 - i]) {
    i++;
  }
  return i;
}
