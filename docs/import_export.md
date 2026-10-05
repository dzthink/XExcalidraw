# Import and export

macOS has Import and Export controls in the window toolbar. iOS has Import in the document browser and Export in the editor. Choose a library folder before importing. Import saves an editable document in the active library, opens it, and adds a numeric suffix when the name already exists.

| Format | Import | Export | Content |
| --- | --- | --- | --- |
| Siye `.mindmap` | Yes | Yes | Native rich text, tree, settings and view state |
| XMind `.xmind` | Modern JSON and legacy XML ZIPs | Modern JSON ZIP | Topic hierarchy, plain text, notes and folding |
| FreeMind / Freeplane `.mm` | Yes | Yes | Topic hierarchy, plain text, notes and folding |
| OPML `.opml` | Yes | Yes | Topic hierarchy, plain text and notes |
| HTML `.html` | No | Yes | Mind maps include switchable outline and map views; drawings embed SVG |
| PNG `.png` | Embedded Excalidraw scene in `.excalidraw.png` | Yes | Rendered image |
| SVG `.svg` | Embedded Excalidraw scene in `.excalidraw.svg` | Yes | Rendered vector image |
| Excalidraw / JSON | Yes | Yes | Drawing elements, app state and image files; Siye JSON is recognized on import |

HTML is standalone and supports offline reading. Mind-map images are embedded as data URLs. HTML retains outline/map switching, with zoom and fit controls for the map. All outline branches are included and can be folded in the browser. PNG and SVG use the rendered map, including its current folding state; export also works from outline mode.

All XMind sheets are retained. Multiple roots become children of a root named after the imported file. Attached and floating topics are imported as tree children. External layouts, styling, relationships, task metadata and image attachments are not converted by the XMind/MM/OPML adapters. Quote blocks become plain-text notes on export. Native `.mindmap` retains rich content and attachment references; its external attachment files must travel with it when moving libraries.

Malformed archives and XML are rejected. XMind import supports stored/Deflate ZIP entries, checks sizes and CRCs, and does not support encrypted or ZIP64 archives. Import files are limited to 64 MiB and individual XMind content entries to 32 MiB. Editable trees are limited to 100 levels of nesting.

Protocol: `requestExport` accepts `html`, `png`, `svg`, `json`, `mindmap`, `xmind`, `mm` and `opml`. `exportResult` returns the requested format and base64 bytes; `exportFailed` returns an error string. Native actions flush pending editing before transfer. iOS uses the share sheet and macOS uses its save panel.

Format references: [XMind model](https://github.com/xmindltd/xmind-model/blob/master/schemas/topic.json), [XMind SDK](https://github.com/xmindltd/xmind-sdk-js), [FreeMind format](https://freemind.sourceforge.io/wiki/index.php/File_format), [OPML 2.0](https://opml.org/spec2.opml).
