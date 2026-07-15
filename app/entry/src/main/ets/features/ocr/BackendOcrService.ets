import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../../common/config/ApiConfig';
import { ApiError, ApiResponse } from '../../common/network/ApiTypes';
import { TokenStorage } from '../../common/storage/TokenStorage';
import { DeviceImageSelection } from './DeviceOcrModels';
import { ImageCropService } from './ImageCropService';
import { ImageUploadNormalizeService, NormalizedImageUpload } from './ImageUploadNormalizeService';
import { OcrResult, OcrTextBlock } from './OcrModels';

/**
 * BackendOcrBlock 表示后端 OCR 返回的文本块。
 * 维护说明：这里只映射接口字段，不保存图片来源、Token 或对象存储 key。
 */
interface BackendOcrBlock {
  order: number;
  text: string;
  confidence: number;
  boundingBox?: string;
}

/**
 * BackendOcrResponse 表示后端单图 OCR 的脱敏响应。
 * 安全边界：包含 OCR 文本但不包含上传文件路径、Authorization 或 Provider 内部异常栈。
 */
interface BackendOcrResponse {
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
  blocks: BackendOcrBlock[];
}

/**
 * BackendOcrService 封装 V1.0 后端真实 OCR fallback，属于 features/ocr 模块。
 * 维护说明：仅在端侧 CoreVisionKit 不可用或返回空时调用后端 /api/v1/ocr/recognize，不使用 Mock 文本、不写死测试期望。
 */
export class BackendOcrService {
  /**
   * 将当前授权图片提交给后端真实 OCR Provider。
   * 参数 context 用于读取应用 rawfile/cache 文件，selection 必须来自当前 OCR 流程；返回值映射为现有 OcrResult。
   * 安全注意：Authorization 只放入请求头，不输出 Token、URI、图片内容或 OCR 全文。
   */
  static async recognizeSelection(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection,
    languageHint: string = ''
  ): Promise<OcrResult> {
    const accessToken = await TokenStorage.getAccessToken();
    if (accessToken.length === 0) {
      throw new ApiError('UNAUTHORIZED', '请先登录后再使用后端 OCR fallback', 401);
    }
    const content = await BackendOcrService.readSelectionBytes(context, selection);
    const normalized = await ImageUploadNormalizeService.normalizeSelectionForUpload(selection, content);
    const response = await BackendOcrService.uploadForRecognition(normalized, accessToken, languageHint);
    const rawText = BackendOcrService.normalizeText(response.rawText);
    if (rawText.length === 0) {
      throw new ApiError('OCR_FAILED', '后端 OCR 未识别到文字', 502);
    }
    return {
      sourceType: selection.sourceType,
      rawText: rawText,
      editedText: BackendOcrService.normalizeText(response.editedText.length > 0 ? response.editedText : rawText),
      durationMs: response.durationMs,
      language: response.language,
      ocrEngine: `Backend ${response.ocrEngine}`,
      providerName: response.providerName,
      engineName: response.engineName,
      mode: response.mode,
      confidence: response.confidence,
      boundingBox: response.boundingBox,
      errorCode: response.errorCode,
      blocks: BackendOcrService.toBlocks(response.blocks, rawText),
      fallbackUsed: true
    };
  }

  /**
   * 读取当前选择图片字节。
   * debug/test rawfile 使用资源管理器读取；普通 cache 文件仅接受 file:// 路径，避免枚举图库或持久化 URI。
   */
  private static async readSelectionBytes(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection
  ): Promise<Uint8Array> {
    try {
      return await ImageCropService.readSelectionBytes(context, selection);
    } catch (_) {
      throw new ApiError('OCR_FALLBACK_UNSUPPORTED_URI', '当前图片 URI 暂不支持后端 OCR fallback，请重新选择后再试', 0);
    }
  }

