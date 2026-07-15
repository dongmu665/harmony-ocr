import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { ApiError } from '../../common/network/ApiTypes';
import { TextCleaner } from '../../common/utils/TextCleaner';
import { BackendOcrService } from './BackendOcrService';
import { DeviceImageSelection, DeviceOcrPlaceholder, DeviceOcrRequest } from './DeviceOcrModels';
import { ImageCropService } from './ImageCropService';
import { OcrRecognitionOptions, OcrResult, OcrSourceType, OcrTextBlock } from './OcrModels';
import { UserPreferenceService } from '../settings/UserPreferenceService';

/**
 * DeviceOcrService 是 V1.0 OCR 的统一入口，属于 features/ocr 模块。
 * 维护说明：正式路径优先使用 HarmonyOS CoreVisionKit；当前 API 15 模拟器缺少 textRecognition runtime 时，自动调用后端真实 OCR fallback。
 */
export class DeviceOcrService {
  /**
   * 创建 OCR 能力说明。
   * 参数 request 仅用于 UI 展示来源和阶段；返回值不包含图片 URI、文件路径、对象存储 key 或敏感配置。
   */
  static createPlaceholder(request: DeviceOcrRequest): DeviceOcrPlaceholder {
    const sourceLabel = request.sourceType === 'album' ? '相册' : '拍照';
    return {
      sourceType: request.sourceType,
      stage: request.stage,
      status: 'real_device_ocr',
      title: sourceLabel + ' OCR 已接入',
      message: '优先使用 HarmonyOS CoreVisionKit；端侧 runtime 不可用时使用后端真实 OCR fallback。'
    };
  }

  /**
   * 识别当前用户授权的真实图片。
   * 参数 context 用于读取图片，selection 必须来自系统 picker、拍照结果、裁剪缓存或 debug/test rawfile；返回 OcrResult 供结果页保存历史。
   * 安全注意：端侧失败原因和后端 fallback 结果都不输出 Token、URI、图片内容或 OCR 全文。
   */
  static async recognizeSelection(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection,
    options?: OcrRecognitionOptions
  ): Promise<OcrResult> {
    if (selection.uri.length === 0) {
      throw new Error('未找到可识别的图片，请重新选择后再试');
    }
    if (options?.simulateDelayMs && options.simulateDelayMs > 0) {
      await DeviceOcrService.delay(options.simulateDelayMs);
    }

    const preferences = await UserPreferenceService.load(context);
    const languageHint = options?.languageHint && options.languageHint.length > 0
      ? options.languageHint
      : UserPreferenceService.toBackendLanguageHint(preferences.recognitionLanguage);

    try {
      return DeviceOcrService.applyPreferenceResult(
        await DeviceOcrService.recognizeByCoreVisionKit(context, selection),
        preferences.autoCleanFormat
      );
    } catch (deviceError) {
      return DeviceOcrService.applyPreferenceResult(
        await DeviceOcrService.recognizeByBackendFallback(context, selection, deviceError as Error, languageHint),
        preferences.autoCleanFormat
      );
    }
  }

  /**
   * 调用 HarmonyOS CoreVisionKit 识别图片。
   * 当前 API 15 模拟器可能出现 textRecognition 或 init undefined，该异常会交给上层 fallback。
   */
  private static async recognizeByCoreVisionKit(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection
  ): Promise<OcrResult> {
    const startTime = Date.now();
    let pixelMap: image.PixelMap | undefined = undefined;
    let initialized = false;
    try {
      pixelMap = await ImageCropService.createPixelMapFromSelection(context, selection);
      initialized = await textRecognition.init();
      if (!initialized) {
        throw new Error('CoreVisionKit textRecognition init failed');
      }
      const sdkResult = await textRecognition.recognizeText(
        { pixelMap: pixelMap },
        { isDirectionDetectionSupported: true }
      );
      const result = DeviceOcrService.toOcrResult(selection.sourceType, sdkResult, Date.now() - startTime);
      if (result.rawText.length === 0) {
        throw new Error('CoreVisionKit OCR result is empty');
      }
      return result;
    } finally {
      if (initialized) {
        await DeviceOcrService.releaseTextRecognition();
      }
      if (pixelMap !== undefined) {
        await pixelMap.release();
      }
    }
  }

