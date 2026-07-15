/**
 * FileModels 定义文件上传契约的数据结构。
 * 维护说明：本模块只描述 files/upload API 的请求与响应，不代表页面已接入真实上传闭环。
 */
export interface FileUploadRequest {
  uri: string;
  fileName: string;
  mimeType: string;
  size: number;
  rawFileName?: string;
  uploadSource?: 'system_picker' | 'document_picker_image' | 'generated_crop_cache' | 'dev_rawfile';
}

/**
 * FileObject 表示后端文件对象的脱敏元数据。
 * 安全边界：objectKey 只能作为后端记录关联字段使用，前端不得把它拼成本地路径或公开下载地址。
 */
export interface FileObject {
  id: number;
  objectKey: string;
  fileName: string;
  mimeType: string;
  size: number;
  fileHash: string;
  storageProvider: string;
  createdAt: string;
  accessUrl?: string | null;
  expiresAt?: string | null;
  originalFilename?: string;
  contentType?: string;
  fileSize?: number;
}
