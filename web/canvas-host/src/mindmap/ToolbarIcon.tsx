import type { ReactNode } from "react";

const paths = {
  quote: "M10 7H5v6h5V7Zm9 0h-5v6h5V7ZM10 13c0 4-2 5-5 5m14-5c0 4-2 5-5 5",
  bullet: "M9 6h12M9 12h12M9 18h12M3 6h.01M3 12h.01M3 18h.01",
  ordered: "M10 6h11M10 12h11M10 18h11M3 3h1v5M3 8h3M3 11c3-2 4 1 1 3l-1 1h3M3 18h2l-1 2c3 0 2 3-1 2",
  dash: "M10 6h11M10 12h11M10 18h11M3 6h3M3 12h3M3 18h3",
  outdent: "M10 5h11M10 10h11M10 15h11M3 20h18M6 7l-3 3 3 3",
  indent: "M10 5h11M10 10h11M10 15h11M3 20h18M3 7l3 3-3 3",
  inlineCode: "M8 7l-5 5 5 5m8-10 5 5-5 5m-3-13-2 16",
  codeBlock: "M4 3h16v18H4V3Zm0 5h16M9 12l-3 3 3 3m6-6 3 3-3 3",
  table: "M3 4h18v16H3V4Zm0 5h18M3 14h18M9 4v16M15 4v16",
  addRow: "M3 3h14v10H3V3Zm0 5h14M8 3v10M5 18h14m-7-4v8",
  addColumn: "M3 3h10v14H3V3Zm5 0v14M3 8h10m2 4h7m-4-7h8",
  deleteRow: "M3 3h14v10H3V3Zm0 5h14M8 3v10M5 18h14",
  deleteColumn: "M3 3h10v14H3V3Zm5 0v14M3 8h10m2 4h7",
  trash: "M3 6h18M9 6V3h6v3M5 6l1 15h12l1-15M10 10v7M14 10v7",
  link: "M10 13a5 5 0 0 0 7 0l3-3a5 5 0 0 0-7-7l-2 2M14 11a5 5 0 0 0-7 0l-3 3a5 5 0 0 0 7 7l2-2",
  unlink: "M8 14l-2 2a3 3 0 0 0 4 4l2-2M16 10l2-2a3 3 0 0 0-4-4l-2 2M3 3l18 18",
  check: "M4 12l5 5L20 6",
  close: "M6 6l12 12M6 18 18 6",
  plus: "M12 5v14M5 12h14",
  minus: "M5 12h14",
  sibling: "M3 5h7v6H3V5Zm0 12h7v5H3v-5ZM6 11v6M17 4v10m-5-5h10",
  child: "M3 3h8v6H3V3Zm4 6v9h6m5-5v10m-5-5h10",
  fold: "M8 3l4 4 4-4M8 21l4-4 4 4M4 12h16",
  focus: "M9 3H3v6m12-6h6v6M3 15v6h6m12-6v6h-6M9 12h6m-3-3v6",
  smaller: "M4 4l6 6M5 10h5V5m10 15-6-6m5 0h-5v5",
  larger: "M9 4H4v5m11 11h5v-5M10 10 4 4m10 10 6 6",
} as const;
export type ToolbarIconName = keyof typeof paths | "paragraph" | "h1" | "h2" | "h3" | "bold" | "italic" | "strike";

export default function ToolbarIcon({ name }: { name: ToolbarIconName }) {
  let content: ReactNode;
  if (name in paths) {
    content = <path d={paths[name as keyof typeof paths]} />;
  } else {
    const glyph = { paragraph: "¶", h1: "H₁", h2: "H₂", h3: "H₃", bold: "B", italic: "I", strike: "S" }[name as "paragraph" | "h1" | "h2" | "h3" | "bold" | "italic" | "strike"];
    content = <><text x="12" y="17" textAnchor="middle" fill="currentColor" stroke="none" fontFamily={name === "italic" ? "Georgia,serif" : "-apple-system,sans-serif"} fontSize="19" fontWeight={name === "bold" ? "750" : "550"} fontStyle={name === "italic" ? "italic" : undefined}>{glyph}</text>{name === "strike" && <path d="M4 12h16" />}</>;
  }
  return <svg className="mindmap-toolbar-icon" viewBox="0 0 24 24" width="24" height="24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false">{content}</svg>;
}
