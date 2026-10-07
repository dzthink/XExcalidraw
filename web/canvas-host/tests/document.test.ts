import test from "node:test";
import assert from "node:assert/strict";
import { DocumentStore, newDocument, newNode, moveNodes, structure, parseDocument, plainContent, topLevelSelection, findNode } from "../src/mindmap/document";
import { readContent, schema, safeLink, attachmentSource } from "../src/mindmap/richText";
import { EditorState, TextSelection } from "prosemirror-state";
import { toggleMark } from "prosemirror-commands";
import { addRowAfter, deleteColumn } from "prosemirror-tables";
import { allowsNodeLongPress } from "../src/mindmap/nodeInteraction";
import { DoubleEnter } from "../src/mindmap/doubleEnter";
test("quick double Return restores text and cursor before creating a sibling", () => {
  const gesture = new DoubleEnter();
  let state = EditorState.create({ doc: readContent(plainContent("abcd")) });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 3)));
  const original = state.doc;
  let siblings = 0;
  const dispatch = (tr: EditorState["tr"]) => { gesture.reset(); state = state.apply(tr); };
  const enter = (time: number) => gesture.handle(() => state, dispatch, () => { siblings++; }, time);
  assert.equal(enter(100), true);
  assert.equal(state.doc.childCount, 2);
  assert.equal(enter(400), true);
  assert.equal(siblings, 1);
  assert.ok(state.doc.eq(original));
  assert.equal(state.selection.from, 3);
});
test("slow Return and intervening input keep ordinary paragraph breaks", () => {
  for (const interrupted of [false, true]) {
    const gesture = new DoubleEnter();
    let state = EditorState.create({ doc: readContent(plainContent("text")) });
    let siblings = 0;
    const dispatch = (tr: EditorState["tr"]) => { gesture.reset(); state = state.apply(tr); };
    const enter = (time: number) => gesture.handle(() => state, dispatch, () => { siblings++; }, time);
    enter(100);
    if (interrupted) dispatch(state.tr.insertText("x"));
    enter(interrupted ? 200 : 551);
    assert.equal(siblings, 0);
    assert.equal(state.doc.childCount, 3);
  }
});
test("double Return leaves nested blocks, code and selected text to normal editing", () => {
  const paragraph = schema.nodes.paragraph.create(null, schema.text("text"));
  const docs = [
    schema.nodes.doc.create(null, schema.nodes.blockquote.create(null, paragraph)),
    schema.nodes.doc.create(null, schema.nodes.code_block.create(null, schema.text("code")))
  ];
  for (const doc of docs) {
    const state = EditorState.create({ doc });
    assert.equal(new DoubleEnter().handle(() => state, () => assert.fail("unexpected edit"), () => assert.fail("unexpected sibling"), 100), false);
  }
  let state = EditorState.create({ doc: readContent(plainContent("text")) });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 1, 3)));
  assert.equal(new DoubleEnter().handle(() => state, () => assert.fail("unexpected edit"), () => assert.fail("unexpected sibling"), 100), false);
});
test("node long press follows view and editing state independently of keyboard visibility", () => {
  for (const editing of [null, "a"]) {
    assert.equal(allowsNodeLongPress("outline", editing, "a", false), false);
    assert.equal(allowsNodeLongPress("outline", editing, "b", false), false);
  }
  assert.equal(allowsNodeLongPress("map", null, "a", false), true);
  assert.equal(allowsNodeLongPress("map", "a", "a", false), false);
  assert.equal(allowsNodeLongPress("map", "a", "b", false), true);
  assert.equal(allowsNodeLongPress("map", null, null, false), false);
  assert.equal(allowsNodeLongPress("map", null, "a", true), false);
});
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

