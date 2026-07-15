import { UIContext } from '@kit.ArkUI';

/**
 * AppNavigator 统一封装应用内页面跳转。
 * 维护说明：只处理固定应用内路由，不记录 URL 参数、Token、账号、OCR 文本或其他业务数据。
 */
export class AppNavigator {
  private static lastFailureMessage: string = '';

  /**
   * 使用 push 语义进入目标页面，保留当前页面用于返回。
   * @param context 当前 ArkUI 组件上下文。
   * @param url 来自 AppRoutes 的应用内页面路径。
   */
  static push(context: UIContext, url: string): void {
    try {
      context.getRouter().pushUrl({ url: url }).catch(() => {
        AppNavigator.recordFailure('页面跳转失败，请稍后重试');
      });
    } catch (_) {
      AppNavigator.recordFailure('页面跳转失败，请稍后重试');
    }
  }

  /**
   * 使用 replace 语义替换当前页面，保留更早的页面栈。
   * @param context 当前 ArkUI 组件上下文。
   * @param url 来自 AppRoutes 的应用内页面路径。
   */
  static replace(context: UIContext, url: string): void {
    try {
      context.getRouter().replaceUrl({ url: url }).catch(() => {
        AppNavigator.recordFailure('页面切换失败，请稍后重试');
      });
    } catch (_) {
      AppNavigator.recordFailure('页面切换失败，请稍后重试');
    }
  }

  /**
   * 优先按页面栈返回上一页；没有可返回页面或返回异常时，使用固定路由兜底。
   * 维护说明：这里只读取栈长度，不记录来源路由、页面参数、Token、账号或 OCR 文本。
   * @param context 当前 ArkUI 组件上下文。
   * @param fallbackRoute 页面栈不可用时的应用内兜底路由。
   */
  static back(context: UIContext, fallbackRoute: string): void {
    try {
      const router = context.getRouter();
      const pageStackLength = Number(router.getLength());
      if (pageStackLength > 1) {
        router.back();
        return;
      }
    } catch (_) {
      AppNavigator.recordFailure('页面返回失败，请稍后重试');
    }
    AppNavigator.replace(context, fallbackRoute);
  }

  /**
   * 进入一级业务页面时清理历史页面栈，避免登录页残留在已认证主界面后方。
   * @param context 当前 ArkUI 组件上下文。
   * @param url 来自 AppRoutes 的一级业务页面路径。
   */
  static replaceRoot(context: UIContext, url: string): void {
    try {
      context.getRouter().clear();
      context.getRouter().pushUrl({ url: url }).catch(() => {
        AppNavigator.recordFailure('页面切换失败，请稍后重试');
      });
    } catch (_) {
      AppNavigator.recordFailure('页面切换失败，请稍后重试');
    }
  }

  /**
   * 读取最近一次路由失败的非敏感提示。
   * @returns 固定用户提示文案，不包含 URL、页面参数、Token 或业务数据。
   */
  static getLastFailureMessage(): string {
    return AppNavigator.lastFailureMessage;
  }

  /**
   * 记录路由失败的非敏感状态。
   * @param message 固定用户提示文案，不能包含具体路由、参数或业务上下文。
   */
  private static recordFailure(message: string): void {
    AppNavigator.lastFailureMessage = message;
  }
}
