# Customising lightweight_rich_editor

The package ships **no fonts, no icons font, no images and no app theme**. Everything visual is a value you
pass in, so the editor can take on the look of whatever app it lives in. This guide is the map: what you can
change, where, and how to handle the situations that are easy to get wrong.

Contents

1. [What you can change, and where](#1-what-you-can-change-and-where)
2. [Fonts and the ruled grid](#2-fonts-and-the-ruled-grid) (read this before changing a font)
3. [Dark mode and colours](#3-dark-mode-and-colours)
4. [Text scale and accessibility](#4-text-scale-and-accessibility)
5. [Icons and the built-in chrome](#5-icons-and-the-built-in-chrome)
6. [Images](#6-images)
7. [Links, search and context menus](#7-links-search-and-context-menus)
8. [Testing your configuration](#8-testing-your-configuration)
9. [Troubleshooting](#9-troubleshooting)

---

## 1. What you can change, and where

| You want to change | Where | Notes |
|---|---|---|
| Body font, sizes, colours of text | `RichTextRenderTheme` (`controller.renderer.theme`) | `bodyFontFamily`, `baseFontSize`, `textColor`, `h1FontSize`..`h3FontSize`, `codeFontFamily` |
| Row height (line spacing) | `RichTextRenderTheme.lineHeight` | One ruled row = one `lineHeight` |
| How strict "fits one row" is | `rowFill`, `headerRowFill` | See section 2 |
| Link, highlight, search-match, list-marker colours | `RichTextRenderTheme` | `linkColor`, `highlightColor`, `matchHighlightColor`, `otherMatchesHighlightColor`, `listMarkerColor` |
| Code block look | `RichTextRenderTheme` (`codeBackgroundColor`, `codeSyntax`) and `RichEditorStyle` (`codeBlockColor`, `codeBlockLabelColor`) | Pass `CodeSyntaxColors.dark` on a dark page |
| Page: padding, ruled lines, margin line | `RichEditorStyle` | `paddingTop/Right/Bottom/Left...`, `ruledLineColor`, `marginLineColor`, `marginLineX` |
| Ruled-line style | `RichTextEditor.lineStyle` | solid, dashed, grid, dots, none |
| Margin line on/off | `RichTextEditor.showMargin` | |
| Placeholder, read-only, autofocus | `RichTextEditor` parameters | `placeholder`, `readOnly`, `autofocus` |
| Text direction / alignment of the whole document | `RichTextEditor.textDirection`, `textAlign` | Per-paragraph alignment is stored but not rendered (see `EXTENSION_POINTS.md`) |
| Input rules (length limit...) | `RichTextEditor.inputFormatters` | Any `TextInputFormatter` |
| Formatting actions | `RichEditorController` methods | `toggleBold`, `setHeader`, `toggleBulletList`, `setLink`, `toggleCodeBlock`... |

Two ways to apply a theme:

```dart
// At creation
final controller = RichEditorController(
  text: 'Hello',
  theme: const RichTextRenderTheme(baseFontSize: 17, lineHeight: 30),
);

// At runtime (a dark-mode switch, a settings change). No need to rebuild the controller.
controller.renderer.theme = controller.renderer.theme.copyWith(textColor: Colors.white);
```

Assigning an equal theme is cheap (the renderer compares the whole value before clearing its caches), so it is
safe to assign from `build`.

---

## 2. Fonts and the ruled grid

The editor draws ruled lines and expects the text to sit on them. That makes the **font's vertical metrics**
(how tall a line of it is) matter more than in an ordinary text field.

### How rows work

- One ruled row is `lineHeight` pixels (scaled by your text scale).
- Body text and inline sizes are shrunk, if needed, so a line fits one row.
- A **paragraph heading (H1 to H3) is never shrunk.** If its natural height does not fit one row, it takes
  **two (or more) whole rows**, and its text then floats between the rules instead of sitting on one.
- `rowFill` and `headerRowFill` are the fraction of a row a glyph run may use before it stops counting as
  fitting (defaults 0.9 and 0.98). Raising them lets a taller font fit; it also leaves less clearance.

### The common trap: changing the font changes which headings fit

Two fonts at the same point size have different line heights. A heading size that fits one row in one font can
need two in another. (Real case: with the default theme, an H1 of 24 fit one 30 px row in Roboto, but needed
two in Plus Jakarta Sans; 23 was the largest that fitted.)

When you change `bodyFontFamily` (or the app's font), **re-check H1 to H3**:

1. Pick the row height you want (`lineHeight`).
2. Find the largest heading sizes that still give exactly one row (recipe below).
3. Set `h1FontSize`, `h2FontSize`, `h3FontSize` a little under those, so there is margin at other text scales.
4. Keep a clear step between levels and above `baseFontSize` (for example 22 / 20 / 18 over a 16 body).

### Recipe: find the largest heading that fits one row

```dart
// Inside a widget test or after the editor has been laid out once:
final metrics = controller.renderer.activeRowMetrics!;
for (var size = 28.0; size >= 14; size -= 1) {
  final rows = metrics.rowsForParagraph(size, FontWeight.bold);
  debugPrint('H size $size -> $rows row(s)');
}
// Or just ask: metrics.allHeadersFitOneRow
```

`rowsForParagraph(fontSize, weight)` measures the real font, so the answer is exact for that font. Load the font
before measuring (see section 8).

### Platform font families (`serif`, `monospace`, `cursive`...)

These resolve to whatever the device provides, so they cannot be measured in a unit test. Check them on a
device, with a long heading, and give the heading sizes enough margin. If you offer several fonts, you may keep
a per-font heading scale (a number you multiply into `h1FontSize`..`h3FontSize`).

### Keeping everything on one row

If you want a guarantee that every line is exactly one row (the simplest, most predictable look), choose heading
sizes so `allHeadersFitOneRow` is true for your font at every text scale you support. The editor then also forces
a fixed strut height, so a line that mixes fonts (emoji, CJK, monospace) cannot grow past a row.

---

## 3. Dark mode and colours

Set these together when the brightness changes:

| Field | Light example | Dark example |
|---|---|---|
| `RichTextRenderTheme.textColor` | near-black | near-white |
| `linkColor` | `#1A66D2` (about 4.6:1 on white) | `#8AB4F8` (about 8:1 on dark) |
| `codeBackgroundColor` | `onSurface` at about 7% | the same, on the dark page |
| `codeSyntax` | `CodeSyntaxColors.light` | `CodeSyntaxColors.dark` |
| `listMarkerColor` | mid grey | lighter grey |
| `RichEditorStyle.ruledLineColor` | soft grey, 40-50% alpha | the outline colour at lower alpha |
| `RichEditorStyle.marginLineColor` | soft red | the same hue, lower alpha |

Guidelines that worked well:

- Body text at least 4.5 : 1 against the page; secondary text and links also 4.5 : 1.
- Ruled lines are decoration: about 1.5 to 2 : 1 against the page is enough, and more feels busy.
- Avoid pure black pages with pure white text if you can (harsh). A soft near-black such as `#16181D` is easier on
  the eye, and cards one or two steps lighter read as raised without borders.
- Coloured note backgrounds look best as the colour's hue blended into the page at about 15% strength in dark mode,
  rather than separate fixed swatches.

Colours chosen by users (a text colour or highlight stored in a document) are kept as written. In dark mode a
very dark text colour on a dark page is the user's choice; offer a "reset colour" action if that matters.

---

## 4. Text scale and accessibility

- The editor measures with the `TextScaler` it is given. Scale `lineHeight` and the heading sizes **together** with
  the font size so that what fitted one row at the normal size still fits at a larger one:

  ```dart
  final scale = baseFontSize / 16.0;
  theme = theme.copyWith(
    baseFontSize: baseFontSize,
    lineHeight: (30 * scale).roundToDouble(),
    h1FontSize: 22 * scale,
    h2FontSize: 20 * scale,
    h3FontSize: 18 * scale,
  );
  ```

- If the host app clamps the system text scale (for example 0.85 to 1.4), keep the headings in proportion to the
  row height; they need to fit the row at the largest scale you allow. Test the extremes (section 8).
- Provide semantic labels for any buttons you build around the editor.

---

## 5. Icons and the built-in chrome

The package draws a little chrome of its own. All of it uses Flutter's Material icons and **takes its colour
from the surrounding theme**; it ships no icon font or assets.

| Chrome | What it shows | How to customise |
|---|---|---|
| Format toolbar (`FormatToolbar`) | bold, italic, link, code, size, colour... | Optional. Build your own toolbar from `RichEditorController` methods (table in section 1) for full control of icons and layout. |
| Picture bar (over a selected image) | open, save, replace, remove, smaller, larger | The *behaviour* is yours (`onOpenImage`, `onSaveImage`, `onReplaceImage`, `onImageRemoved`). The bar's glyphs are fixed. |
| Code block chip | language label and copy | Colours via `RichEditorStyle.codeBlockLabelColor`; label text comes from the block. |
| Link bar and link sheet | open, copy, edit, remove | Behaviour via `confirmBeforeOpeningLinks`, `openLinksOnTap`, `onTapLink`; the sheet can be replaced by calling `showLinkEditSheet` yourself or handling `onTapLink`. |

If the built-in glyphs do not match your icon set:

1. For the toolbar: do not use `FormatToolbar`; build your own (a few `IconButton`s calling controller methods and
   asking `controller.isAttributeActive(AttributeType.bold)` and the like for the pressed state).
2. For the picture bar, code chip and link bar: these are small, internal widgets. The supported options are to
   restyle them through the surrounding `IconTheme`/`Theme`, or to maintain a fork of those few widgets
   (`lib/src/widgets/rich_text_editor.dart`, `link_preview_bar.dart`). The package deliberately does not add
   icon-builder hooks, so that its API stays small.

A host app that uses its own icon set should keep the editor's remaining Material glyphs visually quiet: small,
inheriting the text colour, and not competing with the app's chrome.

---

## 6. Images

Pictures are stored **by id**, not inside the document text. You supply the storage:

```dart
class MyImageStore extends RichImageStore {
  @override
  Future<String> save(Uint8List bytes) async => /* store the bytes, return an id (letters, digits, _ or -, up to 64) */;
  @override
  Future<Uint8List?> load(String id) async => /* the bytes, or null if gone */;
  @override
  Future<void> delete(String id) async {/* optional: forget a picture */}
  // Optional: rememberSource / sourceOf, to offer the original web address again when a picture is replaced.
}
controller.imageStore = MyImageStore();
```

- Use `prepareImage` before storing, to bound size and dimensions.
- Keep ids stable. A document that refers to an id you no longer have shows a "missing picture" placeholder; it
  never crashes.
- Do not copy picture files into things that must stay small (templates, previews). Refer to ids and decide your
  own lifetime rules.

---

## 7. Links, search and context menus

- **Links:** the controller opens links through `launchLinkUrl` after a confirmation. Pass `onTapLink` to the
  controller to take over entirely; set `confirmBeforeOpeningLinks: false` to skip the confirmation.
- **Search:** `controller.find(...)`, `findNext()`, `findPrevious()`; style the matches with
  `matchHighlightColor` and `otherMatchesHighlightColor`. `FindReplaceBar` is optional.
- **Context menu:** pass `contextMenuBuilder` to `RichTextEditor` to replace the selection toolbar.

---

## 8. Testing your configuration

Add a widget test that proves the one-row policy for **your** font and **your** scales:

```dart
testWidgets('headings fit one row in MyFont', (tester) async {
  // Load the font inside runAsync, and create the FontLoader (and its futures) there too:
  // futures made in the test's fake clock never complete while awaited in real time.
  await tester.runAsync(() async {
    final loader = FontLoader('MyFont')
      ..addFont(Future.value(ByteData.sublistView(File('assets/MyFont.ttf').readAsBytesSync())));
    await loader.load();
  });

  final controller = RichEditorController(text: 'Title\nbody', theme: const RichTextRenderTheme(bodyFontFamily: 'MyFont'));
  final scroll = ScrollController();
  addTearDown(controller.dispose);
  addTearDown(scroll.dispose);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData(fontFamily: 'MyFont'),
    home: Scaffold(body: RichTextEditor(controller: controller, scrollController: scroll)),
  ));
  await tester.pumpAndSettle();

  expect(controller.renderer.activeRowMetrics!.allHeadersFitOneRow, isTrue);
});
```

Notes:

- `flutter test` does not load a project's fonts by itself; load the one you use explicitly (as above).
- Loop over the text scales you support (for example 0.85, 1.0, 1.3, 2.0, 3.0).
- Font files declared as variable fonts work with `FontWeight`: Flutter maps the weight onto the font's weight
  axis, so one file is enough.
- Always confirm on a device too: system fonts and the keyboard are not available in unit tests.

---

## 9. Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| A heading's lines each take two rows and the text floats between the rules | The font's line box is taller than the row at that heading size | Lower `h1FontSize`..`h3FontSize` (section 2), or raise `lineHeight`/`headerRowFill` |
| Headings fit at normal text size but not at large | Heading sizes not scaled with the row | Scale `lineHeight` and heading sizes together (section 4) |
| Text sits slightly above or below the rules after changing font | Different ascent/descent proportions | Re-check with `rowsForParagraph`; adjust `lineHeight` by a pixel or two and verify on a device |
| Dark mode text is invisible | `textColor` was not updated | Assign a theme with the new `textColor` (section 3) |
| Links hard to read in dark mode | Light-mode `linkColor` kept | Use a lighter blue in dark mode |
| Colours in code blocks look wrong on a dark page | Light `codeSyntax` | Use `CodeSyntaxColors.dark` |
| Picture shows a "missing" placeholder | The store has no bytes for that id | Make sure the id is stored and `load` returns it |
| A very large imported font size is clamped | Inline sizes are capped to what fits a row (`maxInlineFontSize`) | Expected; the stored value is kept, the display is limited |
| Editor chrome (picture bar, code chip) uses Material icons | By design | See section 5 |

See also: `README.md` (quick start), `EXTENSION_POINTS.md` (known limits), `CHANGELOG.md`.
