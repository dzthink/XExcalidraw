import { useLayoutEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { EditorState, TextSelection, NodeSelection, AllSelection, type Transaction } from "prosemirror-state";
import { EditorView } from "prosemirror-view";
import { baseKeymap, toggleMark, wrapIn } from "prosemirror-commands";
import { sinkListItem, liftListItem } from "prosemirror-schema-list";
import { tableEditing, goToNextCell } from "prosemirror-tables";
import { continueAfterBlock, exitCodeOnEmptyLine, trailingParagraph, withTrailingParagraph } from "./blockEditing";
import { schema, readContent, attachmentSource, safeLink } from "./richText";
import type { Cursor, RichDocument } from "./document";
import "prosemirror-view/style/prosemirror.css";
import "prosemirror-tables/style/tables.css";

export type EditorHandle = { id: string; view: EditorView };
type Props = {
  id: string; content: RichDocument; docId: string; readOnly: boolean; label: string;
  onChange: (content: RichDocument, previous: Cursor, next: Cursor) => void;
  onActive: (handle: EditorHandle) => void; onBlur: () => void;
  onKey: (view: EditorView, event: KeyboardEvent) => boolean;
  onImage: (file: File, view: EditorView) => void;
  onResize: () => void;
  restore?: Cursor | null;
};
export default function RichEditor(props: Props) {
  const [isActive, setIsActive] = useState(false);
  const [hasBlocks, setHasBlocks] = useState(() => (props.content.content ?? []).some(node => !["paragraph", "heading"].includes(node.type)));
  const host = useRef<HTMLDivElement>(null);
  const continueButton = useRef<HTMLButtonElement>(null);
  const viewRef = useRef<EditorView | null>(null);
  const latest = useRef(props); latest.current = props;
  useLayoutEffect(() => {
    if (!host.current) return;
    const view = new EditorView(host.current, {
      state: EditorState.create({ doc: withTrailingParagraph(readContent(props.content)), plugins: [tableEditing(), trailingParagraph] }),
      editable: () => !latest.current.readOnly,
      attributes: { class: "mindmap-rich-content", "aria-label": props.label, role: "textbox", "aria-multiline": "true", "data-editor-id": props.id },
      nodeViews: {
        image: node => {
          const image = document.createElement("img");
          image.src = attachmentSource(node.attrs.path, latest.current.docId);
          image.alt = node.attrs.alt;
          image.width = Math.max(40, Math.min(640, Number(node.attrs.width) || 240));
          image.addEventListener("load", () => latest.current.onResize());
          return { dom: image };
        }
      },
      dispatchTransaction(transaction: Transaction) {
        const previous = { id: props.id, from: view.state.selection.from, to: view.state.selection.to, field: "content" as const };
        const result = view.state.applyTransaction(transaction);
        view.updateState(result.state);
        setHasBlocks(view.state.doc.content.content.some(node => ![schema.nodes.paragraph, schema.nodes.heading].includes(node.type)));
        const next = { ...previous, from: view.state.selection.from, to: view.state.selection.to };
        if (result.transactions.some(tr => tr.docChanged)) latest.current.onChange(view.state.doc.toJSON(), previous, next);
        latest.current.onActive({ id: props.id, view });
      },
      handleDOMEvents: {
        focus: () => { setIsActive(true); latest.current.onActive({ id: props.id, view }); return false; },
        blur: () => { setIsActive(false); latest.current.onBlur(); return false; },
        pointerdown: (_view, event) => { event.stopPropagation(); return false; }
      },
      handleTextInput(view, from, to, text) {
        const { $from } = view.state.selection;
        if (text !== " " || from !== to || $from.parent.type !== schema.nodes.paragraph || $from.parentOffset !== 1 || $from.parent.textContent !== ">") return false;
        const state = view.state.apply(view.state.tr.delete(from - 1, from));
        return wrapIn(schema.nodes.blockquote)(state, transaction => {
          // Apply the input shortcut in one transaction for shared undo history.
          const tr = view.state.tr.delete(from - 1, from);
          transaction.steps.forEach(step => tr.step(step));
          view.dispatch(tr);
        });
      },
      handleClick(_view, _pos, event) {
        const link = (event.target as HTMLElement).closest("a");
        if (link && (latest.current.readOnly || event.metaKey || event.ctrlKey)) {
          const href = safeLink(link.getAttribute("href") ?? "");
          event.preventDefault();
          if (href) window.dispatchEvent(new CustomEvent("mindmap-open-link", { detail: href }));
          return true;
        }
        return false;
      },
      handleKeyDown(view, event) {
        event.stopPropagation();
        if (view.composing || event.isComposing) return false;
        if (event.key === "Enter" && (event.metaKey || event.ctrlKey) && continueAfterBlock(view.state, view.dispatch)) return true;
        if (event.key === "Enter" && !event.shiftKey && exitCodeOnEmptyLine(view.state, view.dispatch)) return true;
        if (latest.current.onKey(view, event)) return true;
        if (event.key === "Enter" && event.shiftKey && !view.state.selection.$from.parent.type.spec.code) {
          view.dispatch(view.state.tr.replaceSelectionWith(schema.nodes.hard_break.create()).scrollIntoView());
          return true;
        }
        if ((event.ctrlKey || event.metaKey) && ["b", "i", "x"].includes(event.key.toLowerCase())) {
          const mark = event.key.toLowerCase() === "b" ? schema.marks.bold : event.key.toLowerCase() === "i" ? schema.marks.italic : schema.marks.strike;
          if (event.key.toLowerCase() === "x" && !event.shiftKey) return false;
          return toggleMark(mark)(view.state, view.dispatch, view);
        }
        if (event.key === "Tab" && (event.shiftKey ? liftListItem(schema.nodes.list_item) : sinkListItem(schema.nodes.list_item))(view.state, view.dispatch)) return true;
        if (event.key === "Tab" && goToNextCell(event.shiftKey ? -1 : 1)(view.state, view.dispatch)) return true;
        if (event.key === "Tab" && view.state.selection.$from.parent.type.name === "code_block") {
          view.dispatch(view.state.tr.insertText("  ")); return true;
        }
        const command = baseKeymap[event.key];
        return command ? command(view.state, view.dispatch, view) : false;
      },
      handlePaste(view, event) {
        const file = Array.from(event.clipboardData?.files ?? []).find(item => item.type.startsWith("image/"));
        if (file) { latest.current.onImage(file, view); return true; }
        return false;
      },
      handleDrop(view, event) {
        const file = Array.from(event.dataTransfer?.files ?? []).find(item => item.type.startsWith("image/"));
        if (file) { latest.current.onImage(file, view); return true; }
        return false;
      }
    });
    viewRef.current = view;
    // Selection transactions do not change geometry. Observe actual editor size.
    let width = -1, height = -1;
    const observer = new ResizeObserver(entries => {
      const box = entries[0]?.contentRect;
      if (!box || box.width === width && box.height === height) return;
      width = box.width; height = box.height; latest.current.onResize();
    });
    observer.observe(view.dom);
    return () => { observer.disconnect(); viewRef.current = null; view.destroy(); };
  }, [props.id]);
  useLayoutEffect(() => {
    const view = viewRef.current;
    if (!view) return;
    const next = withTrailingParagraph(readContent(props.content));
    if (!view.state.doc.eq(next)) {
      const from = Math.min(view.state.selection.from, next.content.size);
      view.updateState(EditorState.create({ doc: next, plugins: [tableEditing(), trailingParagraph], selection: TextSelection.near(next.resolve(from)) }));
    }
  }, [props.content]);
  useLayoutEffect(() => { viewRef.current?.setProps({ editable: () => !props.readOnly }); }, [props.readOnly, props.id]);
  useLayoutEffect(() => {
    const view = viewRef.current, cursor = props.restore;
    if (!view || !cursor || cursor.id !== props.id || cursor.field !== "content") return;
    const from = Math.min(cursor.from, view.state.doc.content.size), to = Math.min(cursor.to, view.state.doc.content.size);
    const doc = view.state.doc, node = doc.nodeAt(from);
    const selection = from === 0 && to === doc.content.size ? new AllSelection(doc) : node?.isAtom && node.type.spec.selectable !== false && to === from + node.nodeSize ? NodeSelection.create(doc, from) : doc.resolve(from).parent.inlineContent && doc.resolve(to).parent.inlineContent ? TextSelection.create(doc, from, to) : TextSelection.near(doc.resolve(from));
    view.dispatch(view.state.tr.setSelection(selection));
    view.focus();
  }, [props.restore]);
  const continueInput = () => {
    const view = viewRef.current;
    if (!view || !continueAfterBlock(view.state, view.dispatch)) return;
    const bookmark = view.state.selection.getBookmark();
    view.focus();
    // WebKit may restore the old native caret after moving out of a table.
    requestAnimationFrame(() => {
      if (viewRef.current !== view || !view.dom.isConnected) return;
      view.dispatch(view.state.tr.setSelection(bookmark.resolve(view.state.doc)));
    });
  };
  useLayoutEffect(() => {
    const button = continueButton.current;
    if (!button) return;
    const touch = (event: TouchEvent) => {
      event.preventDefault(); event.stopPropagation();
      continueInput();
    };
    // Cancelling pointerdown does not cancel WebKit's native touch focus change.
    button.addEventListener("touchstart", touch, { passive: false });
    return () => button.removeEventListener("touchstart", touch);
  }, [isActive, hasBlocks, props.readOnly]);
  const surface = host.current?.closest(".siye-editor");
  return <div className="mindmap-rich-editor">
    <div ref={host} />
    {surface && isActive && hasBlocks && !props.readOnly && createPortal(<button ref={continueButton} type="button" className="mindmap-continue-after-block"
      onMouseDown={event => event.preventDefault()}
      onPointerDown={event => {
        event.preventDefault(); event.stopPropagation();
        // Retain native keyboard focus within the trusted touch event.
        continueInput();
      }}
      onClick={continueInput}>在块后继续输入</button>, surface)}
  </div>;
}
export function selectImage(view: EditorView): boolean { return view.state.selection instanceof NodeSelection && view.state.selection.node.type.name === "image"; }
