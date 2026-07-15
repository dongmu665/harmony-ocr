/**
 * V2Models 定义 V2.0 前端展示所需的安全 DTO。
 * 维护边界：模型只描述后端已脱敏字段，不包含 API Key、Token、完整 media URI、objectKey 或 OCR 全文日志字段。
 */
export type AiActionType = 'CORRECTION' | 'SUMMARY' | 'TRANSLATION' | 'TITLE' | 'KEY_POINTS' | 'FIELD_EXTRACTION' | 'SMART_FORMAT' | 'MARKDOWN';
export type ExportFormatType = 'TXT' | 'MARKDOWN' | 'JSON' | 'PDF' | 'SEARCHABLE_PDF';

/**
 * AiActionRequest 表示用户主动触发的 AI 文本处理请求。
 * 安全边界：前端只传 recordId 和动作类型，OCR 全文由后端按 ownership 读取。
 */
export interface AiActionRequest {
  recordId: number;
  action: AiActionType;
  targetLanguage?: string;
  consentAccepted: boolean;
}

/**
 * AiActionResponse 表示后端返回的 AI 处理结果。
 * 维护说明：响应不包含 prompt、API Key、第三方原始响应或 provider 调用日志。
 */
export interface AiActionResponse {
  action: AiActionType;
  providerName: string;
  modelName: string;
  outputText: string;
  inputLength: number;
  consentRequired: boolean;
  degraded: boolean;
  degradationReason?: string;
  errorCode?: string;
}

/**
 * AiRuntimeConsentRequest 表示用户对 AI 处理 OCR 文本的运行时同意。
 * 安全边界：只传布尔值，不夹带 OCR 文本、provider 配置或密钥。
 */
export interface AiRuntimeConsentRequest {
  accepted: boolean;
}

/**
 * AiRuntimeConsentResponse 表示当前 AI 同意状态。
 * 维护说明：只暴露 scope 和时间戳，不包含具体 OCR 内容或第三方服务信息。
 */
export interface AiRuntimeConsentResponse {
  scope: string;
  accepted: boolean;
  acceptedAt?: string;
  updatedAt?: string;
}

/**
 * AiProviderConfigRequest 表示用户 BYOK Provider 配置提交。
 * 安全边界：apiKey 只在创建/更新请求体中短暂出现，不能被页面缓存、日志记录或再次回显。
 */
export interface AiProviderConfigRequest {
  providerName?: string;
  baseUrl?: string;
  modelName?: string;
  apiKey?: string;
  enabled?: boolean;
  defaultProvider?: boolean;
}

/**
 * AiProviderConfigResponse 表示 BYOK Provider 的脱敏配置。
 * 维护说明：只返回 fingerprint/masked/configured 状态，不返回明文或密文 API Key。
 */
export interface AiProviderConfigResponse {
  id: number;
  providerName: string;
  baseUrl: string;
  modelName: string;
  apiKeyFingerprint?: string;
  apiKeyMasked?: string;
  apiKeyConfigured: boolean;
  secureStorageStatus: string;
  enabled: boolean;
  defaultProvider: boolean;
  createdAt?: string;
  updatedAt?: string;
}

/**
 * AiProviderTestResponse 表示 Provider 连通性测试结果。
 * 安全边界：message 只能显示脱敏诊断，不能包含请求头、API Key 或第三方原始错误体。
 */
export interface AiProviderTestResponse {
  providerId: number;
  providerName: string;
  status: string;
  degraded: boolean;
  message: string;
}

/**
 * PdfExportRequest 表示 PDF 导出任务请求。
 * 维护说明：只传记录 ID 和安全文件名，后端负责 ownership 校验和文件内容生成。
 */
export interface PdfExportRequest {
  recordIds: number[];
  fileName: string;
  searchable: boolean;
}

/**
 * CreateExportRequest 表示通用导出任务请求。
 * 安全边界：前端不传 OCR 全文或 objectKey，导出内容由后端按记录归属重新读取。
 */
export interface CreateExportRequest {
  recordIds: number[];
  format: ExportFormatType;
  fileName: string;
}

/**
 * ExportJobStatusEventResponse 表示导出任务状态历史。
 * 维护说明：只包含状态、进度和时间戳，不暴露后台临时路径或对象存储 key。
 */
export interface ExportJobStatusEventResponse {
  status: string;
  progress: number;
  createdAt?: string;
}

/**
 * ExportJobResponse 表示导出任务摘要。
 * 安全边界：downloadPath 是后端授权下载入口，不是对象存储真实地址或本地文件路径。
 */
export interface ExportJobResponse {
  jobId: string;
  status: string;
  format: ExportFormatType;
  fileName: string;
  contentType: string;
  sizeBytes: number;
  progress: number;
  checksumSha256: string;
  searchable: boolean;
  degraded: boolean;
  downgradeReason?: string;
  downloadPath?: string;
  createdAt?: string;
  statusHistory?: ExportJobStatusEventResponse[];
}

export type BatchOcrItemStatus = 'QUEUED' | 'PENDING' | 'RUNNING' | 'RETRYING' | 'CANCELED' | 'SUCCESS' | 'FAILED' | 'CONFIRM';

/**
 * BatchOcrTaskItemSummaryResponse 表示批量 OCR 单个文件的脱敏摘要。
 * 安全边界：fileName 只用于展示，响应不包含本地 URI、图片 bytes、objectKey 或 OCR 全文。
 */
