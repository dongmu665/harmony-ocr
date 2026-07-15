import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../config/ApiConfig';
import { ApiError, ApiResponse, RequestOptions } from './ApiTypes';
import { TokenStorage } from '../storage/TokenStorage';

/**
 * RequestHeaders 限定 HttpClient 允许设置的请求头。
 * 安全边界：Authorization 只在请求生命周期内存在，不能被序列化到页面状态或日志。
 */
interface RequestHeaders {
  Authorization?: string;
  'Content-Type'?: string;
}

/**
 * HttpClient 统一处理后端 API 前缀、JSON 编解码、Authorization 头和统一响应结构。
 * 安全约束：不打印 Authorization、Refresh Token、OCR 文本等隐私敏感内容。
 */
export class HttpClient {
  /**
   * 发起 GET 请求。
   * 参数 path 为不含 /api/v1 前缀的资源路径；返回值为统一 Result.data。
   */
  static async get<T>(path: string, options: RequestOptions = {}): Promise<T> {
    return HttpClient.request<T>('GET', path, options);
  }

  /**
   * 下载受保护接口返回的二进制文件。
   * 安全边界：仅复用授权头，不解析、不记录响应内容；调用方负责写入受控缓存目录并展示脱敏元数据。
   */
  static async getBytes(path: string, options: RequestOptions = {}): Promise<ArrayBuffer> {
    const request = http.createHttp();
    const url = `${ApiConfig.BASE_URL}${ApiConfig.API_PREFIX}${path}${HttpClient.toQueryString(options.query)}`;
    const headers: RequestHeaders = { 'Content-Type': 'application/json' };
    if (options.headers?.authorization !== undefined) {
      headers.Authorization = options.headers.authorization;
    }
    if (options.authorized) {
      const accessToken = await TokenStorage.getAccessToken();
      if (accessToken.length > 0) {
        headers.Authorization = `Bearer ${accessToken}`;
      }
    }
    try {
      const response = await request.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        connectTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        readTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        if (response.responseCode === 401) {
          await TokenStorage.clearTokens();
        }
        throw new ApiError('DOWNLOAD_FAILED', '导出文件下载失败', response.responseCode);
      }
      if (response.result instanceof ArrayBuffer) {
        return response.result;
      }
      throw new ApiError('INVALID_RESPONSE', '导出文件响应不是二进制内容', response.responseCode);
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError('NETWORK_ERROR', '网络请求失败，请稍后重试', 0);
    } finally {
      request.destroy();
    }
  }

  /**
   * 发起 POST 请求。
   * 参数 body 会被序列化为 JSON；调用方不得把 Token 放入自定义日志字段。
   */
  static async post<T>(path: string, body?: object | string, options: RequestOptions = {}): Promise<T> {
    options.body = body;
    return HttpClient.request<T>('POST', path, options);
  }

  /**
   * 发起 PATCH 请求。
   * 参数 body 使用 JSON 编码；调用方只传业务字段，不传 Token、Refresh Token 或本地文件路径。
   */
  static async patch<T>(path: string, body?: object, options: RequestOptions = {}): Promise<T> {
    options.body = body;
    return HttpClient.request<T>('PATCH', path, options);
  }

  /**
   * 发起 DELETE 请求。
   * 安全边界：所有受保护删除操作仍由后端按当前用户做 ownership 校验。
   */
  static async delete<T>(path: string, options: RequestOptions = {}): Promise<T> {
    return HttpClient.request<T>('DELETE', path, options);
  }

  private static async request<T>(method: string, path: string, options: RequestOptions): Promise<T> {
    const request = http.createHttp();
    const url = `${ApiConfig.BASE_URL}${ApiConfig.API_PREFIX}${path}${HttpClient.toQueryString(options.query)}`;
    const headers: RequestHeaders = { 'Content-Type': 'application/json' };
    if (options.headers?.authorization !== undefined) {
      headers.Authorization = options.headers.authorization;
    }

    if (options.authorized) {
      const accessToken = await TokenStorage.getAccessToken();
      if (accessToken.length > 0) {
        headers.Authorization = `Bearer ${accessToken}`;
      }
    }

    try {
      const extraData = HttpClient.toRequestBody(options.body);
      const response = await request.request(url, {
        method: HttpClient.toHttpMethod(method),
        header: headers,
        connectTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        readTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        extraData: extraData
      });
      return await HttpClient.parseResponse<T>(response.responseCode, HttpClient.responseToString(response.result));
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError('NETWORK_ERROR', '网络请求失败，请稍后重试', 0);
    } finally {
      request.destroy();
    }
  }

  /**
   * 解析后端统一 Result 响应。
   * 安全注意：401 只清理本地 Token 并抛出用户可读错误，不输出 Authorization 或 Refresh Token。
   */
  private static async parseResponse<T>(statusCode: number, rawBody: string): Promise<T> {
    let apiResponse: ApiResponse<T>;
    try {
      apiResponse = JSON.parse(rawBody) as ApiResponse<T>;
    } catch (_) {
      if (statusCode === 401) {
        await TokenStorage.clearTokens();
      }
      throw new ApiError('INVALID_RESPONSE', '后端响应格式不是合法 JSON', statusCode);
    }

    if (!apiResponse.success) {
      if (statusCode === 401) {
        await TokenStorage.clearTokens();
      }
      throw new ApiError(apiResponse.code, apiResponse.message, statusCode);
    }

    return apiResponse.data as T;
  }

  private static toRequestBody(body?: object | string): string | undefined {
    if (body === undefined) {
      return undefined;
    }
    if (typeof body === 'string') {
      return body;
    }
    try {
      return JSON.stringify(body);
    } catch (_) {
      throw new ApiError('INVALID_REQUEST_BODY', '请求体序列化失败', 0);
    }
  }

  private static responseToString(result: string | Object | ArrayBuffer): string {
    if (typeof result === 'string') {
      return result;
    }
    if (result instanceof ArrayBuffer) {
      return '';
    }
    try {
      return JSON.stringify(result);
    } catch (_) {
      return '';
    }
  }

  private static toQueryString(query?: Record<string, string | number | boolean | undefined>): string {
    if (!query) {
      return '';
    }
    const params: string[] = [];
    Object.keys(query).forEach((key: string) => {
      const value = query[key];
      if (value !== undefined) {
        params.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
      }
    });
    return params.length === 0 ? '' : `?${params.join('&')}`;
  }

  private static toHttpMethod(method: string): http.RequestMethod {
    switch (method) {
      case 'GET':
        return http.RequestMethod.GET;
      case 'POST':
        return http.RequestMethod.POST;
      case 'PATCH':
        return 'PATCH' as http.RequestMethod;
      case 'DELETE':
        return http.RequestMethod.DELETE;
      default:
        return http.RequestMethod.GET;
    }
  }
}
