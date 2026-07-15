import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../../common/config/ApiConfig';
import { ApiError, ApiResponse } from '../../common/network/ApiTypes';
import { HttpClient } from '../../common/network/HttpClient';
import { TokenStorage } from '../../common/storage/TokenStorage';
import { DeviceImageSelection } from '../ocr/DeviceOcrModels';
import { ImageCropService } from '../ocr/ImageCropService';
import { ImageUploadNormalizeService, NormalizedImageUpload } from '../ocr/ImageUploadNormalizeService';
import {
  AdminAuditLogResponse,
  AdminFeedbackResponse,
  AdminCapabilityResponse,
  AdminManualMembershipOrderRequest,
  AdminManualMembershipOrderResponse,
  AdminRecordResponse,
  AdminUpdateMembershipRequest,
  AdminUsageSummaryResponse,
  AdminUserResponse,
  ActivationCodeRedeemRequest,
  AiActionRequest,
  AiActionResponse,
  AiProviderConfigRequest,
  AiProviderConfigResponse,
  AiProviderTestResponse,
  AiRuntimeConsentRequest,
  AiRuntimeConsentResponse,
  BatchOcrItemStatus,
  BatchOcrTaskItemSummaryResponse,
  BatchOcrTaskSummaryResponse,
  CreateExportRequest,
  ExportJobResponse,
  MembershipResponse,
  OcrHealthResponse,
  PageResult,
  PdfExportRequest
} from './V2Models';

/**
 * EmptyRequest 表示后端要求 POST 但不需要业务字段的空请求体。
 * 维护说明：使用空对象避免在取消、测试、重加密等动作中夹带敏感上下文。
 */
class EmptyRequest {
}

/**
 * BatchMultipartFilePart 表示批量 OCR multipart 请求中的单个文件段。
 * 安全边界：只在请求组装期间持有脱敏文件名和二进制内容，不落入页面状态或日志。
 */
interface BatchMultipartFilePart {
  fileName: string;
  mimeType: string;
  content: Uint8Array;
}

/**
 * MultipartRequestResponse 描述手写 multipart 请求的最小返回结构。
 * 这里显式声明类型，避免 ArkTS 对匿名对象字面量返回值的限制。
 */
interface MultipartRequestResponse {
  rawBody: string;
  statusCode: number;
}

/**
 * BatchOcrJobCreateItemResponse 描述批量 OCR 创建响应中的单项脱敏字段。
 * 维护说明：result 字段可能由后端返回 OCR 全文，但前端会在映射时丢弃。
 */
interface BatchOcrJobCreateItemResponse {
  itemIndex: number;
  fileName: string;
  status: BatchOcrItemStatus;
  recordId?: number;
  errorCode?: string;
  failureReason?: string;
}

/**
 * BatchOcrJobCreateResponse 描述批量 OCR 创建/重试接口返回的任务摘要。
 * 维护边界：只保留前端后续渲染所需的脱敏元数据，不暴露 URI 或对象存储 key。
 */
interface BatchOcrJobCreateResponse {
  jobId: string;
  status: string;
  recordId?: number;
  total: number;
  completed: number;
  failed: number;
  progress: number;
  items: BatchOcrJobCreateItemResponse[];
}

/**
 * V2Service 封装 V2.0 前端需要调用的后端 JSON API。
 * 维护边界：服务层不打印请求/响应，不接触明文 Token；BYOK apiKey 只在用户提交时作为请求体短暂传递。
 */
export class V2Service {
  /**
   * 兼容后端分页响应和旧数组响应。
   * 安全边界：只解包已脱敏 items，不在前端恢复或推断任何敏感字段。
   */
  private static pageItems<T>(data: PageResult<T> | T[]): T[] {
    if (Array.isArray(data)) {
      return data;
    }
    return data.items;
  }

  /**
   * 查询当前 OCR Provider 健康状态。
   * 返回值只包含可用性和引擎名称，不包含本机路径或 provider 内部错误。
   */
  static async getOcrHealth(): Promise<OcrHealthResponse> {
    return HttpClient.get<OcrHealthResponse>('/ocr/health', { authorized: true });
  }

