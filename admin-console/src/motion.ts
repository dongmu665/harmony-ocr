const REDUCED_MOTION_QUERY = "(prefers-reduced-motion: reduce)";

/** 判断当前系统是否要求减少动态效果。 */
export function prefersReducedMotion(): boolean {
  return window.matchMedia(REDUCED_MOTION_QUERY).matches;
}

/** 订阅动态效果偏好变化，并返回可重复调用的清理函数。 */
export function observeReducedMotion(listener: (reduced: boolean) => void): () => void {
  const media = window.matchMedia(REDUCED_MOTION_QUERY);
  const notify = () => listener(media.matches);
  media.addEventListener("change", notify);
  notify();
  return () => media.removeEventListener("change", notify);
}

/**
 * 在单个元素上启动 Web Animations 动画。
 * 减少动态效果开启时返回 null；取消动画产生的 rejected finished promise 会被内部消化。
 */
export function animateElement(
  element: Element | null,
  keyframes: Keyframe[],
  options: KeyframeAnimationOptions
): Animation | null {
  if (!element || prefersReducedMotion()) return null;
  const animation = element.animate(keyframes, { fill: "backwards", ...options });
  void animation.finished.catch(() => undefined);
  return animation;
}

/** 只在给定组件根节点内查询并按顺序启动动画。 */
export function animateScoped(
  root: ParentNode | null,
  selector: string,
  keyframes: Keyframe[] | ((element: Element, index: number) => Keyframe[]),
  options: KeyframeAnimationOptions,
  staggerMs = 0
): Animation[] {
  if (!root || prefersReducedMotion()) return [];
  return Array.from(root.querySelectorAll(selector)).flatMap((element, index) => {
    const frames = typeof keyframes === "function" ? keyframes(element, index) : keyframes;
    const animation = animateElement(element, frames, {
      ...options,
      delay: Number(options.delay ?? 0) + index * staggerMs
    });
    return animation ? [animation] : [];
  });
}

/** 统一取消 effect 创建的动画，供 React StrictMode 重放时清理。 */
export function cancelAnimations(animations: Iterable<Animation>): void {
  for (const animation of animations) animation.cancel();
}
