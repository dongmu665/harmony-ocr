/**
 * TagModels 定义 OCR 历史标签 API 的前端数据契约，属于 features/record 模块。
 * 维护说明：标签只保存用户可见分类元数据，不承载 OCR 全文、完整路径、objectKey 或 Token。
 */
export interface CreateTagRequest {
  name: string;
  color?: string;
}

/**
 * UpdateTagRequest 表示标签编辑请求。
 * 维护说明：仅允许修改名称和颜色，标签归属仍由后端按当前用户校验。
 */
export interface UpdateTagRequest {
  name?: string;
  color?: string;
}

/**
 * TagResponse 表示当前用户可见的标签响应。
 * 安全边界：标签 ID 不能作为跨用户访问记录的凭据，所有绑定仍需后端 ownership 校验。
 */
export interface TagResponse {
  id: number;
  name: string;
  color?: string;
  createdAt: string;
  updatedAt: string;
}