  /**
   * 创建 PDF 或 searchable PDF 导出任务。
   * 安全边界：只传记录 ID、安全文件名和 searchable 意图，不传本地路径或 objectKey。
   */
  static async createPdfExport(request: PdfExportRequest): Promise<ExportJobResponse> {
    return HttpClient.post<ExportJobResponse>('/exports/pdf', request, { authorized: true });
  }

  /**
   * 创建 TXT、Markdown、JSON、PDF 或 searchable PDF 通用导出任务。
   * 安全边界：请求体只携带记录 ID、格式和安全文件名，后端负责 ownership 校验与文件名清理。
   */
  static async createExport(request: CreateExportRequest): Promise<ExportJobResponse> {
    return HttpClient.post<ExportJobResponse>('/exports', request, { authorized: true });
  }

  /**
   * 创建批量 OCR 任务。
   * 参数 selections 必须来自用户本次主动选择的系统图片；请求体使用 multipart/form-data 的 files 重复字段，不记录 Token、URI、图片 bytes 或 OCR 全文。
   */
  static async createBatchTask(
    context: common.UIAbilityContext,
    selections: DeviceImageSelection[],
    language: string = '',
    saveToHistory: boolean = true
  ): Promise<BatchOcrTaskSummaryResponse> {
    if (selections.length === 0) {
      throw new ApiError('VALIDATION_ERROR', '请先选择图片后再创建批量任务', 400);
    }
    const accessToken = await TokenStorage.getAccessToken();
    if (accessToken.length === 0) {
      throw new ApiError('UNAUTHORIZED', '请先登录后再创建批量任务', 401);
    }

    const fileParts: BatchMultipartFilePart[] = [];
    for (let index = 0; index < selections.length; index++) {
      const selection = selections[index];
      try {
        const content = await ImageCropService.readSelectionBytes(context, selection);
        fileParts.push(await V2Service.normalizeBatchUploadPart(selection, content));
      } catch (error) {
        const reason = error instanceof Error && error.message.length > 0 ? error.message : '图片读取失败';
        throw new ApiError('INVALID_IMAGE', `第 ${index + 1} 张图片读取失败：${reason}`, 400);
      }
    }

    const boundary = `----HarmonyOcrBatchCreate${Date.now()}`;
    const body = V2Service.buildBatchCreateMultipartBody(boundary, fileParts, language, saveToHistory);
    const response = await V2Service.postMultipartRequest(
      '/ocr/batches',
      accessToken,
      boundary,
      body,
      Math.max(ApiConfig.REQUEST_TIMEOUT_MS, 60000)
    );
    return V2Service.parseBatchMultipartResponse(response.rawBody, response.statusCode, '批量创建');
  }

  /**
   * 查询当前用户的批量 OCR 任务摘要。
   * 返回值不包含 OCR 全文或图片 URI，仅用于首页和批量页展示真实任务状态。
   */
  static async listBatchTasks(): Promise<BatchOcrTaskSummaryResponse[]> {
    return HttpClient.get<BatchOcrTaskSummaryResponse[]>('/ocr/batches', { authorized: true });
  }

  /**
   * 查询当前用户拥有的单个批量 OCR 任务。
   * 参数 jobId 只作为任务标识，响应不包含图片 URI、objectKey 或 OCR 全文。
   */
  static async getBatchTask(jobId: string): Promise<BatchOcrTaskSummaryResponse> {
    return HttpClient.get<BatchOcrTaskSummaryResponse>('/ocr/batches/' + encodeURIComponent(jobId), { authorized: true });
  }

  /**
   * 取消当前用户拥有的排队或执行中批量 OCR 任务。
   * 安全边界：只传 jobId，不传图片 URI、objectKey、OCR 全文或本地文件路径。
   */
  static async cancelBatchTask(jobId: string): Promise<BatchOcrTaskSummaryResponse> {
    return HttpClient.post<BatchOcrTaskSummaryResponse>('/ocr/batches/' + encodeURIComponent(jobId) + '/cancel', new EmptyRequest(), { authorized: true });
  }

