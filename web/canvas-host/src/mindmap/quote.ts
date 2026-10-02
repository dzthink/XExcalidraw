import { wrapIn } from "prosemirror-commands";
import { liftTarget } from "prosemirror-transform";
import type { Command } from "prosemirror-state";
import { schema } from "./richText";

export const toggleQuote: Command = (state, dispatch, view) => {
  const { $from, $to } = state.selection;
  const range = $from.blockRange($to, node => node.type === schema.nodes.blockquote);
  if (range) {
    const target = liftTarget(range);
    if (target === null) return false;
    dispatch?.(state.tr.lift(range, target).scrollIntoView());
    return true;
  }
  return wrapIn(schema.nodes.blockquote)(state, dispatch, view);
};
