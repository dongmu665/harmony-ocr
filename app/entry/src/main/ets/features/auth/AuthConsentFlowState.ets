import { AppRoutes } from '../../common/routes/AppRoutes';

/**
 * AuthConsentFlowState 保存登录前协议确认后的跳转目标。
 * 维护说明：这里只保存固定页面路由，不保存账号、密码、Token、API Key 或任何用户隐私数据。
 */
export class AuthConsentFlowState {
  private static targetRoute: string = AppRoutes.LOGIN;

  /**
   * 设置协议确认后的目标页面。
   * 参数 route 必须来自认证入口白名单，非法值会回退到登录页，避免外部输入控制页面跳转。
   */
  static setTarget(route: string): void {
    if (route === AppRoutes.REGISTER) {
      AuthConsentFlowState.targetRoute = AppRoutes.REGISTER;
      return;
    }
    AuthConsentFlowState.targetRoute = AppRoutes.LOGIN;
  }

  /**
   * 读取并消费协议确认目标。
   * 返回值只可能是 Login 或 Register，读取后恢复默认登录目标，避免后续流程误用旧状态。
   */
  static consumeTarget(): string {
    const route = AuthConsentFlowState.targetRoute;
    AuthConsentFlowState.targetRoute = AppRoutes.LOGIN;
    return route === AppRoutes.REGISTER ? AppRoutes.REGISTER : AppRoutes.LOGIN;
  }
}
