import { splitBlock } from "prosemirror-commands";
import { TextSelection, type EditorState, type Transaction } from "prosemirror-state";

// Track only the paragraph break created by the first Return.
export class DoubleEnter {
  private pending: { before: EditorState; after: EditorState; time: number } | null = null;
  private handling = false;

  reset() { if (!this.handling) this.pending = null; }

  handle(getState: () => EditorState, dispatch: (tr: Transaction) => void, sibling: () => void, time: number): boolean {
    const state = getState(), selection = state.selection;
    if (!(selection instanceof TextSelection) || !selection.empty || selection.$from.depth !== 1 || selection.$from.parent.type.name !== "paragraph") {
      this.reset(); return false;
    }
    const pending = this.pending;
    this.pending = null;
    this.handling = true;
    try {
      if (pending && pending.after.doc.eq(state.doc) && pending.after.selection.eq(selection) && time >= pending.time && time - pending.time <= 450) {
        const tr = state.tr.replaceWith(0, state.doc.content.size, pending.before.doc.content);
        tr.setSelection(pending.before.selection.getBookmark().resolve(tr.doc));
        dispatch(tr);
        sibling();
        return true;
      }
      if (!splitBlock(state, dispatch)) return false;
      this.pending = { before: state, after: getState(), time };
      return true;
    } finally { this.handling = false; }
  }
}