import { setList, splitUnfinishedListItem } from "../src/mindmap/list";
test("list styles switch directly with saved markers and preserved content and cursor", () => {
  const item = schema.nodes.list_item.create(null, schema.nodes.paragraph.create(null, schema.text("first", [schema.marks.bold.create()])));
  let state = EditorState.create({ doc: schema.nodes.doc.create(null, schema.nodes.bullet_list.create(null, [item, item])) });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 4)));
  for (const style of ["ordered", "task", "bullet", "ordered", "bullet", "task"] as const) {
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
test("task creation and nested conversion preserve parent style", () => {
  let state = EditorState.create({ doc: readContent(plainContent("text")) });
  setList("task")(state, tr => { state = state.apply(tr); });
  assert.equal(state.doc.firstChild!.attrs.marker, "task");
  const nested = schema.nodes.ordered_list.create(null, schema.nodes.list_item.create(null, schema.nodes.paragraph.create(null, schema.text("nested"))));
  const outer = schema.nodes.bullet_list.create(null, schema.nodes.list_item.create(null, [schema.nodes.paragraph.create(null, schema.text("outer")), nested]));
  state = EditorState.create({ doc: schema.nodes.doc.create(null, outer) });
  let cursor = 0;
  state.doc.descendants((node, pos) => { if (node.isText && node.text === "nested") cursor = pos; });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, cursor)));
  setList("task")(state, tr => { state = state.apply(tr); });
  assert.equal(state.doc.firstChild!.attrs.marker, "bullet");
  assert.equal(state.doc.firstChild!.firstChild!.child(1).attrs.marker, "task");
});

test("node-local history groups input and restores edits across deletion and structural undo", () => {
  const { doc, a, b } = fixture(), store = new DocumentStore(doc);
  const sibling = store.node(b.id)!;
  store.cursor = { id: a.id, from: 2, to: 2, field: "content" };
  store.changeContent(a.id, plainContent("edited"));
  store.changeContent(a.id, plainContent("edited twice"));
  assert.equal(store.node(b.id), sibling);
  assert.equal(store.structureRevision, 0);
  store.change(d => { structure(d.nodeData, [a.id], "delete"); });
  assert.equal(store.node(a.id), null);
  assert.equal(store.undo(), true);
  assert.equal(readContent(store.node(a.id)!.content).textContent, "edited twice");
  assert.equal(store.undo(), true);
  assert.equal(readContent(store.node(a.id)!.content).textContent, "A");
  assert.equal(store.redo(), true);
  assert.equal(readContent(store.node(a.id)!.content).textContent, "edited twice");
  assert.equal(store.redo(), true);
  assert.equal(store.node(a.id), null);
});

test("node-local no-op preserves redo and content history does not absorb a structure change", () => {
  const { doc, a } = fixture(), store = new DocumentStore(doc);
  store.changeContent(a.id, plainContent("changed"), "shared");
  store.change(d => { d.nodeData.children.push(newNode("new")); }, "shared");
  assert.equal(store.undo(), true);
  assert.equal(store.document.nodeData.children.length, 2);
  assert.equal(store.undo(), true);
  assert.equal(store.changeContent(a.id, plainContent("A")), false);
  assert.equal(store.redo(), true);
  assert.equal(readContent(store.node(a.id)!.content).textContent, "changed");
  store.boundary(); store.changeContent(a.id, plainContent("replacement"));
  assert.equal(store.redo(), false);
});

import { initializeBridge, addBridgeListener } from "../src/bridge";
test("bridge setup shares one dispatcher and releases it only after the last consumer", () => {
  const oldWindow = (globalThis as unknown as { window?: unknown }).window;
  const browser = Object.assign(new EventTarget(), { webkit: { messageHandlers: { bridge: { postMessage() {} } } }, matchMedia: () => ({ matches: false }), bridgeDispatch: undefined as ((data: string) => void) | undefined });
  (globalThis as unknown as { window: unknown }).window = browser;
  let deliveries = 0;
  const unlisten = addBridgeListener(() => deliveries++);
  const first = initializeBridge(), second = initializeBridge();
  const message = JSON.stringify({ version: "1.0", type: "webReady", payload: {} });
  try {
    browser.dispatchEvent(new MessageEvent("message", { data: message }));
    assert.equal(deliveries, 1);
    first(); first();
    browser.bridgeDispatch!(message);
    assert.equal(deliveries, 2);
    second();
    assert.equal(browser.bridgeDispatch, undefined);
    browser.dispatchEvent(new MessageEvent("message", { data: message }));
    assert.equal(deliveries, 2);
  } finally {
    first(); second(); unlisten();
    if (oldWindow === undefined) delete (globalThis as unknown as { window?: unknown }).window;
    else (globalThis as unknown as { window: unknown }).window = oldWindow;
  }
});

