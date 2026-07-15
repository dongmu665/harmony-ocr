/**
 * AuthModels 定义前端认证链路使用的数据结构。
 * 维护说明：模型字段严格对齐当前后端 DTO；不得新增会导致后端忽略的敏感字段。
 */
export interface RegisterRequest {
  username: string;
  password: string;
  nickname?: string;
}

/**
 * LoginRequest 是用户名密码登录请求。
 * 安全边界：password 只在请求体中短暂传递，页面状态和日志不得保存明文密码。
 */
export interface LoginRequest {
  username: string;
  password: string;
  deviceId?: string;
  deviceName?: string;
}

/**
 * RefreshTokenRequest 用于刷新访问令牌。
 * 维护说明：refreshToken 必须来自 TokenStorage，不允许从 UI 输入或普通缓存读取。
 */
export interface RefreshTokenRequest {
  refreshToken: string;
}

/**
 * LogoutRequest 用于服务端吊销当前刷新令牌。
 * 安全边界：退出登录后还必须清理本地 TokenStorage，不能只依赖后端状态。
 */
export interface LogoutRequest {
  refreshToken: string;
}

/**
 * AuthTokenResponse 表示认证成功后的会话数据。
 * 安全边界：accessToken/refreshToken 只能交给 TokenStorage 保存，不应透传给普通页面组件。
 */
export interface AuthTokenResponse {
  accessToken: string;
  refreshToken: string;
  tokenType: string;
  expiresIn: number;
  user: CurrentUser;
}

/**
 * CurrentUser 是前端可展示的当前用户脱敏资料。
 * 维护说明：该模型不包含密码哈希、Token、删除标记细节或后台权限判断之外的敏感字段。
 */
export interface CurrentUser {
  id: number;
  username: string;
  nickname?: string;
  avatarUrl?: string;
  status?: string;
  createdAt?: string;
  lastLoginAt?: string;
}