  /**
   * 使用手工 multipart 调用后端 OCR 接口。
   * 该方法不记录 multipart 内容、Authorization 或后端返回全文。
   */
  private static async uploadForRecognition(
    file: NormalizedImageUpload,
    accessToken: string,
    languageHint: string
  ): Promise<BackendOcrResponse> {
    const boundary = `----HarmonyOcrBackend${Date.now()}`;
    const body = BackendOcrService.buildMultipartBody(
      boundary,
      file.fileName,
      file.mimeType,
      file.content,
      languageHint
    );
    const requestTask = http.createHttp();
    try {
      const response = await requestTask.request(`${ApiConfig.BASE_URL}${ApiConfig.API_PREFIX}/ocr/recognize`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`
        },
        connectTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        readTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      });
      return BackendOcrService.parseResponse(String(response.result), response.responseCode);
    } finally {
      requestTask.destroy();
    }
  }

  /**
   * 解析后端 OCR 统一响应。
   * 参数 rawBody 只在内存中解析；错误分支返回脱敏提示，不记录 OCR 全文或响应原文。
   */
  private static parseResponse(rawBody: string, statusCode: number): BackendOcrResponse {
    try {
      const apiResponse = JSON.parse(rawBody) as ApiResponse<BackendOcrResponse>;
      if (!apiResponse.success) {
        throw new ApiError(apiResponse.code, apiResponse.message, statusCode);
      }
      if (apiResponse.data === undefined) {
        throw new ApiError('INVALID_RESPONSE', '后端 OCR 响应缺少数据', statusCode);
      }
      return apiResponse.data;
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError('INVALID_RESPONSE', '后端 OCR 响应格式错误', statusCode);
    }
  }

  /**
   * 构造单图 OCR multipart/form-data 请求体。
   * 安全边界：文件名会移除换行和引号，body 不被日志输出，languageHint 只作为识别提示字段。
   */
  private static buildMultipartBody(
    boundary: string,
    fileName: string,
    mimeType: string,
    content: Uint8Array,
    languageHint: string
  ): ArrayBuffer {
    const encoder = util.TextEncoder.create('utf-8');
    const safeName = fileName.replace(/["\r\n]/g, '_');
    const prefix = encoder.encodeInto(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${safeName}"\r\n` +
      `Content-Type: ${mimeType}\r\n\r\n`
    );
    const languagePart = languageHint.length > 0
      ? encoder.encodeInto(
          `\r\n--${boundary}\r\n` +
          `Content-Disposition: form-data; name="language"\r\n\r\n${languageHint}`
        )
      : new Uint8Array(0);
    const suffix = encoder.encodeInto(`\r\n--${boundary}--\r\n`);
    const body = new Uint8Array(prefix.length + content.length + languagePart.length + suffix.length);
    body.set(prefix, 0);
    body.set(content, prefix.length);
    if (languagePart.length > 0) {
      body.set(languagePart, prefix.length + content.length);
      body.set(suffix, prefix.length + content.length + languagePart.length);
    } else {
      body.set(suffix, prefix.length + content.length);
    }
    return body.buffer;
  }

  /**
   * 将后端文本块映射为前端 OcrTextBlock。
   * 参数 rawText 用作无块结果兜底，避免结果页空白；方法不记录完整文本。
   */
  private static toBlocks(blocks: BackendOcrBlock[], rawText: string): OcrTextBlock[] {
    const mapped: OcrTextBlock[] = [];
    blocks.forEach((block: BackendOcrBlock, index: number) => {
      const text = BackendOcrService.normalizeText(block.text);
      if (text.length > 0) {
        mapped.push({
          order: block.order > 0 ? block.order : index + 1,
          text: text,
          confidence: block.confidence,
          boundingBox: block.boundingBox
        });
      }
    });
    if (mapped.length === 0) {
      mapped.push({ order: 1, text: rawText, confidence: 0 });
    }
    return mapped;
  }

  /**
   * 统一换行并去除首尾空白。
   * 说明：该方法只做展示前规范化，不改变后端 rawText 的保存策略。
   */
  private static normalizeText(text: string): string {
    return text.replace(/\r\n/g, '\n').trim();
  }
}