  /**
   * 重试当前用户拥有的失败批量 OCR item。
   * 安全边界：selection 必须来自用户本次主动选择的系统图片；请求只上传图片 bytes 和脱敏文件名，不记录 URI、Token、objectKey 或 OCR 全文。
   */
  static async retryBatchItem(
    context: common.UIAbilityContext,
    jobId: string,
    itemIndex: number,
    selection: DeviceImageSelection,
    language: string = '',
    saveToHistory: boolean = false
  ): Promise<BatchOcrTaskSummaryResponse> {
    const accessToken = await TokenStorage.getAccessToken();
    if (accessToken.length === 0) {
      throw new ApiError('UNAUTHORIZED', '请先登录后再重试批量任务', 401);
    }
    const content = await ImageCropService.readSelectionBytes(context, selection);
    const filePart = await V2Service.normalizeBatchUploadPart(selection, content);
    return V2Service.uploadBatchRetry(jobId, itemIndex, filePart, accessToken, language, saveToHistory);
  }

  /**
   * 查询当前用户的导出任务摘要。
   * 返回值只包含任务元数据和下载入口，不包含文件 bytes。
   */
  static async listExportJobs(): Promise<ExportJobResponse[]> {
    return HttpClient.get<ExportJobResponse[]>('/exports', { authorized: true });
  }

  /**
   * 查询当前用户拥有的单个导出任务。
   * 返回值只包含任务元数据、进度和授权下载入口，不包含文件 bytes 或对象存储 key。
   */
  static async getExportJob(jobId: string): Promise<ExportJobResponse> {
    return HttpClient.get<ExportJobResponse>('/exports/' + encodeURIComponent(jobId), { authorized: true });
  }

  /**
   * 下载当前用户拥有的成功导出文件 bytes。
   * 安全边界：仅按 jobId 访问后端 download 入口，不接收、不展示 objectKey、服务器路径或 OCR 全文。
   */
  static async downloadExportJob(jobId: string): Promise<ArrayBuffer> {
    return HttpClient.getBytes('/exports/' + encodeURIComponent(jobId) + '/download', { authorized: true });
  }

  /**
   * 取消当前用户拥有的待处理或执行中导出任务。
   * 安全边界：只传 jobId，不传下载路径、objectKey、文件 bytes 或 OCR 全文。
   */
  static async cancelExportJob(jobId: string): Promise<ExportJobResponse> {
    return HttpClient.post<ExportJobResponse>('/exports/' + encodeURIComponent(jobId) + '/cancel', new EmptyRequest(), { authorized: true });
  }

  /**
   * 执行 AI 文本处理动作。
   * 参数必须携带用户同意标记；OCR 文本由后端按记录归属读取，前端不上传全文。
   */
  static async runAiAction(request: AiActionRequest): Promise<AiActionResponse> {
    return HttpClient.post<AiActionResponse>('/ai/actions', request, { authorized: true });
  }

  /**
   * 查询当前用户 AI OCR 文本处理同意状态。
   * 返回值只包含 scope 和时间戳，不包含 OCR 文本、prompt、API Key 或 provider 响应。
   */
  static async getAiConsent(): Promise<AiRuntimeConsentResponse> {
    return HttpClient.get<AiRuntimeConsentResponse>('/ai/consent', { authorized: true });
  }

  /**
   * 保存 AI OCR 文本处理运行时同意状态。
   * 安全边界：请求只传布尔值，不夹带 OCR 全文、prompt、provider 配置或密钥。
   */
  static async updateAiConsent(request: AiRuntimeConsentRequest): Promise<AiRuntimeConsentResponse> {
    return HttpClient.post<AiRuntimeConsentResponse>('/ai/consent', request, { authorized: true });
  }

  /**
   * 查询当前用户的 BYOK Provider 列表。
   * 返回值为后端脱敏元数据，不包含 API Key 或密文。
   */
  static async listProviders(): Promise<AiProviderConfigResponse[]> {
    return HttpClient.get<AiProviderConfigResponse[]>('/ai/providers', { authorized: true });
  }

  /**
   * 创建当前用户的 BYOK Provider 配置。
   * 安全边界：apiKey 只在请求体中短暂传递；响应由后端脱敏，不包含明文或密文 key。
   */
  static async createProvider(request: AiProviderConfigRequest): Promise<AiProviderConfigResponse> {
    return HttpClient.post<AiProviderConfigResponse>('/ai/providers', request, { authorized: true });
  }

