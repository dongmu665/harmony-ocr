import { util } from '@kit.ArkTS';
import { http } from '@kit.NetworkKit';
import { ApiConfig } from '../../common/config/ApiConfig';
import { ApiError, ApiResponse } from '../../common/network/ApiTypes';
import { TokenStorage } from '../../common/storage/TokenStorage';
import { DevicePdfPickerService, DevicePdfSelection } from '../file/DevicePdfPickerService';
import { PdfOcrRecognizeResponse } from './OcrModels';

/**
 * PdfOcrService 调用后端扫描型 PDF OCR 接口。
 * 维护说明：multipart 请求不写日志，错误提示只使用脱敏文案，不暴露 Token、URI、PDF bytes 或 OCR 全文。
 */
export class PdfOcrService {
  /**
   * 上传本轮授权 PDF 并触发后端 OCR。
   * 参数 selection 必须来自系统文件选择器；返回值包含识别文本但不包含 PDF URI 或本地路径。
   */
  static async recognizePdf(selection: DevicePdfSelection, languageHint: string = ''): Promise<PdfOcrRecognizeResponse> {
    const accessToken = await TokenStorage.getAccessToken();
    if (accessToken.length === 0) {
      throw new ApiError('UNAUTHORIZED', '请先登录后再识别 PDF', 401);
    }
    const content = DevicePdfPickerService.readPdfBytes(selection);
    const boundary = `----HarmonyOcrPdf${Date.now()}`;
    const body = PdfOcrService.buildMultipartBody(boundary, selection.displayName, content, languageHint);
    const requestTask = http.createHttp();
    try {
      const response = await requestTask.request(`${ApiConfig.BASE_URL}${ApiConfig.API_PREFIX}/ocr/pdf/recognize`, {
        method: http.RequestMethod.POST,
        header: {
          'Authorization': `Bearer ${accessToken}`,
          'Content-Type': `multipart/form-data; boundary=${boundary}`
        },
        connectTimeout: ApiConfig.REQUEST_TIMEOUT_MS,
        readTimeout: Math.max(ApiConfig.REQUEST_TIMEOUT_MS, 60000),
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      });
      return await PdfOcrService.parseResponse(String(response.result), response.responseCode);
    } finally {
      requestTask.destroy();
    }
  }

  /**
   * 解析 PDF OCR 统一响应。
   * 安全边界：401 会清理本地 Token；错误提示脱敏，不回传原始响应体或 PDF 内容。
   */
  private static async parseResponse(rawBody: string, statusCode: number): Promise<PdfOcrRecognizeResponse> {
    let apiResponse: ApiResponse<PdfOcrRecognizeResponse>;
    try {
      apiResponse = JSON.parse(rawBody) as ApiResponse<PdfOcrRecognizeResponse>;
    } catch (_) {
      if (statusCode === 401) {
        await TokenStorage.clearTokens();
      }
      if (statusCode === 404) {
        throw new ApiError('NOT_FOUND', '扫描型 PDF 识别服务暂未开放', statusCode);
      }
      throw new ApiError('INVALID_RESPONSE', 'PDF OCR 响应格式错误', statusCode);
    }
    if (!apiResponse.success) {
      if (statusCode === 401 || apiResponse.code === 'UNAUTHORIZED' || apiResponse.code === 'AUTH_TOKEN_EXPIRED') {
        await TokenStorage.clearTokens();
      }
      throw new ApiError(apiResponse.code, PdfOcrService.toUserMessage(apiResponse.code, apiResponse.message, statusCode), statusCode);
    }
    if (apiResponse.data === undefined) {
      throw new ApiError('INVALID_RESPONSE', 'PDF OCR 响应缺少结果数据', statusCode);
    }
    return apiResponse.data;
  }

  /**
   * 构造 PDF OCR multipart/form-data 请求体。
   * 参数 fileName 会被清理换行和引号，PDF 字节仅进入当前请求体，不写入日志。
   */
  private static buildMultipartBody(
    boundary: string,
    fileName: string,
    content: Uint8Array,
    languageHint: string
  ): ArrayBuffer {
    const encoder = util.TextEncoder.create('utf-8');
    const safeName = fileName.replace(/["\r\n]/g, '_');
    const prefix = encoder.encodeInto(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${safeName}"\r\n` +
      `Content-Type: application/pdf\r\n\r\n`
    );
    const languagePart = languageHint.length > 0
      ? encoder.encodeInto(
        `\r\n--${boundary}\r\n` +
        `Content-Disposition: form-data; name="language"\r\n\r\n${languageHint}`
      )
      : new Uint8Array(0);
    const savePart = encoder.encodeInto(
      `\r\n--${boundary}\r\n` +
      `Content-Disposition: form-data; name="saveToHistory"\r\n\r\ntrue`
    );
    const suffix = encoder.encodeInto(`\r\n--${boundary}--\r\n`);
    const body = new Uint8Array(prefix.length + content.length + languagePart.length + savePart.length + suffix.length);
    body.set(prefix, 0);
    body.set(content, prefix.length);
    let offset = prefix.length + content.length;
    if (languagePart.length > 0) {
      body.set(languagePart, offset);
      offset += languagePart.length;
    }
    body.set(savePart, offset);
    offset += savePart.length;
    body.set(suffix, offset);
    return body.buffer;
  }

  /**
   * 将后端错误码转换为用户可读提示。
   * 维护说明：仅返回脱敏文案，不暴露 Provider、文件路径、Token 或原始异常信息。
   */
  private static toUserMessage(code: string, message: string, statusCode: number): string {
    if (statusCode === 404 || code === 'NOT_FOUND') {
      return '扫描型 PDF 识别服务暂未开放';
    }
    switch (code) {
      case 'PDF_ENCRYPTED':
        return '加密 PDF 暂不支持识别';
      case 'PDF_TOO_MANY_PAGES':
        return 'PDF 页数超过当前支持上限';
      case 'FILE_TOO_LARGE':
        return 'PDF 文件过大，请选择较小文件';
      case 'FILE_TYPE_NOT_ALLOWED':
        return '请选择 PDF 文件';
      case 'PDF_INVALID':
        return 'PDF 文件损坏或无法打开';
      case 'QUOTA_EXCEEDED':
        return 'OCR 额度不足，无法继续识别';
      case 'UNAUTHORIZED':
      case 'AUTH_TOKEN_EXPIRED':
        return '登录状态已失效，请重新登录';
      default:
        if (message.length > 0 && message.length < 80) {
          return message;
        }
        return 'PDF OCR 失败，请稍后重试';
    }
  }
}