  /**
   * 调用后端真实 OCR fallback。
   * 参数 cause 是端侧失败原因，仅用于组合脱敏错误，不写入日志；fallback 成功时结果会标记 fallbackUsed。
   */
  private static async recognizeByBackendFallback(
    context: common.UIAbilityContext,
    selection: DeviceImageSelection,
    cause: Error,
    languageHint: string
  ): Promise<OcrResult> {
    try {
      return await BackendOcrService.recognizeSelection(context, selection, languageHint);
    } catch (fallbackError) {
      throw DeviceOcrService.toUserError(cause, fallbackError as Error);
    }
  }

  /**
   * 将 CoreVisionKit 结果映射为当前历史记录模型。
   * SDK 未暴露可信置信度时统一写 0，避免把不可验证分值伪装成真实评分。
   */
  private static toOcrResult(
    sourceType: OcrSourceType,
    sdkResult: textRecognition.TextRecognitionResult,
    durationMs: number
  ): OcrResult {
    const rawText = DeviceOcrService.normalizeText(sdkResult.value);
    const blocks: OcrTextBlock[] = DeviceOcrService.toBlocks(sdkResult, rawText);
    return {
      sourceType: sourceType,
      rawText: rawText,
      editedText: rawText,
      durationMs: durationMs,
      language: 'auto',
      ocrEngine: 'HarmonyOS CoreVisionKit textRecognition',
      providerName: 'device',
      engineName: 'CoreVisionKit textRecognition',
      mode: 'single-image',
      blocks: blocks,
      fallbackUsed: false
    };
  }

  /**
   * 生成文本块列表。
   * 参数 sdkResult 来自端侧 OCR；当 SDK 返回空 blocks 但有全文时，创建单块以保证历史保存链路完整。
   */
  private static toBlocks(
    sdkResult: textRecognition.TextRecognitionResult,
    rawText: string
  ): OcrTextBlock[] {
    const blocks: OcrTextBlock[] = [];
    sdkResult.blocks.forEach((block: textRecognition.TextBlock, index: number) => {
      const text = DeviceOcrService.normalizeText(block.value);
      if (text.length > 0) {
        blocks.push({
          order: index + 1,
          text: text,
          confidence: 0
        });
      }
    });
    if (blocks.length === 0 && rawText.length > 0) {
      blocks.push({
        order: 1,
        text: rawText,
        confidence: 0
      });
    }
    return blocks;
  }

  private static normalizeText(text: string): string {
    return text.replace(/\r\n/g, '\n').trim();
  }

  private static async releaseTextRecognition(): Promise<void> {
    try {
      await textRecognition.release();
    } catch (_) {
    }
  }

  private static async delay(durationMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, durationMs);
    });
  }

  private static toUserError(deviceError: Error, fallbackError?: Error): Error {
    if (fallbackError instanceof ApiError) {
      if (fallbackError.statusCode === 401 || fallbackError.code === 'UNAUTHORIZED') {
        return new ApiError('UNAUTHORIZED', '登录已失效，请重新登录后再识别', 401);
      }
      return fallbackError;
    }
    if (fallbackError !== undefined && fallbackError.message &&
      fallbackError.message.length > 0 && fallbackError.message.length < 80) {
      return new Error(`端侧 OCR 不可用，后端 OCR fallback 失败：${fallbackError.message}`);
    }
    if (deviceError.message && deviceError.message.length > 0 && deviceError.message.length < 80) {
      return deviceError;
    }
    return new Error('OCR 识别失败，请确认后端 OCR 服务可用后重试');
  }

  private static applyPreferenceResult(result: OcrResult, autoCleanFormat: boolean): OcrResult {
    if (!autoCleanFormat) {
      return result;
    }
    const cleanedBlocks: OcrTextBlock[] = [];
    result.blocks.forEach((block: OcrTextBlock) => {
      cleanedBlocks.push(block);
    });
    return {
      sourceType: result.sourceType,
      rawText: result.rawText,
      editedText: TextCleaner.cleanOcrText(result.editedText),
      durationMs: result.durationMs,
      language: result.language,
      ocrEngine: result.ocrEngine,
      providerName: result.providerName,
      engineName: result.engineName,
      mode: result.mode,
      confidence: result.confidence,
      boundingBox: result.boundingBox,
      errorCode: result.errorCode,
      blocks: cleanedBlocks,
      fallbackUsed: result.fallbackUsed
    };
  }
}
