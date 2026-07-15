import { MockOcrService } from './MockOcrService';
import { DeviceImageSelection } from './DeviceOcrModels';
import { OcrMockImage, OcrResult, OcrSourceType, PdfOcrRecognizeResponse, PdfOcrPageResult, OcrTextBlock } from './OcrModels';

/**
 * OcrFlowState 保存 OCR Mock 主流程的当前临时状态，属于 features/ocr 模块。
 * 维护说明：该状态只存在于前端内存中；保存历史由结果页调用 records API，本对象不发起网络请求、不保存 Token。
 */
export class OcrFlowState {
  private static sourceType: OcrSourceType = 'camera';
  private static result?: OcrResult;
  private static selectedImage?: DeviceImageSelection;
  private static imageObjectKey: string = '';

  /**
   * 开始一轮新的 Mock OCR 流程。
   * 参数 sourceType 来自首页入口；调用后清空上一轮结果，避免结果页展示旧数据。
   */
  static start(sourceType: OcrSourceType): void {
    OcrFlowState.sourceType = sourceType;
    OcrFlowState.result = undefined;
    OcrFlowState.selectedImage = undefined;
    OcrFlowState.imageObjectKey = '';
  }

  /**
   * 记录用户主动选择或拍摄得到的短期图片 URI。
   * 参数 selection 只保存在内存中；方法不会持久化 URI、不会上传图片，也不会输出到日志。
   */
  static startWithImage(selection: DeviceImageSelection): void {
    OcrFlowState.sourceType = selection.sourceType;
    OcrFlowState.selectedImage = selection;
    OcrFlowState.result = undefined;
    OcrFlowState.imageObjectKey = '';
  }

  /**
   * 获取当前 OCR 来源类型。
   * 返回值只用于页面路由和展示分支，不包含图片 URI 或 OCR 文本。
   */
  static getSourceType(): OcrSourceType {
    return OcrFlowState.sourceType;
  }

  /**
   * 获取当前来源对应的 Mock 图片说明。
   * 返回值只用于 UI 占位展示，不包含图片二进制、本地路径或对象存储 key。
   */
  static getMockImage(): OcrMockImage {
    return MockOcrService.getMockImage(OcrFlowState.sourceType);
  }

  /**
   * 获取本轮用户选择的短期图片引用。
   * 安全边界：调用方只能在当前 OCR 流程内使用，不得持久化 uri 或写入日志。
   */
  static getSelectedImage(): DeviceImageSelection | undefined {
    return OcrFlowState.selectedImage;
  }

  /**
   * 用新的本轮图片替换当前短期图片引用。
   * 该方法用于真实裁剪输出接管后续 Stub OCR、upload 和 record 链路；只更新内存态，不记录 URI、不上传文件、不生成 objectKey。
   */
  static replaceSelectedImage(selection: DeviceImageSelection): void {
    OcrFlowState.sourceType = selection.sourceType;
    OcrFlowState.selectedImage = selection;
    OcrFlowState.imageObjectKey = '';
  }

  /**
   * 清理本轮图片 URI。
   * 用于图片上传并保存记录成功后释放短期 URI；保留 OCR 结果文本，便于结果页继续展示。
   */
  static clearSelectedImage(): void {
    OcrFlowState.selectedImage = undefined;
  }

  /**
   * 判断是否存在可继续处理的本轮图片。
   * 返回 true 只代表内存中有短期 URI，不代表文件仍可被系统授权读取。
   */
  static hasSelectedImage(): boolean {
    return OcrFlowState.selectedImage !== undefined && OcrFlowState.selectedImage.uri.length > 0;
  }

  /**
   * 写入上传成功后由后端生成的对象 key。
   * 参数 objectKey 必须来自 files/upload 响应；不得由前端根据用户、路径或文件名自行拼接。
   */
  static setImageObjectKey(objectKey: string): void {
    OcrFlowState.imageObjectKey = objectKey;
  }

  /**
   * 获取上传成功后的对象 key。
   * 安全边界：objectKey 只能提交给 records API 关联当前记录，不应展示给用户或拼接下载 URL。
   */
  static getImageObjectKey(): string {
    return OcrFlowState.imageObjectKey;
  }

  /**
   * 写入 Mock OCR 结果。
   * 参数 result 只在内存中保存；保存历史时由结果页显式调用 records API，不在状态对象中发起网络请求。
   */
  static setResult(result: OcrResult): void {
    OcrFlowState.sourceType = result.sourceType;
    OcrFlowState.result = result;
  }

  /**
   * 写入后端 PDF OCR 的真实结果。
   * 参数 response 来自 /ocr/pdf/recognize；方法只保存脱敏页级摘要和文本结果，不保存 PDF URI、路径或对象 key。
   */
  static setPdfResult(response: PdfOcrRecognizeResponse): void {
    const blocks: OcrTextBlock[] = [];
    const pages: PdfOcrPageResult[] = response.pages ?? [];
    for (let pageIndex = 0; pageIndex < pages.length; pageIndex++) {
      const page = pages[pageIndex];
      const pageBlocks = page.blocks ?? [];
      for (let blockIndex = 0; blockIndex < pageBlocks.length; blockIndex++) {
        blocks.push(pageBlocks[blockIndex]);
      }
    }
    OcrFlowState.sourceType = 'pdf';
    OcrFlowState.selectedImage = undefined;
    OcrFlowState.imageObjectKey = '';
    OcrFlowState.result = {
      sourceType: 'pdf',
      rawText: response.rawText,
      editedText: response.editedText && response.editedText.length > 0 ? response.editedText : response.rawText,
      durationMs: response.durationMs,
      language: response.language,
      ocrEngine: response.engineName,
      providerName: response.providerName,
      engineName: response.engineName,
      mode: response.mode,
      errorCode: response.errorCode,
      blocks: blocks,
      fallbackUsed: true,
      recordId: response.recordId,
      pdfSummary: {
        pageCount: response.pageCount,
        successPageCount: response.successPageCount,
        failedPageCount: response.failedPageCount,
        partial: response.partial
      },
      pdfPages: pages
    };
  }

  /**
   * 获取当前 OCR 结果。
   * 返回值可能包含隐私文本，只允许结果页、保存历史和用户主动导出流程消费。
   */
  static getResult(): OcrResult | undefined {
    return OcrFlowState.result;
  }

  /**
   * 更新结果页编辑后的文本。
   * 参数 text 是用户当前编辑内容；方法不记录全文，也不持久化到设备或后端。
   */
  static updateEditedText(text: string): void {
    if (OcrFlowState.result) {
      OcrFlowState.result.editedText = text;
    }
  }

  /**
   * 清空 OCR 流程内存状态。
   * 说明：该方法不删除后端历史、不删除对象存储文件，也不清理 Token。
   */
  static clear(): void {
    OcrFlowState.sourceType = 'camera';
    OcrFlowState.result = undefined;
    OcrFlowState.selectedImage = undefined;
    OcrFlowState.imageObjectKey = '';
  }
}