test("node lookup follows an identical structural replacement before subsequent input", () => {
  const { doc, a } = fixture(), store = new DocumentStore(doc);
  const previous = store.node(a.id);
  assert.equal(store.change(document => { document.nodeData = JSON.parse(JSON.stringify(document.nodeData)); }), false);
  assert.notEqual(store.node(a.id), previous);
  assert.equal(store.changeContent(a.id, plainContent("updated")), true);
  assert.equal(readContent(findNode(store.document.nodeData, a.id)!.content).textContent, "updated");
});

test("large node history drops old groups while retaining recent undo and redo", () => {
  const doc = newDocument(), store = new DocumentStore(doc), id = doc.nodeData.id;
  const text = "字".repeat(500000);
  for (let index = 0; index < 24; index++) store.changeContent(id, plainContent(text + index), `group-${index}`);
  let count = 0;
  while (store.undo()) count++;
  assert.ok(count > 0 && count < 24, "Large snapshots must stay within the history budget");
  for (let index = 0; index < count; index++) assert.equal(store.redo(), true);
  assert.equal(readContent(store.node(id)!.content).textContent, text + 23);
});


test("task completion survives save and splitting starts an unfinished item", () => {
  const item = schema.nodes.list_item.create({ checked: true }, schema.nodes.paragraph.create(null, schema.text("done")));
  let state = EditorState.create({ doc: schema.nodes.doc.create(null, schema.nodes.bullet_list.create({ marker: "task" }, item)) });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 7)));
  assert.equal(splitUnfinishedListItem(state, tr => { state = state.apply(tr); }), true);
  const saved = readContent(state.doc.toJSON());
  assert.equal(saved.firstChild!.child(0).attrs.checked, true);
  assert.equal(saved.firstChild!.child(1).attrs.checked, false);
  assert.equal(saved.firstChild!.child(1).textContent, "");
  assert.equal(state.selection.$from.parent.textContent, "");
});


test("splitting a completed task inside text resets the new item only", () => {
  const item = schema.nodes.list_item.create({ checked: true }, schema.nodes.paragraph.create(null, schema.text("first second")));
  let state = EditorState.create({ doc: schema.nodes.doc.create(null, schema.nodes.bullet_list.create({ marker: "task" }, item)) });
  state = state.apply(state.tr.setSelection(TextSelection.create(state.doc, 9)));
  assert.equal(splitUnfinishedListItem(state, tr => { state = state.apply(tr); }), true);
  assert.equal(state.doc.firstChild!.child(0).attrs.checked, true);
  assert.equal(state.doc.firstChild!.child(1).attrs.checked, false);
  assert.equal(state.doc.firstChild!.child(1).textContent, "second");
});

test("interchange exports escape XML, preserve tree and package valid XMind ZIP", async () => {
  const { exportFreeMind, exportOPML, exportXMind, htmlPage } = await import("../src/mindmap/interchange");
  const doc = newDocument();
  doc.nodeData.content = plainContent('中文 & <主题> "');
  doc.nodeData.note = "备注\n第二行";
  doc.nodeData.expanded = false;
  doc.nodeData.children.push(newNode("子主题"));
  assert.match(exportFreeMind(doc), /TEXT="中文 &amp; &lt;主题&gt; &quot;"/);
  assert.match(exportFreeMind(doc), /FOLDED="true"/);
  assert.match(exportFreeMind(doc), /TYPE="NOTE"/);
  assert.match(exportOPML(doc), /<outline text="子主题"/);
  assert.match(htmlPage("<script>", "<p>正文</p>"), /<title>&lt;script&gt;<\/title>/);
  const bytes = exportXMind(doc);
  const view = new DataView(bytes.buffer);
  assert.equal(view.getUint32(0, true), 0x04034b50);
  const nameLength = view.getUint16(26, true), size = view.getUint32(18, true);
  assert.equal(new TextDecoder().decode(bytes.subarray(30, 30 + nameLength)), "content.json");
  const sheets = JSON.parse(new TextDecoder().decode(bytes.subarray(30 + nameLength, 30 + nameLength + size)));
  assert.equal(sheets[0].rootTopic.title, '中文 & <主题> "');
  assert.equal(sheets[0].rootTopic.notes.plain.content, "备注\n第二行");
  assert.equal(sheets[0].rootTopic.children.attached[0].title, "子主题");
  assert.equal(view.getUint32(bytes.length - 22, true), 0x06054b50);
});

