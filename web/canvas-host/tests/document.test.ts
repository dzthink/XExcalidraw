import test from "node:test";
import assert from "node:assert/strict";
import { DocumentStore, newDocument, newNode, moveNodes, structure, parseDocument, plainContent, topLevelSelection, findNode } from "../src/mindmap/document";
import { readContent, schema, safeLink, attachmentSource } from "../src/mindmap/richText";
import { EditorState, TextSelection } from "prosemirror-state";
import { toggleMark } from "prosemirror-commands";
import { addRowAfter, deleteColumn } from "prosemirror-tables";
function fixture() { const doc = newDocument(); const a = newNode("A"), b = newNode("B"), c = newNode("C"); a.children.push(c); doc.nodeData.children.push(a, b); return { doc, a, b, c }; }
test("batch movement prunes descendants and rejects cycles without losing nodes", () => {
 const {doc,a,b,c}=fixture(); assert.deepEqual(topLevelSelection(doc.nodeData,[a.id,c.id]).map(n=>n.id),[a.id]);
 assert.equal(moveNodes(doc.nodeData,[a.id],c.id,"inside"),false); assert.equal(moveNodes(doc.nodeData,[a.id,c.id],b.id,"inside"),true);
 assert.deepEqual(doc.nodeData.children.map(n=>n.id),[b.id]); assert.equal(b.children[0].children[0].id,c.id);
});
test("indent and outdent preserve sibling order and root boundary",()=>{
 const {doc,a,b}=fixture(); assert.equal(structure(doc.nodeData,[b.id],"indent"),b.id); assert.equal(a.children[1].id,b.id);
 assert.equal(structure(doc.nodeData,[b.id],"outdent"),b.id); assert.equal(doc.nodeData.children[1].id,b.id);
 assert.equal(structure(doc.nodeData,[a.id],"outdent"),null);
});
test("shared history restores rich text, note and cursor while retaining viewport",()=>{
 const {doc,a}=fixture(); const store=new DocumentStore(doc); store.cursor={id:a.id,from:1,to:1,field:"content"};
 store.change(d=>{findNode(d.nodeData,a.id)!.content=plainContent("AB")},"typing");
 store.change(d=>{findNode(d.nodeData,a.id)!.content=plainContent("ABC")},"typing");
 store.boundary(); store.cursor={id:a.id,from:4,to:4,field:"content"}; store.change(d=>{findNode(d.nodeData,a.id)!.note="line1\nline2"},"note");
 store.document.views.mode="map"; store.document.views.map.scale=.6;
 assert.equal(store.undo(),true); assert.equal(findNode(store.document.nodeData,a.id)!.note,""); assert.equal(store.cursor!.from,4);
 assert.equal(store.undo(),true); assert.deepEqual(findNode(store.document.nodeData,a.id)!.content,plainContent("A")); assert.equal(store.cursor!.from,1); assert.equal(store.document.views.map.scale,.6);
 store.redo(); store.redo(); assert.equal(findNode(store.document.nodeData,a.id)!.note,"line1\nline2");
});
test("legacy, duplicate IDs and unsupported content fail validation",()=>{
 assert.equal(parseDocument({nodeData:{topic:"legacy"}}),null); const {doc,a,b}=fixture(); b.id=a.id; assert.equal(parseDocument(doc),null);
 assert.throws(()=>readContent({type:"doc",content:[{type:"heading",attrs:{level:4}}]}));
 assert.throws(()=>readContent({type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"x",marks:[{type:"link",attrs:{href:"javascript:alert(1)"}}]}]}]}));
});
test("formatting affects only selected text and survives JSON round trip",()=>{
 const state=EditorState.create({doc:readContent(plainContent("abcdef"))}); let next=state.apply(state.tr.setSelection(TextSelection.create(state.doc,2,5)));
 toggleMark(schema.marks.bold)(next,tr=>{next=next.apply(tr)}); const round=readContent(next.doc.toJSON());
 assert.equal(round.child(0).child(0).text,"a"); assert.equal(round.child(0).child(1).text,"bcd"); assert.equal(round.child(0).child(1).marks[0].type.name,"bold"); assert.equal(round.child(0).child(2).text,"ef");
});
test("table row/column commands preserve editable content and round trip",()=>{
 const cell=()=>schema.nodes.table_cell.createAndFill()!; const table=schema.nodes.table.create(null,[schema.nodes.table_row.create(null,[cell(),cell()]),schema.nodes.table_row.create(null,[cell(),cell()])]);
 let state=EditorState.create({doc:schema.nodes.doc.create(null,[table])}); state=state.apply(state.tr.setSelection(TextSelection.create(state.doc,4)));
 assert.equal(addRowAfter(state,tr=>{state=state.apply(tr)}),true); assert.equal(state.doc.child(0).childCount,3);
 assert.equal(deleteColumn(state,tr=>{state=state.apply(tr)}),true); assert.equal(readContent(state.doc.toJSON()).child(0).child(0).childCount,1);
});
test("links and attachments reject unsafe destinations",()=>{
 assert.equal(safeLink("javascript:alert(1)"),null); assert.equal(safeLink("file:///etc/passwd"),null); assert.equal(safeLink("https://example.com"),"https://example.com/");
 assert.equal(attachmentSource("attachments/../secret","doc"),""); assert.equal(attachmentSource("https://example.com/a.png","doc"),""); assert.match(attachmentSource("../attachments/abc.png","/doc.mindmap"),/^app:\/\/\/mindmap-attachment/);
});

