import { OcrSourceType } from './OcrModels';

/**
 * DeviceOcrModels 定义设备图片与 OCR 流程的编译期模型，属于 features/ocr 模块。
 * 维护说明：这些类型只描述 Stub 状态，不承载真实图片 URI、文件路径、对象存储 key 或 OCR SDK 结果。
 */
export type DeviceOcrCapabilityStatus = 'real_device_ocr' | 'unavailable';
export type DeviceOcrStage = 'capture' | 'album' | 'preview' | 'crop' | 'recognition';
export type DeviceImagePickerMode = 'camera' | 'album';
export type DeviceImageUploadSource = 'system_picker' | 'document_picker_image' | 'generated_crop_cache' | 'dev_rawfile';

/**
 * 设备能力占位信息。
 * 安全注意：该结构只用于 UI 提示，不得扩展为保存本地文件路径、Token、MinIO key 或第三方 OCR 参数。
 */
export interface DeviceOcrPlaceholder {
  sourceType: OcrSourceType;
  stage: DeviceOcrStage;
  status: DeviceOcrCapabilityStatus;
  title: string;
  message: string;
}

/**
 * 设备 OCR Stub 请求。
 * 参数只表达入口来源和处理状态，用于隔离设备能力与页面展示模型。
 */
export interface DeviceOcrRequest {
  sourceType: OcrSourceType;
  stage: DeviceOcrStage;
}

/**
 * 真实图片选择结果。
 * 安全注意事项：uri 仅保存在本轮内存流程中，不写日志、不持久化，也不作为后端 record 字段保存。
 */
export interface DeviceImageSelection {
  sourceType: OcrSourceType;
  uri: string;
  fileName: string;
  mimeType: string;
  rawFileName?: string;
  uploadSource: DeviceImageUploadSource;
}
