import '../commands/command_dispatcher.dart';
import '../commands/composite_command.dart';
import '../commands/replace_range_command.dart';
import '../core/editor_document.dart';
import '../core/editor_selection.dart';

/// A single search hit: `[start, end)` in the document.
class SearchMatch {
  final int start;
  final int end;

  const SearchMatch({required this.start, required this.end});

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is SearchMatch && other.start == start && other.end == end);

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'SearchMatch([$start, $end))';
}

/// Find and replace over an [EditorDocument].
///
/// Results are a snapshot, not a live view — they don't automatically
/// track edits made after [search] runs. Call [refresh] after an edit
/// if you need [matches] to stay accurate; [replaceCurrent] and
/// [replaceAll] already do this for you.
class SearchIndex {
  final EditorDocument document;
  final CommandDispatcher commands;

  SearchIndex({required this.document, required this.commands});

  String _query = '';
  bool _caseSensitive = false;
  bool _wholeWord = false;
  List<SearchMatch> _matches = const [];
  int _currentIndex = -1;

  // Cached so repeated reads return the same `identical` instance until
  // `_matches` is reassigned, letting callers cheaply detect changes.
  List<SearchMatch>? _matchesView;

  String get query => _query;

  List<SearchMatch> get matches => _matchesView ??= List.unmodifiable(_matches);

  /// [matches] converted to [EditorSelection]s, for hosts doing their
  /// own highlighting/navigation instead of using [FindReplaceBar].
  List<EditorSelection> get matchSelections =>
      matches.map((m) => EditorSelection(baseOffset: m.start, extentOffset: m.end)).toList(growable: false);

  int get matchCount => _matches.length;

  /// Index into [matches] of the currently-selected result, or `-1` if
  /// there are no matches (or nothing has been searched yet).
  int get currentIndex => _currentIndex;

  SearchMatch? get currentMatch =>
      (_currentIndex >= 0 && _currentIndex < _matches.length) ? _matches[_currentIndex] : null;

  /// Searches for `query` and selects the first match, if any. An empty
  /// `query` clears the search (same as [clear]).
  void search(String query, {bool caseSensitive = false, bool wholeWord = false}) {
    _query = query;
    _caseSensitive = caseSensitive;
    _wholeWord = wholeWord;
    _setMatches(query.isEmpty ? const [] : _findAll(query, caseSensitive: caseSensitive, wholeWord: wholeWord));
    _currentIndex = _matches.isEmpty ? -1 : 0;
  }

  void _setMatches(List<SearchMatch> value) {
    _matches = value;
    _matchesView = null;
  }

  /// Re-runs the last search against the document's current text.
  /// No-op if nothing has been searched yet.
  void refresh() {
    if (_query.isEmpty) return;
    search(_query, caseSensitive: _caseSensitive, wholeWord: _wholeWord);
  }

  void clear() {
    _query = '';
    _setMatches(const []);
    _currentIndex = -1;
  }

  /// Moves to the next match, wrapping around to the first after the
  /// last. Returns the new current match, or `null` if there are none.
  SearchMatch? next() {
    if (_matches.isEmpty) return null;
    _currentIndex = (_currentIndex + 1) % _matches.length;
    return currentMatch;
  }

  /// Moves to the previous match, wrapping around to the last before
  /// the first. Returns the new current match, or `null` if there are
  /// none.
  SearchMatch? previous() {
    if (_matches.isEmpty) return null;
    _currentIndex = (_currentIndex - 1 + _matches.length) % _matches.length;
    return currentMatch;
  }

  /// Replaces [currentMatch] with `replacement`, as one undoable edit,
  /// then [refresh]es (resetting [currentIndex] to the first remaining
  /// match). Returns the resulting caret selection, or `null` if there's
  /// no current match.
  EditorSelection? replaceCurrent(String replacement) {
    final match = currentMatch;
    if (match == null) return null;

    final result = commands.dispatch(ReplaceRangeCommand(
      start: match.start,
      end: match.end,
      text: replacement,
      attributesForInsertion: const {},
    ));
    refresh();
    return result;
  }

  /// Replaces every current match with `replacement`, as a single
  /// undoable edit, and clears the search afterward. Returns the number
  /// of replacements made.
  int replaceAll(String replacement) {
    if (_matches.isEmpty) return 0;
    final count = _matches.length;

    // Back to front, so each match's offset stays valid as later ones are edited.
    final subCommands = _matches.reversed
        .map((match) => ReplaceRangeCommand(
      start: match.start,
      end: match.end,
      text: replacement,
      attributesForInsertion: const {},
    ))
        .toList();
    commands.dispatch(CompositeCommand(subCommands));

    clear();
    return count;
  }

  List<SearchMatch> _findAll(String query, {required bool caseSensitive, required bool wholeWord}) {
    final haystack = caseSensitive ? document.text : document.text.toLowerCase();
    final needle = caseSensitive ? query : query.toLowerCase();
    if (needle.isEmpty) return const [];

    final matches = <SearchMatch>[];
    var searchFrom = 0;
    while (true) {
      final index = haystack.indexOf(needle, searchFrom);
      if (index == -1) break;
      final end = index + needle.length;
      if (!wholeWord || _isWholeWordMatch(haystack, index, end)) {
        matches.add(SearchMatch(start: index, end: end));
      }
      searchFrom = end; // non-overlapping: resume after this match
    }
    return matches;
  }

  bool _isWholeWordMatch(String haystack, int start, int end) {
    bool isWordChar(String char) => RegExp(r'[A-Za-z0-9_]').hasMatch(char);
    if (start > 0 && isWordChar(haystack[start - 1])) return false;
    if (end < haystack.length && isWordChar(haystack[end])) return false;
    return true;
  }
}