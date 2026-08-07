import 'package:flutter_test/flutter_test.dart';

import 'package:lightweight_rich_editor/src/commands/replace_range_command.dart';
import 'package:lightweight_rich_editor/src/core/editing_engine.dart';
import 'package:lightweight_rich_editor/src/core/editor_document.dart';
import 'package:lightweight_rich_editor/src/core/transaction_manager.dart';
import 'package:lightweight_rich_editor/src/history/history_manager.dart';
import 'package:lightweight_rich_editor/src/metrics/editor_metrics.dart';
import 'package:lightweight_rich_editor/src/models/attribute_type.dart';
import 'package:lightweight_rich_editor/src/models/text_attribute.dart';

void main() {
  test('reflects character count, attribute count, and undo/redo depth', () {
    final document = EditorDocument.fromText(
      'hello',
      const [TextAttribute(start: 0, end: 5, type: AttributeType.bold)],
    );
    final engine = EditingEngine(document: document, transactions: TransactionManager(() {}));
    final history = HistoryManager(engine: engine);
    final metrics = EditorMetrics(document: document, history: history);

    expect(metrics.characterCount, 5);
    expect(metrics.wordCount, 1);
    expect(metrics.attributeCount, 1);
    expect(metrics.undoDepth, 0);
    expect(metrics.redoDepth, 0);

    history.execute(ReplaceRangeCommand(start: 5, end: 5, text: ' world!'));
    expect(metrics.characterCount, 12);
    expect(metrics.wordCount, 2);
    expect(metrics.undoDepth, 1);

    history.undo();
    expect(metrics.characterCount, 5);
    expect(metrics.undoDepth, 0);
    expect(metrics.redoDepth, 1);
  });
}