// The host can retain its full height, shrink natively, or pan while typing.
import { keyboardViewport } from "../src/mindmap/keyboardViewport";
test("keyboard toolbar follows visible bottom without double counting native resize", () => {
  assert.deepEqual(keyboardViewport(844, 844, 510, 0, 844), { inset: 334, open: true });
  assert.deepEqual(keyboardViewport(844, 844, 510, 90, 844), { inset: 244, open: true });
  assert.deepEqual(keyboardViewport(510, 510, 510, 0, 844), { inset: 0, open: true });
  assert.deepEqual(keyboardViewport(844, 844, 844, 0, 844), { inset: 0, open: false });
});

import { toggleQuote } from "../src/mindmap/quote";
test("quote formatting wraps selected paragraphs, toggles off and survives shared undo", () => {
  const doc = newDocument(); doc.nodeData.content = plainContent("quoted text");
  const store = new DocumentStore(doc);
  let state = EditorState.create({ doc: readContent(doc.nodeData.content) });
  assert.equal(toggleQuote(state, tr => { state = state.apply(tr); }), true);
  assert.equal(state.doc.child(0).type.name, "blockquote");
  assert.equal(readContent(state.doc.toJSON()).textContent, "quoted text");
  store.change(d => { d.nodeData.content = state.doc.toJSON(); });
  assert.equal(store.undo(), true);
  assert.equal(readContent(store.document.nodeData.content).child(0).type.name, "paragraph");
  assert.equal(store.redo(), true);
  assert.equal(readContent(store.document.nodeData.content).child(0).type.name, "blockquote");
  assert.equal(toggleQuote(state, tr => { state = state.apply(tr); }), true);
  assert.equal(state.doc.child(0).type.name, "paragraph");
});
test("legacy notes merge into quote blocks once without losing multiline content", () => {
  const { doc, a } = fixture(); a.note = "first\n\nlast";
  const parsed = parseDocument(doc)!;
  const node = findNode(parsed.nodeData, a.id)!;
  assert.equal(node.note, "");
  const content = readContent(node.content);
  assert.equal(content.child(0).textContent, "A");
  assert.equal(content.child(1).type.name, "blockquote");
  assert.deepEqual(Array.from({ length: content.child(1).childCount }, (_, i) => content.child(1).child(i).textContent), ["first", "", "last"]);
  assert.deepEqual(parseDocument(parsed), parsed);
  assert.equal(a.note, "first\n\nlast");
});

