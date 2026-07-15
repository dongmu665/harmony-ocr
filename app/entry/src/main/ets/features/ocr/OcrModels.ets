/**
 * OcrModels 定义 V1.0 OCR 前端流程的数据结构，属于 features/ocr 模块。
 * 维护说明：OcrResult 承载端侧真实 OCR 结果以及开发诊断结果；正式上线路径必须由真实 OCR 服务写入，不得把 Mock/Stub 伪装成真实结果。
 */
export type OcrSourceType = 'camera' | 'album' | 'pdf';

/**
 * OcrMockImage 描述开发期 Mock 图片占位信息。
 * 维护说明：该模型不能被用作真实 OCR 结果或真实图片资源凭据。
 */
export interface OcrMockImage {
  sourceType: OcrSourceType;
  title: string;
  description: string;
}

/**
 * OcrTextBlock 表示一次 OCR 返回的文本块。
 * 安全边界：text 可能包含隐私内容，列表页和日志只能使用摘要或计数。
 */
export interface OcrTextBlock {
  order: number;
  text: string;
  confidence: number;
  boundingBox?: string;
}

/**
 * PdfOcrPageResult 表示扫描型 PDF 单页识别结果。
 * 维护说明：失败页使用 status/errorCode/failureReason 表达，不暴露 Provider 异常栈或 PDF 路径。
 */
export interface PdfOcrPageResult {
  pageIndex: number;
  pageNumber: number;
  status: string;
  rawText: string;
  editedText: string;
  durationMs: number;
  confidence?: number;
  errorCode?: string;
  failureReason?: string;
  previewImageBase64?: string;
  previewContentType?: string;
  previewImageUri?: string;
  blocks?: OcrTextBlock[];
}

/**
 * PdfOcrRecognizeResponse 表示后端 PDF OCR 完整响应。
 * 安全边界：响应包含 OCR 文本但不包含 PDF URI、对象存储 key、Token 或后端临时文件路径。
 */
export interface PdfOcrRecognizeResponse {
  rawText: string;
  editedText: string;
  pageCount: number;
  successPageCount: number;
  failedPageCount: number;
  durationMs: number;
  language: string;
  providerName: string;
  engineName: string;
  mode: string;
  pages: PdfOcrPageResult[];
  errorCode?: string;
  partial: boolean;
  recordId?: number;
}

/**
 * PdfOcrSummary 是结果页展示 PDF OCR 状态的摘要。
 * 维护说明：只保留页数和成功失败计数，适合列表或顶部状态展示。
 */
export interface PdfOcrSummary {
  pageCount: number;
  successPageCount: number;
  failedPageCount: number;
  partial: boolean;
}

/**
 * OcrResult 是前端 OCR 流程统一结果模型。
 * 安全边界：rawText/editedText 可能包含隐私内容，只能在结果页、保存记录和用户主动导出流程中使用。
 */
export interface OcrResult {
  sourceType: OcrSourceType;
  rawText: string;
  editedText: string;
  durationMs: number;
  language: string;
  ocrEngine: string;
  providerName?: string;
  engineName?: string;
  mode?: string;
  confidence?: number;
  boundingBox?: string;
  errorCode?: string;
  blocks: OcrTextBlock[];
  fallbackUsed?: boolean;
  recordId?: number;
  pdfSummary?: PdfOcrSummary;
  pdfPages?: PdfOcrPageResult[];
}

/**
 * OcrRecognitionOptions 描述 OCR 识别的本地执行选项。
 * 维护说明：languageHint 只是 Provider 提示，不代表新增语言能力；simulateDelayMs 仅服务开发体验。
 */
export interface OcrRecognitionOptions {
  simulateDelayMs?: number;
  languageHint?: string;
}