  /**
   * 更新当前用户的 BYOK Provider 配置。
   * 参数 id 为当前用户 provider ID；后端负责 ownership 校验和密钥加密/脱敏。
   */
  static async updateProvider(id: number, request: AiProviderConfigRequest): Promise<AiProviderConfigResponse> {
    return HttpClient.patch<AiProviderConfigResponse>('/ai/providers/' + id.toString(), request, { authorized: true });
  }

  /**
   * 测试当前用户 Provider 连通性。
   * 安全边界：前端不接触解密后的 API Key，测试请求由后端按安全策略执行。
   */
  static async testProvider(id: number): Promise<AiProviderTestResponse> {
    return HttpClient.post<AiProviderTestResponse>('/ai/providers/' + id.toString() + '/test', new EmptyRequest(), { authorized: true });
  }

  /**
   * 触发当前用户 Provider 密钥重加密。
   * 维护说明：该动作只返回脱敏 Provider 元数据，不返回明文 API Key 或密文内容。
   */
  static async reencryptProvider(id: number): Promise<AiProviderConfigResponse> {
    return HttpClient.post<AiProviderConfigResponse>('/ai/providers/' + id.toString() + '/reencrypt', new EmptyRequest(), { authorized: true });
  }

  /**
   * 删除当前用户的 BYOK Provider 配置。
   * 安全边界：后端负责删除密钥材料和默认配置状态，前端不直接处理密文。
   */
  static async deleteProvider(id: number): Promise<void> {
    await HttpClient.delete<void>('/ai/providers/' + id.toString(), { authorized: true });
  }

  /**
   * 查询当前用户会员与额度。
   * 返回值只包含等级和用量数字，不包含支付、账单或身份敏感信息。
   */
  static async getMembership(): Promise<MembershipResponse> {
    return HttpClient.get<MembershipResponse>('/membership/me', { authorized: true });
  }

  /**
   * 兑换一次性会员激活码。
   * 安全边界：只把用户输入的明文 code 发送给兑换接口，不做本地持久化、不写日志。
   */
  static async redeemActivationCode(request: ActivationCodeRedeemRequest): Promise<MembershipResponse> {
    return HttpClient.post<MembershipResponse>('/membership/activation-codes/redeem', request, { authorized: true });
  }

  /**
   * 查询当前用户是否具备管理后台访问能力。
   * 说明：该结果只控制 UI 展示，所有管理接口仍以后端鉴权结果为准。
   */
  static async getAdminCapability(): Promise<AdminCapabilityResponse> {
    return HttpClient.get<AdminCapabilityResponse>('/admin/me', { authorized: true });
  }

  /**
   * 查询管理后台聚合用量概览。
   * 返回值只包含聚合数字，不包含用户 OCR 全文、文件地址或敏感凭据。
   */
  static async getAdminSummary(): Promise<AdminUsageSummaryResponse> {
    return HttpClient.get<AdminUsageSummaryResponse>('/admin/usage/summary', { authorized: true });
  }

  /**
   * 查询管理后台用户摘要列表。
   * 安全边界：仅用于管理员视图，响应不包含密码哈希、Token 或密钥材料。
   */
  static async listAdminUsers(): Promise<AdminUserResponse[]> {
    return V2Service.pageItems(await HttpClient.get<PageResult<AdminUserResponse> | AdminUserResponse[]>('/admin/users', { authorized: true }));
  }

  /**
   * 查询单个管理后台用户摘要。
   * 安全边界：详情 DTO 与列表一致，不返回密码哈希、Token、联系方式或任何认证材料。
   */
  static async getAdminUser(id: number): Promise<AdminUserResponse> {
    return HttpClient.get<AdminUserResponse>('/admin/users/' + id.toString(), { authorized: true });
  }

  /**
   * 管理员调整指定用户会员等级和额度。
   * 维护说明：这是唯一真实会员调整写接口之一；调用方必须把封禁、假支付、假升级等无后端契约动作保持禁用。
   */
  static async updateAdminUserMembership(id: number, request: AdminUpdateMembershipRequest): Promise<MembershipResponse> {
    return HttpClient.patch<MembershipResponse>('/admin/users/' + id.toString() + '/membership', request, { authorized: true });
  }

