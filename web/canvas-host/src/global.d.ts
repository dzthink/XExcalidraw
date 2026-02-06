interface Window {
  __XEXCALIDRAW_THEME?: "light" | "dark";
  webkit?: {
    messageHandlers?: {
      bridge?: {
        postMessage: (message: string) => void;
      };
    };
  };
}
