import { OcrMockImage, OcrRecognitionOptions, OcrResult, OcrSourceType, OcrTextBlock } from './OcrModels';

/**
 * MockOcrService 提供前端 OCR 主流程的模拟识别能力，属于 features/ocr 模块。
 * 维护说明：服务只返回固定 Mock 文本，不访问网络、不读取真实图片、不上传文件、不保存历史，也不记录 OCR 全文。
 */
export class MockOcrService {
  /**
   * 根据来源返回本地 Mock 图片说明。
   * 参数 sourceType 表示首页入口来源；返回值仅用于页面占位展示，不包含真实文件路径。
   */
  static getMockImage(sourceType: OcrSourceType): OcrMockImage {
    if (sourceType === 'album') {
      return {
        sourceType,
        title: '相册图片 Mock',
        description: '模拟从相册选择的一张票据截图，用于验证预览、裁剪和识别结果链路。'
      };
    }
    return {
      sourceType,
      title: '拍照图片 Mock',
      description: '模拟刚拍摄的一页纸质资料，用于验证 OCR 主流程，不调用真实相机。'
    };
  }

  /**
   * 模拟 OCR 识别并返回固定文本。
   * 参数 sourceType 表示识别来源，options 可控制模拟延迟；返回值包含 Mock 文本、耗时和分块信息。
   */
  static async recognizeFromMockImage(sourceType: OcrSourceType, options?: OcrRecognitionOptions): Promise<OcrResult> {
    const delayMs = options && options.simulateDelayMs !== undefined ? options.simulateDelayMs : 700;
    await MockOcrService.delay(delayMs);

    const blocks: OcrTextBlock[] = sourceType === 'album' ? [
      { order: 1, text: 'Harmony OCR 相册识别 Mock', confidence: 0.96 },
      { order: 2, text: '日期：2026-05-25', confidence: 0.94 },
      { order: 3, text: '请在结果页编辑、复制或清理格式。', confidence: 0.92 }
    ] : [
      { order: 1, text: 'Harmony OCR 拍照识别 Mock', confidence: 0.95 },
      { order: 2, text: '纸质资料已转换为可编辑文本。', confidence: 0.93 },
      { order: 3, text: '模拟模式不调用真实 OCR 引擎。', confidence: 0.91 }
    ];
    const rawText = blocks.map((block: OcrTextBlock) => block.text).join('\n');

    return {
      sourceType,
      rawText,
      editedText: rawText,
      durationMs: sourceType === 'album' ? 1280 : 1460,
      language: 'zh-CN',
      ocrEngine: 'MockOcrService',
      blocks
    };
  }

  /**
   * 提供页面可感知的异步延迟。
   * 参数 delayMs 只影响 loading 展示；返回值无业务数据，不执行外部 IO。
   */
  private static delay(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, delayMs);
    });
  }
}