  /**
   * 创建线下手工会员开通订单。
   * 安全边界：该接口不接入真实支付，不生成激活码明文；note 不应包含付款凭证、Token、API Key 或个人敏感信息。
   */
  static async createAdminManualOrder(
    id: number,
    request: AdminManualMembershipOrderRequest
  ): Promise<AdminManualMembershipOrderResponse> {
    return HttpClient.post<AdminManualMembershipOrderResponse>('/admin/users/' + id.toString() + '/manual-orders', request, { authorized: true });
  }

  /**
   * 查询管理后台记录摘要列表。
   * 维护说明：响应只包含记录元数据和文本长度，不返回 OCR 全文或 objectKey。
   */
  static async listAdminRecords(): Promise<AdminRecordResponse[]> {
    return V2Service.pageItems(await HttpClient.get<PageResult<AdminRecordResponse> | AdminRecordResponse[]>('/admin/records', { authorized: true }));
  }

  /**
   * 查询单条管理后台记录摘要。
   * 安全边界：Admin 详情仍只暴露记录元数据和文本长度，不返回 OCR 全文、图片 objectKey 或本地/服务端路径。
   */
  static async getAdminRecord(id: number): Promise<AdminRecordResponse> {
    return HttpClient.get<AdminRecordResponse>('/admin/records/' + id.toString(), { authorized: true });
  }

  /**
   * 查询管理后台反馈摘要列表。
   * 安全边界：只展示反馈类型和状态，不携带附件路径、私密联系方式或处理备注。
   */
  static async listAdminFeedback(): Promise<AdminFeedbackResponse[]> {
    return V2Service.pageItems(await HttpClient.get<PageResult<AdminFeedbackResponse> | AdminFeedbackResponse[]>('/admin/feedback', { authorized: true }));
  }

  /**
   * 查询单条管理后台反馈摘要。
   * 维护说明：这里只读反馈元数据；移动端不封装回复反馈或处理反馈写动作，避免 UI 误导为已开放客服工作流。
   */
  static async getAdminFeedback(id: number): Promise<AdminFeedbackResponse> {
    return HttpClient.get<AdminFeedbackResponse>('/admin/feedback/' + id.toString(), { authorized: true });
  }

  /**
   * 查询管理后台审计日志。
   * 维护说明：日志只用于管理操作追踪，不包含请求体、Token、API Key 或 OCR 文本。
   */
  static async listAdminAuditLogs(): Promise<AdminAuditLogResponse[]> {
    return V2Service.pageItems(await HttpClient.get<PageResult<AdminAuditLogResponse> | AdminAuditLogResponse[]>('/admin/audit-logs', { authorized: true }));
  }

  /**
   * 查询单条管理后台审计日志。
   * 安全边界：响应只包含动作、目标类型、目标 ID 和时间，不承载请求体、认证信息、API Key 或 OCR 文本。
   */
  static async getAdminAuditLog(id: number): Promise<AdminAuditLogResponse> {
    return HttpClient.get<AdminAuditLogResponse>('/admin/audit-logs/' + id.toString(), { authorized: true });
  }

  /**
   * 将系统相册返回的图片规范化为后端允许的 JPEG/PNG/WebP。
   * 安全边界：只在内存中检查魔数和必要时转码，不记录 URI、图片 bytes 或 OCR 文本。
   */
  private static async normalizeBatchUploadPart(
    selection: DeviceImageSelection,
    content: Uint8Array
  ): Promise<BatchMultipartFilePart> {
    const normalized: NormalizedImageUpload = await ImageUploadNormalizeService.normalizeSelectionForUpload(selection, content);
    return {
      fileName: normalized.fileName,
      mimeType: normalized.mimeType,
      content: normalized.content
    };
  }

  /**
   * 上传批量 OCR 失败 item 的重试图片。
   * 安全边界：图片字节和 Authorization 只进入当前 multipart 请求，不写入日志、页面状态或本地持久化。
   */
  private static async uploadBatchRetry(
    jobId: string,
    itemIndex: number,
    filePart: BatchMultipartFilePart,
    accessToken: string,
    language: string,
    saveToHistory: boolean
  ): Promise<BatchOcrTaskSummaryResponse> {
    const boundary = `----HarmonyOcrBatchRetry${Date.now()}`;
    const body = V2Service.buildBatchRetryMultipartBody(
      boundary,
      filePart.fileName,
      filePart.mimeType,
      filePart.content,
      language,
      saveToHistory
    );
    const response = await V2Service.postMultipartRequest(
      '/ocr/batches/' + encodeURIComponent(jobId) + '/items/' + itemIndex.toString() + '/retry',
      accessToken,
      boundary,
      body,
      Math.max(ApiConfig.REQUEST_TIMEOUT_MS, 60000)
    );
    return await V2Service.parseBatchMultipartResponse(response.rawBody, response.statusCode, '批量重试');
  }