import { continueAfterBlock, exitCodeOnEmptyLine, trailingParagraph, withTrailingParagraph } from "../src/mindmap/blockEditing";
test("terminal tables and code retain a reachable paragraph without duplicates", () => {
  const cell = schema.nodes.table_cell.createAndFill()!;
  const table = schema.nodes.table.create(null, [schema.nodes.table_row.create(null, [cell])]);
  for (const block of [table, schema.nodes.code_block.create(null, schema.text("code")), schema.nodes.blockquote.create(null, schema.nodes.paragraph.create())]) {
    const normalized = withTrailingParagraph(schema.nodes.doc.create(null, [block]));
    assert.equal(normalized.lastChild!.type.name, "paragraph");
    assert.equal(withTrailingParagraph(normalized).childCount, 2);
    let state = EditorState.create({ doc: normalized, plugins: [trailingParagraph] });
    state = state.apply(state.tr.setSelection(TextSelection.atStart(state.doc)));
    assert.equal(continueAfterBlock(state, tr => { state = state.apply(tr); }), true);
    assert.equal(state.selection.$from.parent.type.name, "paragraph");
    assert.equal(state.selection.$from.depth, 1);
    state = state.apply(state.tr.insertText("after"));
    assert.equal(state.doc.lastChild!.textContent, "after");
    assert.equal(state.doc.child(0).eq(block), true);
  }
});
test("continuing after a table inserts text before the following code block", () => {
  const table = schema.nodes.table.create(null, [schema.nodes.table_row.create(null, [schema.nodes.table_cell.createAndFill()!])]);
  const code = schema.nodes.code_block.create(null, schema.text("keep"));
  let state = EditorState.create({ doc: schema.nodes.doc.create(null, [table, code]) });
  continueAfterBlock(state, tr => { state = state.apply(tr); });
  assert.deepEqual(Array.from({ length: state.doc.childCount }, (_, i) => state.doc.child(i).type.name), ["table", "paragraph", "code_block"]);
  assert.equal(state.doc.child(2).textContent, "keep");
});
test("trailing paragraph plugin appends in the same edit and shared undo restores content", () => {
  const doc = newDocument(); const store = new DocumentStore(doc);
  let state = EditorState.create({ doc: readContent(doc.nodeData.content), plugins: [trailingParagraph] });
  const result = state.applyTransaction(state.tr.setBlockType(0, state.doc.content.size, schema.nodes.code_block));
  assert.equal(result.transactions.length, 2);
  state = result.state;
  assert.equal(state.doc.child(0).type.name, "code_block");
  assert.equal(state.doc.lastChild!.type.name, "paragraph");
  store.change(d => { d.nodeData.content = state.doc.toJSON(); });
  assert.equal(store.undo(), true);
  assert.deepEqual(store.document.nodeData.content, doc.nodeData.content);
  assert.equal(store.redo(), true);
  assert.deepEqual(readContent(store.document.nodeData.content).toJSON(), state.doc.toJSON());
});
test("second Enter at code end exits to text while ordinary code lines stay intact", () => {
  const code = schema.nodes.code_block.create(null, schema.text("code\n"));
  let state = EditorState.create({ doc: withTrailingParagraph(schema.nodes.doc.create(null, code)), plugins: [trailingParagraph] });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, code.nodeSize - 1)));
  assert.equal(exitCodeOnEmptyLine(state, tr => { state = state.apply(tr); }), true);
  assert.equal(state.doc.child(0).textContent, "code");
  assert.equal(state.selection.$from.parent.type.name, "paragraph");
  assert.equal(exitCodeOnEmptyLine(state), false);
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 2)));
  assert.equal(exitCodeOnEmptyLine(state), false);
});

import { setList } from "../src/mindmap/list";
test("list styles switch directly with saved markers and preserved content and cursor", () => {
  const item = schema.nodes.list_item.create(null, schema.nodes.paragraph.create(null, schema.text("first", [schema.marks.bold.create()])));
  let state = EditorState.create({ doc: schema.nodes.doc.create(null, schema.nodes.bullet_list.create(null, [item, item])) });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 4)));
  for (const style of ["ordered", "dash", "bullet", "ordered", "bullet", "dash"] as const) {
    assert.equal(setList(style)(state), true);
    assert.equal(setList(style)(state, tr => { state = state.apply(tr); }), true);
    const list = readContent(state.doc.toJSON()).firstChild!;
    assert.equal(list.type.name, style === "ordered" ? "ordered_list" : "bullet_list");
    if (style !== "ordered") assert.equal(list.attrs.marker, style);
    assert.equal(list.childCount, 2);
    assert.equal(list.firstChild!.firstChild!.firstChild!.marks[0].type.name, "bold");
    assert.equal(state.selection.from, 4);
  }
});
test("dash creation and nested conversion preserve parent style", () => {
  let state = EditorState.create({ doc: readContent(plainContent("text")) });
  setList("dash")(state, tr => { state = state.apply(tr); });
  assert.equal(state.doc.firstChild!.attrs.marker, "dash");
  const nested = schema.nodes.ordered_list.create(null, schema.nodes.list_item.create(null, schema.nodes.paragraph.create(null, schema.text("nested"))));
  const outer = schema.nodes.bullet_list.create(null, schema.nodes.list_item.create(null, [schema.nodes.paragraph.create(null, schema.text("outer")), nested]));
  state = EditorState.create({ doc: schema.nodes.doc.create(null, outer) });
  let cursor = 0;
  state.doc.descendants((node, pos) => { if (node.isText && node.text === "nested") cursor = pos; });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, cursor)));
  setList("dash")(state, tr => { state = state.apply(tr); });
  assert.equal(state.doc.firstChild!.attrs.marker, "bullet");
  assert.equal(state.doc.firstChild!.firstChild!.child(1).attrs.marker, "dash");
});