export interface BatchOcrTaskItemSummaryResponse {
  itemIndex: number;
  fileName: string;
  status: BatchOcrItemStatus;
  recordId?: number;
  errorCode?: string;
  failureReason?: string;
}

/**
 * BatchOcrTaskSummaryResponse 表示批量 OCR 任务摘要。
 * 维护说明：items 只展示任务进度和错误摘要，完整识别结果仍通过 records API 查询。
 */
export interface BatchOcrTaskSummaryResponse {
  jobId: string;
  status: string;
  recordId?: number;
  total: number;
  completed: number;
  failed: number;
  progress: number;
  createdAt?: string;
  items: BatchOcrTaskItemSummaryResponse[];
}

/**
 * MembershipResponse 表示当前用户会员和额度用量。
 * 安全边界：不包含支付凭据、订单原始信息、手机号、真实姓名或后台备注。
 */
export interface MembershipResponse {
  userId: number;
  membershipLevel: string;
  ocrQuota: number;
  aiQuota: number;
  exportQuota: number;
  ocrUsed: number;
  aiUsed: number;
  exportUsed: number;
}

/**
 * ActivationCodeRedeemRequest 表示会员激活码兑换请求。
 * 安全边界：code 只在提交时短暂传递，不持久化、不日志输出、不进入页面全局状态。
 */
export interface ActivationCodeRedeemRequest {
  code: string;
}

/**
 * AdminUpdateMembershipRequest 表示管理员调整用户会员额度的真实后端请求。
 * 安全边界：该请求只表达等级和额度变更，不携带支付凭证、交易流水、激活码明文或用户隐私资料。
 */
export interface AdminUpdateMembershipRequest {
  membershipLevel: string;
  ocrQuota: number;
  aiQuota: number;
  exportQuota: number;
}

/**
 * AdminManualMembershipOrderRequest 表示管理员创建线下手工开通记录的请求。
 * 维护说明：note 只允许写入非敏感业务备注，不能包含付款凭证、Token、API Key、身份证件或联系方式。
 */
export interface AdminManualMembershipOrderRequest {
  membershipLevel: string;
  ocrQuota: number;
  aiQuota: number;
  exportQuota: number;
  note?: string;
}

/**
 * AdminManualMembershipOrderResponse 表示手工会员订单的脱敏响应。
 * 安全边界：响应仅用于展示订单元数据和额度结果，不代表移动端支付成功，也不返回任何真实支付凭据。
 */
export interface AdminManualMembershipOrderResponse {
  id: number;
  userId: number;
  adminUserId: number;
  membershipLevel: string;
  ocrQuota: number;
  aiQuota: number;
  exportQuota: number;
  orderStatus: string;
  paymentProvider: string;
  createdAt?: string;
}

/**
 * OcrHealthResponse 表示当前 OCR 服务可用性。
 * 维护说明：只展示引擎名称和可用状态，不暴露本机执行路径或 Provider 内部错误。
 */
export interface OcrHealthResponse {
  available: boolean;
  ocrEngine: string;
}

/**
 * AdminUsageSummaryResponse 表示管理后台用量概览。
 * 安全边界：只提供聚合数字，不返回用户 OCR 全文、文件地址或个人敏感资料。
 */
export interface AdminUsageSummaryResponse {
  totalUsers: number;
  totalRecords: number;
  totalFeedback: number;
  ocrUsed: number;
  aiUsed: number;
  exportUsed: number;
}

/**
 * AdminCapabilityResponse 表示当前用户是否具备管理能力。
 * 维护说明：前端只能据此展示入口，所有管理 API 仍必须由后端鉴权。
 */
export interface AdminCapabilityResponse {
  admin: boolean;
}

/**
 * PageResult 表示后端统一分页响应。
 * 维护说明：items 已由后端按当前用户或管理员权限过滤并脱敏。
 */
export interface PageResult<T> {
  items: T[];
  total: number;
  page: number;
  size: number;
}

/**
 * AdminUserResponse 表示管理后台用户列表的脱敏行。
 * 安全边界：不返回密码哈希、Token、邮箱手机号等未在当前产品范围内公开的资料。
 */
export interface AdminUserResponse {
  id: number;
  username: string;
  status: string;
  createdAt?: string;
  membershipLevel: string;
}

/**
 * AdminRecordResponse 表示管理后台记录列表摘要。
 * 维护说明：只返回标题、来源、长度和时间，不返回 OCR 全文或图片 objectKey。
 */
export interface AdminRecordResponse {
  id: number;
  userId: number;
  title: string;
  sourceType: string;
  textLength: number;
  createdAt?: string;
}

/**
 * AdminFeedbackResponse 表示管理后台反馈列表摘要。
 * 安全边界：这里不承载完整联系方式、附件路径或后台处理备注。
 */
export interface AdminFeedbackResponse {
  id: number;
  userId?: number;
  feedbackType: string;
  status: string;
  createdAt?: string;
}

/**
 * AdminAuditLogResponse 表示管理后台审计日志行。
 * 维护说明：只记录管理动作元数据，不保存请求体、Token、API Key 或 OCR 全文。
 */
export interface AdminAuditLogResponse {
  id: number;
  adminUserId: number;
  action: string;
  targetType: string;
  targetId?: number;
  createdAt?: string;
}