  /**
   * 发起 multipart/form-data 请求并返回原始响应字符串。
   * 安全边界：Authorization 仅保留在当前请求头内存中，不进入页面状态、日志或异常消息。
   */
  private static async postMultipartRequest(
    path: string,
    accessToken: string,
    boundary: string,
    body: ArrayBuffer,
    readTimeoutMs: number
  ): Promise<MultipartRequestResponse> {
    const requestTask = http.createHttp();
    try {
      const response = await requestTask.request(
        `${ApiConfig.BASE_URL}${ApiConfig.API_PREFIX}${path}`,
        {
          method: http.RequestMethod.POST,
          header: {
            'Authorization': `Bearer ${accessToken}`,
            'Content-Type': `multipart/form-data; boundary=${boundary}`
          },
          connectTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
          readTimeout: readTimeoutMs,
          expectDataType: http.HttpDataType.STRING,
          extraData: body
        }
      );
      return {
        rawBody: String(response.result),
        statusCode: response.responseCode
      };
    } finally {
      requestTask.destroy();
    }
  }

  /**
   * 解析批量 OCR multipart 响应并映射为前端任务摘要。
   * 安全边界：401 / UNAUTHORIZED / AUTH_TOKEN_EXPIRED 会统一清理本地 Token；不会回传原始响应体、图片 bytes 或 Authorization。
   */
  private static async parseBatchMultipartResponse(
    rawBody: string,
    statusCode: number,
    actionLabel: string
  ): Promise<BatchOcrTaskSummaryResponse> {
    try {
      const apiResponse = JSON.parse(rawBody) as ApiResponse<BatchOcrJobCreateResponse>;
      if (!apiResponse.success) {
        await V2Service.clearTokensIfUnauthorized(statusCode, apiResponse.code);
        throw new ApiError(apiResponse.code, apiResponse.message, statusCode);
      }
      if (apiResponse.data === undefined) {
        throw new ApiError('INVALID_RESPONSE', actionLabel + '响应缺少结果数据', statusCode);
      }
      return V2Service.mapBatchJobResponse(apiResponse.data);
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      await V2Service.clearTokensIfUnauthorized(statusCode);
      throw new ApiError('INVALID_RESPONSE', actionLabel + '响应格式错误', statusCode);
    }
  }

  /**
   * 将批量任务响应映射为前端现有摘要 DTO。
   * 维护说明：result 字段在映射时直接丢弃，避免 OCR 全文扩散到前端批量列表。
   */
  private static mapBatchJobResponse(job: BatchOcrJobCreateResponse): BatchOcrTaskSummaryResponse {
    return {
      jobId: job.jobId,
      status: job.status,
      recordId: job.recordId,
      total: job.total,
      completed: job.completed,
      failed: job.failed,
      progress: job.progress,
      createdAt: undefined,
      items: V2Service.mapBatchItems(job.items ?? [])
    };
  }

  /**
   * 将后端批量任务 item 映射为前端可直接展示的脱敏摘要。
   * 这里拆成显式函数，避免 ArkTS 对 map 返回匿名对象的推断失败。
   */
  private static mapBatchItems(items: BatchOcrJobCreateItemResponse[]): BatchOcrTaskItemSummaryResponse[] {
    const mappedItems: BatchOcrTaskItemSummaryResponse[] = [];
    items.forEach((item: BatchOcrJobCreateItemResponse) => {
      mappedItems.push({
        itemIndex: item.itemIndex,
        fileName: item.fileName,
        status: item.status,
        recordId: item.recordId,
        errorCode: item.errorCode,
        failureReason: item.failureReason
      });
    });
    return mappedItems;
  }

