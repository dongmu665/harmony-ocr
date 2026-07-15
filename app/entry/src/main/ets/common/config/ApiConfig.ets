/**
 * ApiConfig 集中维护前端访问后端 API 的基础配置。
 * 维护说明：这里只允许保存开发环境地址、API 前缀和超时时间，不得写入生产密钥或用户凭据。
 */
export class ApiConfig {
  static readonly BASE_URL: string = 'http://127.0.0.1:8080';
  static readonly API_PREFIX: string = '/api/v1';
  static readonly REQUEST_TIMEOUT_MS: number = 15000;
}
