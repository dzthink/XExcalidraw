import { useEffect, useState } from "react";
import type { StructureAction } from "./document";
import ToolbarIcon, { type ToolbarIconName } from "./ToolbarIcon";

type Props = {
  selectedId: string; expanded: boolean; selection?: boolean;
  edit: () => void; action: (action: StructureAction) => void;
  focusNode: () => void; exitFocus?: () => void; dismiss: () => void;
};
export default function MobileNodeToolbar(props: Props) {
  const [more, setMore] = useState(false);
  useEffect(() => { setMore(false); }, [props.selectedId, props.selection]);
  const button = (label: string, icon: ToolbarIconName, action: () => void, caption?: string, destructive = false) => (
    <button type="button" aria-label={label} title={label} className={destructive ? "is-destructive" : undefined}
      onClick={() => { setMore(false); action(); }}>
      <ToolbarIcon name={icon} />{caption && <span>{caption}</span>}
    </button>
  );
  return <>
    {more && props.selection !== false && <div className="mindmap-mobile-menu-backdrop" aria-hidden="true"
      onPointerDown={event => { event.stopPropagation(); event.preventDefault(); }}
      onClick={event => { event.stopPropagation(); setMore(false); }} />}
    <div className={`mindmap-node-toolbar mindmap-mobile-node-toolbar${more ? " has-open-menu" : ""}`} role="toolbar" aria-label="节点操作栏"
    onPointerDown={event => { event.stopPropagation(); event.preventDefault(); }}>
    {props.selection === false ? props.exitFocus && button("返回完整导图", "undo", props.exitFocus, "返回完整导图") : <>
    <div className="mindmap-toolbar-actions">
      {button("编辑节点", "textStyle", props.edit, "编辑")}
      {button("添加子节点", "child", () => props.action("child"), "子节点")}
      {button("添加同级节点", "sibling", () => props.action("sibling"), "同级")}
      {button("折叠 / 展开", "fold", () => props.action("fold"), props.expanded ? "折叠" : "展开")}
      <button type="button" aria-label="更多节点操作" aria-expanded={more} onClick={() => setMore(value => !value)}>
        <ToolbarIcon name="more" /><span>更多</span>
      </button>
    </div>
    {button("取消选中", "close", props.dismiss)}
    {more && <div className="mindmap-toolbar-panel" role="group" aria-label="更多节点操作">
      <div className="mindmap-mobile-node-more">
        {props.exitFocus ? button("返回完整导图", "undo", props.exitFocus, "返回完整导图")
          : button("进入此节点", "focus", props.focusNode, "进入此节点")}
        {button("删除节点", "trash", () => props.action("delete"), "删除节点", true)}
      </div>
    </div>}
    </>}
  </div></>;
}
