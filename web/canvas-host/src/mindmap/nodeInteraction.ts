export function allowsNodeLongPress(mode: "outline" | "map", editingId: string | null, nodeId: string | null, readOnly: boolean): boolean {
  return mode === "map" && !readOnly && nodeId !== null && nodeId !== editingId;
}
