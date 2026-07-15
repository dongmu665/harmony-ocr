import { HttpClient } from '../../common/network/HttpClient';
import { ApiError } from '../../common/network/ApiTypes';
import { TokenStorage } from '../../common/storage/TokenStorage';
import {
  AuthTokenResponse,
  CurrentUser,
  LoginRequest,
  LogoutRequest,
  RefreshTokenRequest,
  RegisterRequest
} from './AuthModels';

/**
 * AuthService 封装前端认证 API 调用，属于 auth 功能模块。
 * 维护说明：服务层负责 Token 保存和清理，不在日志、UI 或异常中暴露 Token、密码和 Refresh Token。
 */
export class AuthService {
  /**
   * 注册新用户。
   * 参数为用户名、密码和可选昵称；当前后端返回用户资料而不是 Token，因此注册成功后引导用户登录。
   */
  static async register(request: RegisterRequest): Promise<CurrentUser> {
    return HttpClient.post<CurrentUser>('/auth/register', request);
  }

  /**
   * 使用用户名密码登录并保存 Token。
   * 参数 deviceId/deviceName 用于后端记录设备；返回值包含 Token 和当前用户资料。
   */
  static async login(request: LoginRequest): Promise<AuthTokenResponse> {
    const tokens = await HttpClient.post<AuthTokenResponse>('/auth/login', request);
    await TokenStorage.saveTokens(tokens.accessToken, tokens.refreshToken);
    return tokens;
  }

  /**
   * 使用 Refresh Token 刷新会话。
   * 参数可显式传入；未传入时读取本地 Token，若为空则直接抛出需要重新登录的错误。
   */
  static async refresh(refreshToken?: string): Promise<AuthTokenResponse> {
    const tokenForRefresh = refreshToken ?? await TokenStorage.getRefreshToken();
    if (tokenForRefresh.length === 0) {
      await TokenStorage.clearTokens();
      throw new ApiError('AUTH_REFRESH_TOKEN_MISSING', '登录状态已失效，请重新登录');
    }
    const request: RefreshTokenRequest = { refreshToken: tokenForRefresh };
    const tokens = await HttpClient.post<AuthTokenResponse>('/auth/refresh', request);
    await TokenStorage.saveTokens(tokens.accessToken, tokens.refreshToken);
    return tokens;
  }

  /**
   * 退出登录并清理本地 Token。
   * 安全注意：即使网络请求失败，也必须清理本地 Token，避免用户主动退出后仍保留会话。
   */
  static async logout(): Promise<void> {
    const refreshToken = await TokenStorage.getRefreshToken();
    try {
      if (refreshToken.length > 0) {
        const request: LogoutRequest = { refreshToken };
        await HttpClient.post<void>('/auth/logout', request, { authorized: true });
      }
    } finally {
      await TokenStorage.clearTokens();
    }
  }

  /**
   * 获取当前登录用户资料。
   * 返回值来自受保护接口；401 时由 HttpClient 清理本地 Token 并抛出错误。
   */
  static async getCurrentUser(): Promise<CurrentUser> {
    return HttpClient.get<CurrentUser>('/users/me', { authorized: true });
  }

  /**
   * 注销当前账号。
   * 安全注意：后端完成当前用户数据删除或匿名化后，本地 Token 必须立即清理。
   */
  static async deleteAccount(): Promise<void> {
    await HttpClient.delete<void>('/users/me', { authorized: true });
    await TokenStorage.clearTokens();
  }
}
