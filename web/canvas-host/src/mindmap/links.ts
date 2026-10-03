import type MindElixir from "mind-elixir";
import type { Topic, Wrapper, SubLineParams } from "mind-elixir";

type Box = { top: number; left: number; width: number; height: number };
type Path = { d: string; color: string };
const namespace = "http://www.w3.org/2000/svg";

const box = (element: HTMLElement): Box => ({ top: element.offsetTop, left: element.offsetLeft, width: element.offsetWidth, height: element.offsetHeight });
const relativeBox = (element: HTMLElement, container: HTMLElement): Box => {
  const result = box(element);
  for (let parent = element.offsetParent as HTMLElement | null; parent && parent !== container; parent = parent.offsetParent as HTMLElement | null) {
    result.top += parent.offsetTop; result.left += parent.offsetLeft;
  }
  return result;
};
function writePaths(svg: SVGElement, paths: Path[], width: string) {
  const fragment = document.createDocumentFragment();
  for (const path of paths) {
    const element = document.createElementNS(namespace, "path");
    element.setAttribute("d", path.d); element.setAttribute("stroke", path.color);
    element.setAttribute("stroke-width", width); element.setAttribute("fill", "none");
    fragment.append(element);
  }
  svg.replaceChildren(fragment);
}

/** Host rich text changes node sizes outside the library's plain-text editor.
 * Read all geometry before writing SVG, using the library's public curve generators.
 * Structure changes still use MindElixir.refresh() and its normal renderer.
 */
export function refreshRichTextLinks(instance: MindElixir, branches: Set<Wrapper> | null) {
  if (instance.arrows.length || instance.summaries.length) { instance.linkDiv(); return; }
  const root = instance.nodes.querySelector<HTMLElement>("me-root");
  if (!root) return;
  const parent = box(root), containerHeight = instance.nodes.offsetHeight, containerWidth = instance.nodes.offsetWidth;
  const mainPaths: Path[] = [];
  const subPlans: { wrapper: Wrapper; paths: Path[] }[] = [];
  const wrappers = instance.nodes.querySelectorAll<Wrapper>("me-main > me-wrapper");
  wrappers.forEach((wrapper, index) => {
    const topic = wrapper.querySelector<Topic>("me-tpc");
    if (!topic) return;
    const child = relativeBox(topic, instance.nodes);
    const direction = wrapper.parentElement!.className as SubLineParams["direction"];
    const color = topic.nodeObj.branchColor || instance.theme.palette[index % instance.theme.palette.length];
    mainPaths.push({ color, d: instance.generateMainBranch({ pT: parent.top, pL: parent.left, pW: parent.width, pH: parent.height, cT: child.top, cL: child.left, cW: child.width, cH: child.height, direction, containerHeight, containerWidth }) });
    if (branches && !branches.has(wrapper)) return;
    const paths: Path[] = [];
    const visit = (item: Wrapper, branchColor: string, isFirst: boolean) => {
      const parentElement = item.firstElementChild as HTMLElement;
      const children = item.children[1]?.children;
      if (!parentElement || !children?.length) return;
      const p = box(parentElement);
      for (const childWrapper of children) {
        const childElement = childWrapper.firstElementChild as HTMLElement;
        const childTopic = childElement.firstElementChild as Topic;
        const c = box(childElement), color = childTopic.nodeObj.branchColor || branchColor;
        paths.push({ color, d: instance.generateSubBranch({ pT: p.top, pL: p.left, pW: p.width, pH: p.height, cT: c.top, cL: c.left, cW: c.width, cH: c.height, direction, isFirst }) });
        const expander = childElement.children[1] as (HTMLElement & { expanded?: boolean }) | undefined;
        if (expander?.expanded) visit(childWrapper as Wrapper, color, false);
      }
    };
    visit(wrapper, color, true);
    subPlans.push({ wrapper, paths });
  });
  // No layout reads below this point. Preserve the library's SVG containers.
  writePaths(instance.lines, mainPaths, "3");
  for (const plan of subPlans) {
    let svg = plan.wrapper.querySelector<SVGElement>(":scope > svg.subLines");
    if (!svg) { svg = document.createElementNS(namespace, "svg"); svg.classList.add("subLines"); svg.setAttribute("overflow", "visible"); plan.wrapper.append(svg); }
    writePaths(svg, plan.paths, "2");
  }
}