test("peer save replaces content while preserving local view and rebuilding node lookup", () => {
  const original = newDocument();
  const child = newNode("Before"); original.nodeData.children.push(child);
  const store = new DocumentStore(original);
  store.document.views.outlineScroll = 180;
  store.document.views.mode = "outline";
  store.document.views.selectedIds = [child.id];
  store.document.views.focusId = child.id;
  const oldNode = store.node(child.id);
  const remote = structuredClone(original);
  remote.nodeData.children[0].content = plainContent("After");
  remote.views.outlineScroll = 0; remote.views.mode = "map";
  store.replaceFromExternal(remote);
  assert.notEqual(store.node(child.id), oldNode);
  assert.deepEqual(store.node(child.id)?.content, plainContent("After"));
  assert.equal(store.document.views.outlineScroll, 180);
  assert.equal(store.document.views.mode, "outline");
  assert.deepEqual(store.document.views.selectedIds, [child.id]);
  assert.equal(store.document.views.focusId, child.id);
  assert.equal(store.revision, 0);
});

test("peer deletion clears invalid focus, selection and stale undo history", () => {
  const original = newDocument(); const child = newNode("Child");
  original.nodeData.children.push(child);
  const store = new DocumentStore(original);
  store.change(doc => { doc.nodeData.content = plainContent("Local change"); });
  store.document.views.selectedIds = [child.id]; store.document.views.focusId = child.id;
  const remote = structuredClone(original); remote.nodeData.children = [];
  store.replaceFromExternal(remote);
  assert.equal(store.node(child.id), null);
  assert.deepEqual(store.document.views.selectedIds, []);
  assert.equal(store.document.views.focusId, null);
  assert.equal(store.undo(), false);
  assert.equal(store.redo(), false);
  assert.deepEqual(store.document.nodeData.content, remote.nodeData.content);
});

test("drag infers the nearest parent in empty space and excludes the whole moving subtree", async () => {
  const { nearestParent } = await import("../src/mindmap/nodeDrag");
  const { doc, a, b, c } = fixture();
  const candidates = [
    { id: doc.nodeData.id, left: 0, top: 0, width: 100, height: 40 },
    { id: a.id, left: 200, top: 0, width: 100, height: 40 },
    { id: c.id, left: 400, top: 0, width: 100, height: 40 },
    { id: b.id, left: 400, top: 100, width: 100, height: 40 }
  ];
  assert.equal(nearestParent(doc.nodeData, a.id, 440, 50, candidates), b.id);
  assert.equal(nearestParent(doc.nodeData, a.id, 110, 20, candidates), doc.nodeData.id);
  assert.equal(nearestParent(doc.nodeData, doc.nodeData.id, 400, 100, candidates), null);
  assert.equal(nearestParent(doc.nodeData, a.id, 400, 100, []), null);
});
test("drag distance uses rich-text bounds consistently across zoom and downward layout", async () => {
  const { nearestParent } = await import("../src/mindmap/nodeDrag");
  const { doc, a, b, c } = fixture();
  const candidates = [
    { id: a.id, left: 0, top: 100, width: 400, height: 80 },
    { id: b.id, left: 300, top: 220, width: 80, height: 40 }
  ];
  for (const scale of [0.25, 1, 3]) {
    const scaled = candidates.map(rect => ({ id: rect.id, left: rect.left * scale, top: rect.top * scale, width: rect.width * scale, height: rect.height * scale }));
    assert.equal(nearestParent(doc.nodeData, c.id, 390 * scale, 185 * scale, scaled), a.id);
    assert.equal(nearestParent(doc.nodeData, c.id, 390 * scale, 215 * scale, scaled), b.id);
  }
});
test("drag reparenting keeps descendants and expands destination in a single undo step", () => {
  const { doc, a, b, c } = fixture(); b.expanded = false;
  const store = new DocumentStore(doc);
  store.change(document => { moveNodes(document.nodeData, [a.id], b.id, "inside"); });
  assert.equal(store.node(b.id)?.expanded, true);
  assert.equal(store.node(b.id)?.children[0].children[0].id, c.id);
  assert.equal(store.undo(), true);
  assert.deepEqual(store.document.nodeData.children.map(node => node.id), [a.id, b.id]);
  assert.equal(store.node(b.id)?.expanded, false);
  assert.equal(store.redo(), true);
  assert.equal(store.node(b.id)?.children[0].id, a.id);
});
