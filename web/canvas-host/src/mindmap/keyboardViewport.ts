declare global {
  interface Window {
    siyeNativeKeyboardAccessory?: boolean;
    siyeNativeKeyboardVisible?: boolean;
    siyeNativeKeyboardTop?: number;
  }
}

/** All coordinates are CSS pixels in the layout viewport. */
export function keyboardViewport(hostBottom: number, layoutHeight: number, viewportHeight: number, offsetTop: number, expandedHeight: number) {
  const visibleBottom = Math.min(layoutHeight, offsetTop + viewportHeight);
  return {
    inset: Math.max(0, hostBottom - visibleBottom),
    open: expandedHeight - viewportHeight > 80,
  };
}

export function trackKeyboardViewport(host: HTMLElement): () => void {
  const viewport = window.visualViewport;
  let expandedHeight = viewport?.height ?? window.innerHeight;
  let frame = 0;
  const update = () => {
    const height = viewport?.height ?? window.innerHeight;
    const focused = document.activeElement instanceof HTMLElement && host.contains(document.activeElement)
      && document.activeElement.matches('input, textarea, [contenteditable="true"]');
    if (!focused) expandedHeight = Math.max(expandedHeight, height);
    const geometry = keyboardViewport(host.getBoundingClientRect().bottom, window.innerHeight, height, viewport?.offsetTop ?? 0, expandedHeight);
    const nativeVisible = window.siyeNativeKeyboardAccessory && window.siyeNativeKeyboardVisible;
    const visibleBottom = nativeVisible && window.siyeNativeKeyboardTop !== undefined
      ? window.siyeNativeKeyboardTop : Math.min(window.innerHeight, (viewport?.offsetTop ?? 0) + height);
    const inset = nativeVisible ? Math.max(0, host.getBoundingClientRect().bottom - visibleBottom) : geometry.inset;
    host.style.setProperty("--keyboard-inset", `${inset}px`);
    window.dispatchEvent(new CustomEvent("siye-visible-editor-area", { detail: { bottom: visibleBottom } }));
    host.dataset.nativeKeyboard = String(Boolean(window.siyeNativeKeyboardAccessory));
    host.dataset.keyboardOpen = String(window.siyeNativeKeyboardAccessory ? Boolean(nativeVisible) : geometry.open);
  };
  const schedule = () => { cancelAnimationFrame(frame); frame = requestAnimationFrame(update); };
  const orientation = () => { expandedHeight = viewport?.height ?? window.innerHeight; schedule(); };
  viewport?.addEventListener("resize", schedule);
  viewport?.addEventListener("scroll", schedule);
  window.addEventListener("resize", schedule);
  window.addEventListener("siye-native-keyboard", schedule);
  window.addEventListener("orientationchange", orientation);
  host.addEventListener("focusin", schedule);
  host.addEventListener("focusout", schedule);
  const observer = new ResizeObserver(schedule);
  observer.observe(host);
  update();
  return () => {
    cancelAnimationFrame(frame); observer.disconnect();
    viewport?.removeEventListener("resize", schedule);
    viewport?.removeEventListener("scroll", schedule);
    window.removeEventListener("resize", schedule);
    window.removeEventListener("siye-native-keyboard", schedule);
    window.removeEventListener("orientationchange", orientation);
    host.removeEventListener("focusin", schedule);
    host.removeEventListener("focusout", schedule);
  };
}
