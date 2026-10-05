import { wrapInList, splitListItem } from "prosemirror-schema-list";
import type { Command } from "prosemirror-state";
import { schema } from "./richText";

export function setList(style: "bullet" | "ordered" | "task"): Command {
  return (state, dispatch, view) => {
    const type = style === "ordered" ? schema.nodes.ordered_list : schema.nodes.bullet_list;
    const attrs = style === "ordered" ? { order: 1 } : { marker: style };
    const isList = (name: string) => name === "bullet_list" || name === "ordered_list";
    const { $from, from, to } = state.selection;
    const positions = new Set<number>();
    // A cursor inside a nested list changes the nearest list only.
    for (let depth = $from.depth; depth > 0; depth--) {
      if (isList($from.node(depth).type.name)) {
        positions.add($from.before(depth));
        break;
      }
    }
    state.doc.nodesBetween(from, to, (node, pos) => {
      if (isList(node.type.name)) {
        if ([...positions].some(selected => pos < selected && selected < pos + node.nodeSize)) return true;
        if (![...positions].some(parent => parent <= pos && pos < parent + state.doc.nodeAt(parent)!.nodeSize)) positions.add(pos);
        return false;
      }
      return true;
    });
    if (!positions.size) return wrapInList(type, attrs)(state, dispatch, view);
    if (dispatch) {
      const tr = state.tr;
      for (const pos of positions) tr.setNodeMarkup(pos, type, attrs);
      dispatch(tr.scrollIntoView());
    }
    return true;
  };
}

// ProseMirror applies itemAttrs only at the end of a paragraph. Reset the
// new item's completion explicitly when Return splits within existing text.
export const splitUnfinishedListItem: Command = (state, dispatch, view) =>
  splitListItem(schema.nodes.list_item, { checked: false })(state, dispatch && (tr => {
    const { $from } = tr.selection;
    for (let depth = $from.depth; depth > 0; depth--) {
      const node = $from.node(depth);
      if (node.type !== schema.nodes.list_item) continue;
      if (node.attrs.checked) tr.setNodeMarkup($from.before(depth), undefined, { ...node.attrs, checked: false });
      break;
    }
    dispatch(tr);
  }), view);
