import { HttpClient } from '../../common/network/HttpClient';
import {
  CreateRecordRequest,
  FavoriteRecordRequest,
  RecordPageResult,
  RecordQuery,
  RecordResponse,
  UpdateRecordRequest
} from './RecordModels';

/**
 * RecordService 封装前端 records API 调用，属于 features/record 模块。
 * 维护说明：服务只复用 HttpClient，不直接读取 Token、不拼接 Authorization Header，也不输出 OCR 全文。
 */
export class RecordService {
  /**
   * 创建当前登录用户的 OCR 历史记录。
   * 参数 request 必须使用后端字段名；返回值为后端记录详情。401 由 HttpClient 清理 Token 并抛出错误。
   */
  static async createRecord(request: CreateRecordRequest): Promise<RecordResponse> {
    return HttpClient.post<RecordResponse>('/records', request, { authorized: true });
  }

  /**
   * 分页查询当前登录用户的历史记录。
   * 参数 query 使用后端当前实现的 page/size/favorite/sourceType/keyword；page 为 0-based。
   */
  static async listRecords(query: RecordQuery = {}): Promise<RecordPageResult<RecordResponse>> {
    return HttpClient.get<RecordPageResult<RecordResponse>>(`/records${RecordService.toQueryString(query)}`, {
      authorized: true
    });
  }

  /**
   * 查询当前用户拥有的单条历史记录详情。
   * 参数 id 来自列表或保存结果；越权访问由后端按 NOT_FOUND/UNAUTHORIZED 拦截。
   */
  static async getRecordDetail(id: string): Promise<RecordResponse> {
    return HttpClient.get<RecordResponse>(`/records/${encodeURIComponent(id)}`, { authorized: true });
  }

  /**
   * 更新当前用户拥有的历史记录。
   * 安全边界：只提交允许编辑的字段，后端负责 ownership 与软删除状态校验。
   */
  static async updateRecord(id: string, request: UpdateRecordRequest): Promise<RecordResponse> {
    // HarmonyOS 模拟器 HTTP SDK 对 PATCH 的兼容性不稳定，记录编辑改走后端同语义 POST 兼容入口。
    return HttpClient.post<RecordResponse>(
      `/records/${encodeURIComponent(id)}/update`,
      JSON.stringify(request),
      { authorized: true }
    );
  }

  /**
   * 软删除当前用户拥有的历史记录。
   * 维护说明：前端只调用删除 API，不直接删除 MinIO 对象或本地缓存中的历史正文。
   */
  static async deleteRecord(id: string): Promise<void> {
    return HttpClient.delete<void>(`/records/${encodeURIComponent(id)}`, { authorized: true });
  }

  /**
   * 更新当前用户记录的收藏状态。
   * 参数 favorite 为目标状态；重复点击由后端幂等处理。
   */
  static async updateFavorite(id: string, favorite: boolean): Promise<RecordResponse> {
    const request: FavoriteRecordRequest = { favorite: favorite };
    // HarmonyOS HTTP SDK 当前无 PATCH 枚举，收藏状态更新走后端保留语义一致的 POST 兼容入口。
    return HttpClient.post<RecordResponse>(`/records/${encodeURIComponent(id)}/favorite`, request, {
      authorized: true
    });
  }

  /**
   * 收藏当前用户拥有的记录。
   * 返回值为后端确认后的记录详情，避免前端只靠本地乐观状态。
   */
  static async favoriteRecord(id: string): Promise<RecordResponse> {
    return RecordService.updateFavorite(id, true);
  }

  /**
   * 取消收藏当前用户拥有的记录。
   * 返回值为后端确认后的记录详情，避免跨设备状态不一致。
   */
  static async unfavoriteRecord(id: string): Promise<RecordResponse> {
    return RecordService.updateFavorite(id, false);
  }

  /**
   * 给当前用户拥有的历史记录绑定标签。
   * 参数 id/tagId 分别为记录和标签 ID；重复绑定由后端按幂等成功处理。
   */
  static async addTag(id: string, tagId: number): Promise<RecordResponse> {
    return HttpClient.post<RecordResponse>(
      `/records/${encodeURIComponent(id)}/tags/${encodeURIComponent(String(tagId))}`,
      undefined,
      { authorized: true }
    );
  }

  /**
   * 移除当前用户历史记录上的标签绑定。
   * 参数 id/tagId 分别为记录和标签 ID；越权或不存在由后端返回 NOT_FOUND。
   */
  static async removeTag(id: string, tagId: number): Promise<RecordResponse> {
    return HttpClient.delete<RecordResponse>(
      `/records/${encodeURIComponent(id)}/tags/${encodeURIComponent(String(tagId))}`,
      { authorized: true }
    );
  }

  /**
   * 按关键字搜索当前用户历史记录。
   * 参数 keyword 仅传给后端查询当前用户记录，不在前端记录搜索历史或 OCR 全文。
   */
  static async searchRecords(keyword: string, page: number = 0, size: number = 20): Promise<RecordPageResult<RecordResponse>> {
    const query: RecordQuery = {
      keyword: keyword,
      page: page,
      size: size
    };
    return RecordService.listRecords(query);
  }

  private static toQueryString(query: RecordQuery): string {
    const params: string[] = [];
    if (query.page !== undefined) {
      params.push(`page=${encodeURIComponent(String(query.page))}`);
    }
    if (query.size !== undefined) {
      params.push(`size=${encodeURIComponent(String(query.size))}`);
    }
    if (query.favorite !== undefined) {
      params.push(`favorite=${encodeURIComponent(String(query.favorite))}`);
    }
    if (query.sourceType !== undefined) {
      params.push(`sourceType=${encodeURIComponent(query.sourceType)}`);
    }
    if (query.keyword !== undefined && query.keyword.length > 0) {
      params.push(`keyword=${encodeURIComponent(query.keyword)}`);
    }
    if (query.createdFrom !== undefined && query.createdFrom.length > 0) {
      params.push(`createdFrom=${encodeURIComponent(query.createdFrom)}`);
    }
    if (query.createdTo !== undefined && query.createdTo.length > 0) {
      params.push(`createdTo=${encodeURIComponent(query.createdTo)}`);
    }
    if (query.dateFrom !== undefined && query.dateFrom.length > 0) {
      params.push(`dateFrom=${encodeURIComponent(query.dateFrom)}`);
    }
    if (query.dateTo !== undefined && query.dateTo.length > 0) {
      params.push(`dateTo=${encodeURIComponent(query.dateTo)}`);
    }
    if (query.tagId !== undefined) {
      params.push(`tagId=${encodeURIComponent(String(query.tagId))}`);
    }
    if (query.ocrEngine !== undefined && query.ocrEngine.length > 0) {
      params.push(`ocrEngine=${encodeURIComponent(query.ocrEngine)}`);
    }
    if (query.sort !== undefined && query.sort.length > 0) {
      params.push(`sort=${encodeURIComponent(query.sort)}`);
    }
    return params.length === 0 ? '' : `?${params.join('&')}`;
  }
}
