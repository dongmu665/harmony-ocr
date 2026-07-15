/**
 * ApiTypes 定义移动端网络层的统一响应、请求选项和错误对象。
 * 维护说明：错误对象只保存错误码、用户可读消息和 HTTP 状态码，不得携带 Token 或密码。
 */
export interface ApiResponse<T> {
  success: boolean;
  code: string;
  message: string;
  data?: T;
  timestamp?: string;
}

/**
 * RequestOptions 描述 HttpClient 的通用请求扩展项。
 * 维护说明：authorized 只表示由 TokenStorage 注入 Authorization；调用方不得把 Token 放进 query 或 body。
 */
export interface RequestOptions {
  headers?: HeaderOptions;
  query?: Record<string, string | number | boolean | undefined>;
  body?: object | string;
  authorized?: boolean;
}

/**
 * HeaderOptions 承载少量允许透传的请求头。
 * 安全边界：authorization 仅用于当前请求内存传递，不应被页面状态、日志或错误提示持久化。
 */
export interface HeaderOptions {
  contentType?: string;
  authorization?: string;
}

/**
 * ApiError 是前端网络层统一抛出的业务错误。
 * 维护说明：错误对象只保留脱敏错误码、提示文案和 HTTP 状态码，不携带原始响应体或敏感请求头。
 */
export class ApiError extends Error {
  readonly code: string;
  readonly statusCode?: number;

  constructor(code: string, message: string, statusCode?: number) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
  }
}
