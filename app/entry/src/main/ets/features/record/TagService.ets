import { HttpClient } from '../../common/network/HttpClient';
import { CreateTagRequest, TagResponse, UpdateTagRequest } from './TagModels';

/**
 * TagService 封装 OCR 历史标签 API 调用，属于 features/record 模块。
 * 维护说明：服务不直接读取 Token、不记录标签内容和 OCR 文本，鉴权统一交给 HttpClient。
 */
export class TagService {
  /**
   * 创建当前用户的历史标签。
   * 参数 request 仅包含标签名和颜色；返回后端保存后的标签元信息。
   */
  static async createTag(request: CreateTagRequest): Promise<TagResponse> {
    return HttpClient.post<TagResponse>('/tags', request, { authorized: true });
  }

  /**
   * 查询当前用户的历史标签列表。
   * 返回值仅包含当前账号可见标签，不包含任何绑定记录全文。
   */
  static async listTags(): Promise<TagResponse[]> {
    return HttpClient.get<TagResponse[]>('/tags', { authorized: true });
  }

  /**
   * 更新当前用户拥有的历史标签。
   * 参数 id 为标签 ID，request 为允许修改的字段；越权由后端返回 NOT_FOUND。
   */
  static async updateTag(id: number, request: UpdateTagRequest): Promise<TagResponse> {
    return HttpClient.patch<TagResponse>(`/tags/${encodeURIComponent(String(id))}`, request, { authorized: true });
  }

  /**
   * 删除当前用户拥有的历史标签。
   * 参数 id 为标签 ID；删除只影响标签和绑定关系，不删除 OCR 记录。
   */
  static async deleteTag(id: number): Promise<void> {
    return HttpClient.delete<void>(`/tags/${encodeURIComponent(String(id))}`, { authorized: true });
  }
}
