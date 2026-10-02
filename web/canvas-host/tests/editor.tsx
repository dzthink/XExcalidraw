// Standalone development fixture: never reads or writes native documents.
import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import type MindElixir from "mind-elixir";
import MindMapEditor from "../src/MindMapEditor";
import { initializeBridge } from "../src/bridge";
import { newDocument, newNode } from "../src/mindmap/document";
initializeBridge();
const initial = newDocument(); initial.nodeData.content={type:"doc",content:[{type:"paragraph",content:[{type:"text",text:"投放 Agent"}]}]};
const architecture=newNode("架构"),levels=newNode("投放 agent 的五个层次"); architecture.note="test"; levels.children=["runtime 基础能力","执行特定任务的原子 agent","多个 agent 组成 team 模式","多个 team 服务特定产品、目标投放","全自动运转"].map(newNode); architecture.children=[levels,newNode("稳定运行"),newNode("事件")];
initial.nodeData.children=[architecture,newNode("skills 管理平台"),newNode("PMF 产品设计"),newNode("desktop")]; initial.nodeData.children[1].children=[newNode("cli")]; const north=newNode("北极星"); north.note="消耗渗透率：从成都代投开始"; initial.nodeData.children[2].children=[north];
let failSave = false;
let testMap: MindElixir | null = null;
window.addEventListener("message",event=>{if(typeof event.data!=="string")return;const message=JSON.parse(event.data);if(message.type==="saveScene"){if(failSave){window.postMessage({version:"1.0",type:"saveResult",payload:{requestId:message.payload.requestId,success:false,error:"测试保存失败"}},"*");return;}localStorage.setItem("siye-qa",message.payload.sceneJson);window.postMessage({version:"1.0",type:"saveResult",payload:{requestId:message.payload.requestId,success:true}},"*");}});
function QA(){const [theme,setTheme]=useState<"light"|"dark">("light");const [readOnly,setReadOnly]=useState(false);return <div style={{height:"100vh"}}><div style={{position:"absolute",bottom:3,left:5,zIndex:40}}><button onClick={()=>{failSave=!failSave}}>切换保存失败</button><button onClick={()=>{localStorage.removeItem("siye-qa");location.reload()}}>重置测试</button><button onClick={()=>{if(!testMap)return;const topic=testMap.nodes.querySelector("me-tpc"),before=testMap.scaleVal;const started=performance.now();for(let i=0;i<100;i++)testMap.container.dispatchEvent(new WheelEvent("wheel",{deltaY:i%2===0?-10:8,metaKey:true,bubbles:true,cancelable:true}));document.getElementById("native-result")!.textContent=`原生缩放 ${testMap.scaleVal!==before && topic===testMap.nodes.querySelector("me-tpc") ? "通过" : "失败"}，100 次滚轮 ${Math.round(performance.now()-started)}ms`}}>验证原生缩放</button><span id="native-result"/><button onClick={()=>setTheme(theme==="light"?"dark":"light")}>测试主题</button><button onClick={()=>setReadOnly(!readOnly)}>测试只读</button></div><MindMapEditor docId="qa.mindmap" data={JSON.parse(localStorage.getItem("siye-qa")||JSON.stringify(initial))} readOnly={readOnly} theme={theme} onReady={instance=>{testMap=instance}} /></div>}
createRoot(document.getElementById("root")!).render(<QA/>);
