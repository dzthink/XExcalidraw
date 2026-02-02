interface Window {
  webkit?: {
    messageHandlers?: {
      bridge?: {
        postMessage: (message: string) => void;
      };
    };
  };
}