  /**
   * 构造批量 OCR 创建请求的 multipart/form-data 请求体。
   * 参数 files 中仅保留脱敏文件名、mimeType 和 bytes；language 与 saveToHistory 为可选业务字段。
   */
  private static buildBatchCreateMultipartBody(
    boundary: string,
    files: BatchMultipartFilePart[],
    language: string,
    saveToHistory: boolean
  ): ArrayBuffer {
    const encoder = util.TextEncoder.create('utf-8');
    const parts: Uint8Array[] = [];
    files.forEach((file: BatchMultipartFilePart, index: number) => {
      const safeName = V2Service.sanitizeMultipartFileName(file.fileName);
      const safeMimeType = file.mimeType.length > 0 ? file.mimeType : 'application/octet-stream';
      const prefix = index === 0
        ? `--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="${safeName}"\r\nContent-Type: ${safeMimeType}\r\n\r\n`
        : `\r\n--${boundary}\r\nContent-Disposition: form-data; name="files"; filename="${safeName}"\r\nContent-Type: ${safeMimeType}\r\n\r\n`;
      parts.push(encoder.encodeInto(prefix));
      parts.push(file.content);
    });
    if (language.length > 0) {
      parts.push(encoder.encodeInto(`\r\n--${boundary}\r\nContent-Disposition: form-data; name="language"\r\n\r\n${language}`));
    }
    parts.push(encoder.encodeInto(
      `\r\n--${boundary}\r\nContent-Disposition: form-data; name="saveToHistory"\r\n\r\n${saveToHistory ? 'true' : 'false'}`
    ));
    parts.push(encoder.encodeInto(`\r\n--${boundary}--\r\n`));

    let totalLength = 0;
    parts.forEach((part: Uint8Array) => {
      totalLength += part.length;
    });
    const body = new Uint8Array(totalLength);
    let offset = 0;
    parts.forEach((part: Uint8Array) => {
      body.set(part, offset);
      offset += part.length;
    });
    return body.buffer;
  }

  /**
   * 清理 multipart 文件名中的危险字符。
   * 维护说明：只保留安全展示名，不向请求体注入换行、引号或路径分隔符。
   */
  private static sanitizeMultipartFileName(fileName: string): string {
    if (fileName.length === 0) {
      return 'image.jpg';
    }
    return fileName.replace(/["\r\n\\/]+/g, '_');
  }

  /**
   * 在 401 / UNAUTHORIZED / AUTH_TOKEN_EXPIRED 场景下统一清理本地 Token。
   * 安全边界：只触发本地失效，不输出 Token 内容，也不向页面暴露鉴权细节。
   */
  private static async clearTokensIfUnauthorized(statusCode: number, code?: string): Promise<void> {
    if (statusCode === 401 || code === 'UNAUTHORIZED' || code === 'AUTH_TOKEN_EXPIRED') {
      await TokenStorage.clearTokens();
    }
  }

  /**
   * 构造批量 OCR 重试 multipart/form-data 请求体。
   * 参数 fileName 会清理换行和引号；content 只在内存中拼装，不写入缓存或日志。
   */
  private static buildBatchRetryMultipartBody(
    boundary: string,
    fileName: string,
    mimeType: string,
    content: Uint8Array,
    language: string,
    saveToHistory: boolean
  ): ArrayBuffer {
    const encoder = util.TextEncoder.create('utf-8');
    const safeName = fileName.replace(/["\r\n]/g, '_');
    const prefix = encoder.encodeInto(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${safeName}"\r\n` +
      `Content-Type: ${mimeType}\r\n\r\n`
    );
    const languagePart = language.length > 0
      ? encoder.encodeInto(
          `\r\n--${boundary}\r\n` +
          `Content-Disposition: form-data; name="language"\r\n\r\n${language}`
        )
      : new Uint8Array(0);
    const savePart = encoder.encodeInto(
      `\r\n--${boundary}\r\n` +
      `Content-Disposition: form-data; name="saveToHistory"\r\n\r\n${saveToHistory ? 'true' : 'false'}`
    );
    const suffix = encoder.encodeInto(`\r\n--${boundary}--\r\n`);
    const body = new Uint8Array(prefix.length + content.length + languagePart.length + savePart.length + suffix.length);
    body.set(prefix, 0);
    body.set(content, prefix.length);
    body.set(languagePart, prefix.length + content.length);
    body.set(savePart, prefix.length + content.length + languagePart.length);
    body.set(suffix, prefix.length + content.length + languagePart.length + savePart.length);
    return body.buffer;
  }
}
