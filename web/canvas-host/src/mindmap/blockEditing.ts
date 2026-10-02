import { Fragment, type Node as PMNode } from "prosemirror-model";
import { Plugin, TextSelection, type Command } from "prosemirror-state";
import { schema } from "./richText";

// Every block has a reachable place for continuing with ordinary text.
export function withTrailingParagraph(doc: PMNode): PMNode {
  if (doc.lastChild?.type === schema.nodes.paragraph) return doc;
  return doc.copy(doc.content.append(Fragment.from(schema.nodes.paragraph.create())));
}
export const trailingParagraph = new Plugin({
  appendTransaction(transactions, _oldState, state) {
    if (!transactions.some(transaction => transaction.docChanged) || state.doc.lastChild?.type === schema.nodes.paragraph) return null;
    return state.tr.insert(state.doc.content.size, schema.nodes.paragraph.create());
  }
});
export const continueAfterBlock: Command = (state, dispatch) => {
  const { $from } = state.selection;
  const block = $from.depth ? $from.node(1) : state.doc.nodeAt($from.pos);
  if (!block || block.type === schema.nodes.paragraph || block.type === schema.nodes.heading) return false;
  const after = $from.depth ? $from.after(1) : $from.pos + block.nodeSize;
  const tr = state.tr;
  if (tr.doc.nodeAt(after)?.type !== schema.nodes.paragraph) tr.insert(after, schema.nodes.paragraph.create());
  tr.setSelection(TextSelection.create(tr.doc, after + 1)).scrollIntoView();
  dispatch?.(tr);
  return true;
};
export const exitCodeOnEmptyLine: Command = (state, dispatch) => {
  const { $from, empty } = state.selection;
  if (!empty || $from.depth !== 1 || $from.parent.type !== schema.nodes.code_block || $from.parentOffset !== $from.parent.content.size || !$from.parent.textContent.endsWith("\n")) return false;
  const tr = state.tr.delete($from.pos - 1, $from.pos);
  return continueAfterBlock(state.apply(tr), exit => {
    exit.steps.forEach(step => tr.step(step));
    tr.setSelection(exit.selection).scrollIntoView();
    dispatch?.(tr);
  });
};
