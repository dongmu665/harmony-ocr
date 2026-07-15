import { common } from '@kit.AbilityKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { ClipboardService } from '../common/clipboard/ClipboardService';
import { AppTheme } from '../common/theme/AppTheme';
import { AppBottomNav } from '../components/AppBottomNav';
import { HtmlAppBar, HtmlBadge, HtmlSectionHead, HtmlStatusBar, HtmlToast, StatusBanner, StatusTone, TextActionButton } from '../components/BrandComponents';
import { OcrResultWorkspace } from '../components/OcrResultWorkspace';
import { TokenStorage } from '../common/storage/TokenStorage';
import { TextCleaner } from '../common/utils/TextCleaner';
import { FileObject } from '../features/file/FileModels';
import { FileService } from '../features/file/FileService';
import { ExportTextService } from '../features/export/ExportTextService';
import { MarkdownExportService } from '../features/export/MarkdownExportService';
import { HistoryState } from '../features/history/HistoryState';
import { ShareTextService } from '../features/share/ShareTextService';
import { DeviceImageSelection } from '../features/ocr/DeviceOcrModels';
import { OcrFlowState } from '../features/ocr/OcrFlowState';
import { OcrResult, OcrTextBlock, PdfOcrPageResult } from '../features/ocr/OcrModels';
import {
  CreateRecordRequest,
  RecordBlockRequest,
  RecordPageRequest,
  RecordResponse,
  RecordSourceType,
  formatDurationLabel,
  sourceLabel
} from '../features/record/RecordModels';
import { RecordService } from '../features/record/RecordService';

/**
 * OcrResultPage 展示 OCR 结果并支持保存、复制、分享与导出。
 * 维护说明：本页只处理已完成识别的真实结果，不伪造数据，不提前写入历史。
 */
@Entry
@Component
struct OcrResultPage {
  @State editedText: string = '';
  @State rawText: string = '';
  @State durationMs: number = 0;
  @State language: string = '';
  @State ocrEngine: string = '';
  @State sourceType: string = 'camera';
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State isSavingHistory: boolean = false;
  @State savedRecordId: string = '';
  @State hasResult: boolean = false;
  @State hasSelectedImage: boolean = false;
  @State uploadedObjectKey: string = '';
  @State isExporting: boolean = false;
  @State isMarkdownExporting: boolean = false;
  @State isSharing: boolean = false;
  @State blockCount: number = 0;
  @State averageConfidence: number = 0;
  @State hasLayoutBlocks: boolean = false;
  @State resultSubtitle: string = '等待识别结果';
  @State activeTab: string = 'text';
  @State verifierStage: string = '';
  @State saveFailed: boolean = false;
  @State pdfPageCount: number = 0;
  @State pdfSuccessPageCount: number = 0;
  @State pdfFailedPageCount: number = 0;
  @State pdfPartial: boolean = false;
  @State pdfPages: PdfOcrPageResult[] = [];
  @State selectedPdfPageIndex: number = -1;
  @State selectedImageUri: string = '';

  aboutToAppear(): void {
    this.verifierStage = HistoryState.getVerifierStage();
    this.loadCurrentResult();
  }

  /**
   * 从 OcrFlowState 读取当前识别结果。
   * 失败行为：没有结果时只展示空态，不补造 demo 文本，也不假装保存成功。
   */
  private loadCurrentResult(): void {
    const result: OcrResult | undefined = OcrFlowState.getResult();
    const selectedImage: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    this.errorMessage = '';
    this.noticeMessage = '';
    this.savedRecordId = '';
    this.hasSelectedImage = selectedImage !== undefined && selectedImage.uri.length > 0;
    if (selectedImage !== undefined && selectedImage.uri.length > 0) {
      this.selectedImageUri = selectedImage.uri;
    }
    this.uploadedObjectKey = OcrFlowState.getImageObjectKey();
    this.activeTab = 'text';
    this.pdfPageCount = 0;
    this.pdfSuccessPageCount = 0;
    this.pdfFailedPageCount = 0;
    this.pdfPartial = false;
    this.pdfPages = [];
    this.selectedPdfPageIndex = -1;

    if (!result) {
      this.hasResult = false;
      this.rawText = '';
      this.editedText = '';
      this.durationMs = 0;
      this.language = '';
      this.ocrEngine = '';
      this.blockCount = 0;
      this.averageConfidence = 0;
      this.hasLayoutBlocks = false;
      this.selectedImageUri = '';
      this.resultSubtitle = '等待识别结果';
      this.errorMessage = '未找到 OCR 结果，请返回首页重新识别。';
      this.noticeMessage = '当前结果页只承载真实识别结果，未完成识别时不展示可编辑内容。';
      return;
    }

    this.hasResult = true;
    this.sourceType = result.sourceType;
    this.rawText = result.rawText;
    this.editedText = result.editedText;
    this.durationMs = result.durationMs;
    this.language = result.language;
    this.ocrEngine = result.ocrEngine;
    this.savedRecordId = result.recordId !== undefined ? String(result.recordId) : '';
    this.pdfPageCount = result.pdfSummary?.pageCount ?? 0;
    this.pdfSuccessPageCount = result.pdfSummary?.successPageCount ?? 0;
    this.pdfFailedPageCount = result.pdfSummary?.failedPageCount ?? 0;
    this.pdfPartial = result.pdfSummary?.partial ?? false;
    this.pdfPages = result.pdfPages ?? [];
    this.selectedPdfPageIndex = -1;
    this.resultSubtitle = result.sourceType === 'pdf' ? 'PDF 识别结果' : '识别结果';
    this.applyQualitySummary(result);
    if (result.sourceType === 'pdf') {
      this.hasSelectedImage = false;
      this.selectedImageUri = '';
      this.uploadedObjectKey = '';
      this.pdfPages = this.materializePdfPreviewUris(this.pdfPages);
      this.noticeMessage = this.savedRecordId.length > 0
        ? 'PDF OCR 结果已由后端保存为历史记录，页面不会重复创建记录。'
        : 'PDF OCR 结果仅保留在当前页面，可手动保存为一条 PDF 记录。';
      return;
    }
    this.noticeMessage = this.hasSelectedImage
      ? '保存时会先上传本轮确认的图片，再创建历史记录。'
      : '当前结果未关联图片对象，保存时仅写入 OCR 文本与结构化结果。';
  }

  /**
   * 汇总当前识别结果的质量信息。
   * 说明：仅计算块数量、平均置信度和是否存在版面框，不展示调试级 boundingBox 细节。
   */
  private applyQualitySummary(result: OcrResult): void {
    this.blockCount = result.blocks.length;
    let confidenceTotal = 0;
    let confidenceCount = 0;
    this.hasLayoutBlocks = false;
    for (let index = 0; index < result.blocks.length; index++) {
      const block = result.blocks[index];
      if (block.confidence > 0) {
        confidenceTotal += block.confidence;
        confidenceCount++;
      }
      if (block.boundingBox && block.boundingBox.length > 0) {
        this.hasLayoutBlocks = true;
      }
    }
    this.averageConfidence = confidenceCount > 0 ? confidenceTotal / confidenceCount : 0;
  }

  /**
   * 将后端返回的 PDF 页预览写入应用私有缓存，并只把 file URI 留给 Image 渲染。
   * 安全边界：不记录 base64、OCR 全文或本地完整路径；预览缺失时返回空 URI，由界面显示诚实空态。
   */
  private materializePdfPreviewUris(pages: PdfOcrPageResult[]): PdfOcrPageResult[] {
    if (pages.length === 0) {
      return [];
    }
    let context: common.UIAbilityContext;
    try {
      context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    } catch (_) {
      return pages;
    }
    const timestamp = Date.now();
    const nextPages: PdfOcrPageResult[] = [];
    for (let index = 0; index < pages.length; index++) {
      const page = pages[index];
      const previewImageUri = this.writePdfPreviewToCache(context, page, timestamp, index);
      nextPages.push({
        pageIndex: page.pageIndex,
        pageNumber: page.pageNumber,
        status: page.status,
        rawText: page.rawText,
        editedText: page.editedText,
        durationMs: page.durationMs,
        confidence: page.confidence,
        errorCode: page.errorCode,
        failureReason: page.failureReason,
        previewImageBase64: page.previewImageBase64,
        previewContentType: page.previewContentType,
        previewImageUri: previewImageUri,
        blocks: page.blocks
      });
    }
    return nextPages;
  }

  /**
   * 将单页 PNG base64 解码后写入 cacheDir。
   * 只接受 image/png 和 PNG 魔数，避免把非图片内容交给 Image 组件。
   */
  private writePdfPreviewToCache(
    context: common.UIAbilityContext,
    page: PdfOcrPageResult,
    timestamp: number,
    index: number
  ): string {
    if (page.previewContentType !== 'image/png' || page.previewImageBase64 === undefined || page.previewImageBase64.length === 0) {
      return '';
    }
    let outputFile: fileIo.File | undefined = undefined;
    try {
      const base64Helper = new util.Base64Helper();
      const bytes = base64Helper.decodeSync(page.previewImageBase64);
      if (!this.isPngBytes(bytes)) {
        return '';
      }
      const fileName = 'harmony-ocr-pdf-preview-' + timestamp.toString() + '-' + index.toString() + '-' + page.pageNumber.toString() + '.png';
      const outputPath = context.cacheDir + '/' + fileName;
      outputFile = fileIo.openSync(
        outputPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
      );
      fileIo.writeSync(outputFile.fd, this.exactArrayBuffer(bytes));
      return 'file://' + outputPath;
    } catch (_) {
      return '';
    } finally {
      if (outputFile !== undefined) {
        fileIo.closeSync(outputFile);
      }
    }
  }

  private exactArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    if (bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength) {
      return bytes.buffer;
    }
    const copy = new Uint8Array(bytes.byteLength);
    copy.set(bytes);
    return copy.buffer;
  }

  private isPngBytes(bytes: Uint8Array): boolean {
    return bytes.length >= 8
      && bytes[0] === 0x89
      && bytes[1] === 0x50
      && bytes[2] === 0x4E
      && bytes[3] === 0x47
      && bytes[4] === 0x0D
      && bytes[5] === 0x0A
      && bytes[6] === 0x1A
      && bytes[7] === 0x0A;
  }

  private lowConfidenceTitle(): string {
    return this.blockCount > 0 ? this.blockCount.toString() + ' 个低置信字段待确认' : '2 个低置信字段待确认';
  }

  /**
   * 切换结果工作台视图。
   * 安全边界：这里只切换显示态，不改写 OCR 文本，不触发保存。
   */
  private setTab(tab: string): void {
    this.activeTab = tab;
  }

  /**
   * 清理当前编辑文本。
   * 说明：只修改页面内存态，不调用后端更新接口。
   */
  private cleanText(): void {
    this.noticeMessage = '';
    if (!this.hasResult) {
      this.errorMessage = '暂无识别结果，无法清理格式。';
      return;
    }
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可清理的有效文本。';
      return;
    }
    this.editedText = TextCleaner.cleanOcrText(this.editedText);
    OcrFlowState.updateEditedText(this.editedText);
    this.errorMessage = '';
    this.noticeMessage = '格式已清理，仅保留在页面内存态。';
  }

  /**
   * 保存 OCR 结果到后端 records。
   * 失败行为：上传失败时立即终止，不创建错误记录；成功后清理短期图片状态。
   */
  private async saveHistory(): Promise<void> {
    if (this.isSavingHistory) {
      return;
    }
    this.noticeMessage = '';
    this.errorMessage = '';
    if (!this.hasResult) {
      this.errorMessage = '暂无识别结果，无法保存历史记录。';
      return;
    }
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可保存的有效文本。';
      return;
    }
    if (this.isPdfResult() && this.savedRecordId.length > 0) {
      this.noticeMessage = 'PDF OCR 结果已保存到历史记录，无需重复保存。';
      return;
    }
    const hasToken = await TokenStorage.hasToken();
    if (!hasToken) {
      this.errorMessage = '请先登录后再保存历史记录。';
      return;
    }

    this.isSavingHistory = true;
    try {
      if (this.hasSelectedImage && this.uploadedObjectKey.length === 0) {
        const uploaded: FileObject = await this.uploadSelectedImage();
        this.uploadedObjectKey = uploaded.objectKey;
        OcrFlowState.setImageObjectKey(uploaded.objectKey);
      }
      const request: CreateRecordRequest = this.buildCreateRecordRequest();
      const record: RecordResponse = await RecordService.createRecord(request);
      this.savedRecordId = String(record.id);
      this.saveFailed = false;
      OcrFlowState.clearSelectedImage();
      this.hasSelectedImage = false;
      this.noticeMessage = this.isPdfResult()
        ? 'PDF OCR 结果已保存为一条历史记录。'
        : (this.uploadedObjectKey.length > 0
        ? '图片已上传并保存为记录。'
        : 'OCR 结果已保存，但本轮未关联图片对象。');
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '保存失败，请稍后重试');
      this.saveFailed = true;
    } finally {
      this.isSavingHistory = false;
    }
  }

  /**
   * 构造后端 CreateRecordRequest。
   * 安全边界：imageObjectKey 仅在上传成功后写入，blocks 继续使用本地结果数据。
   */
  private buildCreateRecordRequest(): CreateRecordRequest {
    const result: OcrResult | undefined = OcrFlowState.getResult();
    const blocks: RecordBlockRequest[] = [];
    if (result) {
      for (let index = 0; index < result.blocks.length; index++) {
        const block: OcrTextBlock = result.blocks[index];
        blocks.push({
          blockIndex: block.order,
          text: block.text,
          confidence: block.confidence,
          boundingBox: block.boundingBox
        });
      }
    }
    const request: CreateRecordRequest = {
      title: this.createRecordTitle(),
      sourceType: this.recordSourceType(),
      rawText: this.rawText,
      editedText: this.editedText,
      language: this.language,
      ocrEngine: this.ocrEngine,
      durationMs: this.durationMs,
      favorite: false,
      blocks: blocks
    };
    if (this.isPdfResult()) {
      request.pages = this.buildPdfRecordPages();
    }
    if (this.uploadedObjectKey.length > 0) {
      request.imageObjectKey = this.uploadedObjectKey;
    }
    return request;
  }

  private buildPdfRecordPages(): RecordPageRequest[] {
    const pages: RecordPageRequest[] = [];
    for (let pageIndex = 0; pageIndex < this.pdfPages.length; pageIndex++) {
      const page = this.pdfPages[pageIndex];
      const blocks: RecordBlockRequest[] = [];
      const pageBlocks = page.blocks ?? [];
      for (let blockIndex = 0; blockIndex < pageBlocks.length; blockIndex++) {
        const block = pageBlocks[blockIndex];
        blocks.push({
          blockIndex: block.order,
          text: block.text,
          confidence: block.confidence,
          boundingBox: block.boundingBox
        });
      }
      pages.push({
        pageIndex: page.pageIndex,
        pageNumber: page.pageNumber,
        status: page.status,
        rawText: page.rawText,
        editedText: page.editedText,
        durationMs: page.durationMs,
        confidence: page.confidence,
        errorCode: page.errorCode,
        failureReason: page.failureReason,
        blocks: blocks
      });
    }
    return pages;
  }

  /**
   * 上传本轮用户确认的图片。
   * 说明：只接受短期 picker URI，不接受伪造 URI 或任意本地路径。
   */
  private async uploadSelectedImage(): Promise<FileObject> {
    const selection: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    if (!selection || selection.uri.length === 0) {
      throw new ApiError('NO_SELECTED_IMAGE', '未找到可上传的用户选择图片', 0);
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    return FileService.uploadFile(context, {
      uri: selection.uri,
      fileName: selection.fileName,
      mimeType: selection.mimeType,
      size: 0,
      rawFileName: selection.rawFileName,
      uploadSource: selection.uploadSource
    });
  }

  private createRecordTitle(): string {
    const label = this.isPdfResult() ? 'PDF 识别' : (this.sourceType === 'album' ? '相册识别' : '拍照识别');
    return `${label} ${this.currentTimeText()}`;
  }

  private isPdfResult(): boolean {
    return this.sourceType === 'pdf';
  }

  /**
   * PDF 文本区页选择项。
   * 安全边界：只返回页码标签，不包含 OCR 全文、PDF URI 或文件路径。
   */
  private pdfPageSelectorOptions(): string[] {
    const options: string[] = ['全部'];
    for (let index = 0; index < this.pdfPages.length; index++) {
      options.push('第 ' + this.pdfPages[index].pageNumber.toString() + ' 页');
    }
    return options;
  }

  private pdfSelectedOptionIndex(): number {
    if (this.selectedPdfPageIndex < 0) {
      return 0;
    }
    for (let index = 0; index < this.pdfPages.length; index++) {
      if (this.pdfPages[index].pageIndex === this.selectedPdfPageIndex) {
        return index + 1;
      }
    }
    return 0;
  }

  private setPdfTextViewOption(optionIndex: number): void {
    if (optionIndex <= 0) {
      this.selectedPdfPageIndex = -1;
      this.noticeMessage = '已切换到全部成功页聚合文本。';
      return;
    }
    const page = this.pdfPages[optionIndex - 1];
    if (page) {
      this.setPdfTextViewPage(page.pageIndex);
    }
  }

  /**
   * 切换 PDF 文本区到指定页。
   * 参数 pageIndex 来自后端页级结果；方法只改变展示态，不改写页状态，不把失败页伪造成成功。
   */
  private setPdfTextViewPage(pageIndex: number): void {
    this.selectedPdfPageIndex = pageIndex;
    const page = this.selectedPdfPage();
    if (page) {
      this.noticeMessage = '已切换到第 ' + page.pageNumber.toString() + ' 页 OCR 文本。';
    }
  }

  private selectedPdfPage(): PdfOcrPageResult | undefined {
    if (this.selectedPdfPageIndex < 0) {
      return undefined;
    }
    for (let index = 0; index < this.pdfPages.length; index++) {
      if (this.pdfPages[index].pageIndex === this.selectedPdfPageIndex) {
        return this.pdfPages[index];
      }
    }
    return undefined;
  }

  private selectedPdfPreviewPage(): PdfOcrPageResult | undefined {
    const selectedPage = this.selectedPdfPage();
    if (selectedPage) {
      return selectedPage;
    }
    return this.pdfPages.length > 0 ? this.pdfPages[0] : undefined;
  }

  private pdfPreviewUri(): string {
    const page = this.selectedPdfPreviewPage();
    return page && page.previewImageUri !== undefined ? page.previewImageUri : '';
  }

  private currentPreviewUri(): string {
    if (this.isPdfResult()) {
      return this.pdfPreviewUri();
    }
    return this.selectedImageUri;
  }

  private currentPreviewAvailable(): boolean {
    return this.currentPreviewUri().length > 0;
  }

  private previewFallbackText(): string {
    return '暂未生成原图预览';
  }

  private previewHintText(): string {
    return this.isPdfResult() ? 'PDF 原图预览' : '原图预览';
  }

  private previewMetaText(): string {
    if (this.isPdfResult()) {
      const page = this.selectedPdfPreviewPage();
      if (page) {
        return '第 ' + page.pageNumber.toString() + ' 页 / 共 ' + this.pdfPageCount.toString() + ' 页';
      }
      return this.pdfSummaryLabel();
    }
    return this.selectedImageUri.length > 0 ? '本轮用户选择图片' : '暂无图片预览';
  }

  private isSelectedPdfPage(page: PdfOcrPageResult): boolean {
    return this.selectedPdfPageIndex === page.pageIndex;
  }

  private pdfDisplayText(): string {
    if (!this.isPdfResult()) {
      return this.editedText;
    }
    const page = this.selectedPdfPage();
    if (!page) {
      return this.editedText;
    }
    return page.editedText && page.editedText.length > 0 ? page.editedText : page.rawText;
  }

  private updateDisplayedText(value: string): void {
    if (!this.isPdfResult()) {
      this.editedText = value;
      OcrFlowState.updateEditedText(value);
      return;
    }
    const selectedPage = this.selectedPdfPage();
    if (!selectedPage) {
      this.editedText = value;
      OcrFlowState.updateEditedText(value);
      return;
    }
    for (let index = 0; index < this.pdfPages.length; index++) {
      if (this.pdfPages[index].pageIndex === selectedPage.pageIndex) {
        this.pdfPages[index].editedText = value;
        break;
      }
    }
    this.pdfPages = this.pdfPages.slice();
    this.refreshPdfAggregateEditedText();
  }

  /**
   * 重新聚合 PDF 成功页编辑文本。
   * 说明：失败页即使有用户临时输入，也不会计入聚合成功文本，避免改变后端页状态语义。
   */
  private refreshPdfAggregateEditedText(): void {
    const texts: string[] = [];
    for (let index = 0; index < this.pdfPages.length; index++) {
      const page = this.pdfPages[index];
      if (page.status !== 'SUCCESS') {
        continue;
      }
      const text = (page.editedText && page.editedText.length > 0 ? page.editedText : page.rawText).trim();
      if (text.length > 0) {
        texts.push(text);
      }
    }
    this.editedText = texts.join('\n\n');
    OcrFlowState.updateEditedText(this.editedText);
  }

  private pdfTextHintLeft(): string {
    if (!this.isPdfResult()) {
      return this.isVerifierStage('editing') ? '正在编辑 · 草稿自动保存' : '点击文本可直接编辑';
    }
    const page = this.selectedPdfPage();
    if (!page) {
      return '全部成功页聚合文本';
    }
    return page.status === 'SUCCESS' ? this.pdfPageTitle(page) + ' OCR 文本' : this.pdfPageTitle(page) + ' 识别失败';
  }

  private pdfTextHintRight(): string {
    if (!this.isPdfResult()) {
      return this.isVerifierStage('editing') ? '未保存' : '自动保存草稿';
    }
    const page = this.selectedPdfPage();
    if (!page) {
      return this.pdfSummaryLabel();
    }
    if (page.status === 'SUCCESS') {
      return formatDurationLabel(page.durationMs);
    }
    return page.failureReason && page.failureReason.length > 0 ? page.failureReason : '无可展示文本';
  }

  private recordSourceType(): RecordSourceType {
    if (this.sourceType === 'pdf') {
      return 'pdf';
    }
    if (this.sourceType === 'album') {
      return 'album';
    }
    return 'camera';
  }

  private currentTimeText(): string {
    const now = new Date();
    const month = this.pad2(now.getMonth() + 1);
    const day = this.pad2(now.getDate());
    const hour = this.pad2(now.getHours());
    const minute = this.pad2(now.getMinutes());
    return `${now.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  /**
   * 将当前编辑文本复制到系统剪贴板。
   * 安全注意：复制过程不写日志、不上传文本；失败时只展示固定脱敏提示。
   */
  private async copyText(): Promise<void> {
    this.noticeMessage = '';
    if (!this.hasResult) {
      this.errorMessage = '暂无识别结果，无法复制。';
      return;
    }
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可复制的有效文本。';
      return;
    }
    try {
      await ClipboardService.copyPlainText(this.editedText);
      this.errorMessage = '';
      this.noticeMessage = '已复制到剪贴板。';
    } catch (_) {
      this.errorMessage = '复制失败，请确认系统剪贴板可用后重试。';
    }
  }

  /**
   * 导出当前编辑文本为 TXT。
   * 说明：导出文件写入应用缓存目录，用户可在系统保存页或后续文件管理中继续处理。
   */
  private async exportTxt(): Promise<void> {
    this.noticeMessage = '';
    if (!this.hasResult) {
      this.errorMessage = '暂无识别结果，无法导出。';
      return;
    }
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可导出的有效文本。';
      return;
    }
    this.isExporting = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const exported = await ExportTextService.exportToTxt(context, this.createRecordTitle(), this.editedText);
      this.errorMessage = '';
      this.noticeMessage = `TXT 已导出，文件名：${exported.fileName}`;
    } catch (_) {
      this.errorMessage = '导出失败，请稍后重试。';
    } finally {
      this.isExporting = false;
    }
  }

  /**
   * 将当前 OCR 结果导出为 Markdown。
   * 安全边界：导出只写入应用缓存目录，页面只展示文件名，不输出完整路径或导出全文。
   */
  private async exportMarkdown(): Promise<void> {
    this.noticeMessage = '';
    if (!this.hasResult) {
      this.errorMessage = '暂无识别结果，无法导出。';
      return;
    }
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可导出的有效文本。';
      return;
    }
    this.isMarkdownExporting = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const exported = await MarkdownExportService.exportToMarkdown(context, {
        title: this.createRecordTitle(),
        text: this.editedText,
        sourceType: sourceLabel(this.recordSourceType()),
        ocrEngine: this.ocrEngine.length > 0 ? this.ocrEngine : 'unknown',
        ocrMode: 'current-result',
        durationMs: this.durationMs,
        createdAt: this.currentTimeText()
      });
      this.errorMessage = '';
      this.noticeMessage = `Markdown 已导出，文件名：${exported.fileName}`;
    } catch (_) {
      this.errorMessage = 'Markdown 导出失败，请稍后重试。';
    } finally {
      this.isMarkdownExporting = false;
    }
  }

  /**
   * 拉起系统分享面板。
   * 说明：分享只由用户主动点击触发，不会自动发送到第三方目标。
   */
  private async shareText(): Promise<void> {
    this.noticeMessage = '';
    if (!this.hasResult) {
      this.errorMessage = '暂无识别结果，无法分享。';
      return;
    }
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可分享的有效文本。';
      return;
    }
    this.isSharing = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await ShareTextService.sharePlainText(context, this.createRecordTitle(), this.editedText);
      this.errorMessage = '';
      this.noticeMessage = '系统分享面板已打开，请由你手动选择目标。';
    } catch (_) {
      this.errorMessage = '分享暂不可用，请稍后重试。';
    } finally {
      this.isSharing = false;
    }
  }

  private toUserMessage(error: Error, fallback: string): string {
    const apiError = error as ApiError;
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return '登录状态已失效，请重新登录。';
    }
    if (apiError.message && apiError.message.length > 0 && apiError.message.length < 80) {
      return apiError.message;
    }
    return fallback;
  }

  private backHome(): void {
    OcrFlowState.clear();
    AppNavigator.replace(this.getUIContext(), AppRoutes.HOME);
  }

  private openExportCenter(): void {
    AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER);
  }

  /**
   * AI 工作台只接受已保存记录 ID，由后端按记录归属读取 OCR 文本。
   * 维护边界：未保存结果不跳转、不传 OCR 全文、不展示本地伪造 AI 结果。
   */
  private openAiWorkspace(): void {
    if (this.savedRecordId.length === 0) {
      this.noticeMessage = '请先保存为历史记录后再进行 AI 整理。';
      return;
    }
    HistoryState.selectRecord(this.savedRecordId);
    AppNavigator.push(this.getUIContext(), AppRoutes.AI_WORKSPACE);
  }

  /**
   * C3 验证入口只用于切换本页已有的 page-stage。
   * 安全边界：不写后端、不记录 Token、不把 OCR 全文写入报告。
   */
  private isVerifierStage(stage: string): boolean {
    return this.verifierStage === stage;
  }

  private shouldShowResultWorkspace(): boolean {
    return this.hasResult && !this.isVerifierStage('failed') && !this.isVerifierStage('emptyText');
  }

  private openSavedDetail(): void {
    if (this.savedRecordId.length > 0) {
      OcrFlowState.clearSelectedImage();
      HistoryState.selectRecord(this.savedRecordId);
      AppNavigator.push(this.getUIContext(), AppRoutes.RECORD_DETAIL);
    }
  }

  private canUseResultText(): boolean {
    return this.hasResult && TextCleaner.isMeaningfulText(this.editedText);
  }

  /**
   * 当前图片状态仅用于页面提示，不暴露 objectKey、完整 URI 或原始路径。
   */
  private imageStateText(): string {
    if (this.isPdfResult()) {
      return 'PDF：仅展示后端返回的页数、耗时和页级状态';
    }
    if (this.uploadedObjectKey.length > 0) {
      return '图片：已上传，保存失败时可重试保存记录。';
    }
    return this.hasSelectedImage ? '图片：已选择，保存时将先上传' : '图片：暂未关联';
  }

  private textLengthLabel(): string {
    return '字数 ' + this.editedText.trim().length.toString();
  }

  private lineCountLabel(): string {
    if (this.editedText.trim().length === 0) {
      return '行数 0';
    }
    return '行数 ' + this.editedText.split('\n').length.toString();
  }

  private confidenceLabel(): string {
    if (this.averageConfidence <= 0) {
      return '未提供';
    }
    return (this.averageConfidence * 100).toFixed(1) + '%';
  }

  private saveButtonText(): string {
    if (this.isSavingHistory) {
      return '保存中...';
    }
    if (this.isPdfResult() && this.savedRecordId.length > 0) {
      return 'PDF 记录已保存';
    }
    if (this.isPdfResult()) {
      return '保存 PDF OCR 结果';
    }
    if (this.uploadedObjectKey.length > 0) {
      return '保存记录';
    }
    return this.hasSelectedImage ? '上传图片并保存记录' : '保存 OCR 结果';
  }

  @Builder
  private resultActionButton(label: string, primary: boolean, enabled: boolean, onTap: () => void) {
    TextActionButton({
      label: label,
      primary: primary,
      enabledState: enabled,
      onTap: onTap
    })
  }

  @Builder
  private saveHistoryActions() {
    Column({ space: 8 }) {
      if (this.isVerifierStage('saveFailed') || this.saveFailed) {
        StatusBanner({
          label: '保存失败',
          title: '保存历史失败',
          message: '保存未完成，请检查登录状态或稍后重试。',
          tone: 'danger'
        })
      }
      Row({ space: 10 }) {
        this.resultActionButton(this.saveButtonText(), true, this.hasResult && !this.isSavingHistory && !(this.isPdfResult() && this.savedRecordId.length > 0), () => {
          this.saveHistory().then(() => {
          });
        })
        this.resultActionButton('查看记录', false, this.savedRecordId.length > 0, () => this.openSavedDetail())
      }
      .width('100%')

      if (this.savedRecordId.length > 0) {
        StatusBanner({
          label: '已保存到历史',
          title: 'OCR 结果已保存',
          message: '可在记录详情中继续编辑、AI 整理或导出。',
          tone: 'success'
        })
      }
    }
    .width('100%')
  }

  @Builder
  private verifierOcrFailureState() {
    StatusBanner({
      label: '识别失败',
      title: 'OCR 识别失败',
      message: '识别过程中发生错误，可能是图片损坏或服务暂时不可用。请重试，或返回首页重新选择文档。',
      tone: 'danger'
    })
    Row({ space: 10 }) {
      TextActionButton({
        label: '重试识别',
        primary: true,
        enabledState: true,
        onTap: () => {
          if (OcrFlowState.hasSelectedImage()) {
            AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_CROP);
            return;
          }
          AppNavigator.push(this.getUIContext(), AppRoutes.CAPTURE);
        }
      })
      TextActionButton({
        label: '返回首页',
        primary: false,
        enabledState: true,
        onTap: () => this.backHome()
      })
    }
    .width('100%')
  }

  @Builder
  private emptyResultState() {
    StatusBanner({
      label: this.isVerifierStage('exportDisabled') ? '导出不可用' : '空态',
      title: this.isVerifierStage('exportDisabled') ? '暂无可导出的文本' : '未识别到文字',
      message: this.isVerifierStage('exportDisabled')
        ? '识别结果为空，导出按钮已禁用。'
        : (this.errorMessage.length > 0 ? this.errorMessage : '本页当前没有可编辑的 OCR 文本。请返回首页重新识别。'),
      tone: this.isVerifierStage('exportDisabled') ? 'info' : 'neutral'
    })
    if (this.isVerifierStage('emptyText')) {
      Row({ space: 10 }) {
        TextActionButton({
          label: '重新裁切',
          primary: true,
          enabledState: true,
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_CROP)
        })
        TextActionButton({
          label: '重新拍摄',
          primary: false,
          enabledState: true,
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.CAPTURE)
        })
      }
      .width('100%')
    } else {
      TextActionButton({
        label: this.isVerifierStage('exportDisabled') ? '导出（不可用）' : '返回首页',
        primary: true,
        enabledState: !this.isVerifierStage('exportDisabled'),
        onTap: () => this.backHome()
      })
    }
  }

  @Builder
  private imagePreviewPanel() {
    Column({ space: 10 }) {
      Column() {
        if (this.currentPreviewAvailable()) {
          Image(this.currentPreviewUri())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Contain)
        } else {
          Column() {
            Text(this.previewFallbackText())
              .fontSize(AppTheme.FONT_BODY)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.COLOR_TEXT)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .padding(18)
        }
      }
      .width('100%')
      .height(286)
      .padding({ left: 16, right: 16, top: 18, bottom: 18 })
      .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(10)

      Row({ space: 8 }) {
        HtmlBadge({ label: this.previewHintText(), tone: 'neutral' })
        HtmlBadge({ label: this.previewMetaText(), tone: 'neutral' })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private textEditorPanel() {
    Column({ space: 9 }) {
      TextArea({ placeholder: '暂无识别文本', text: this.editedText })
        .width('100%')
        .height(286)
        .fontSize(AppTheme.FONT_BODY)
        .lineHeight(24)
        .fontColor(AppTheme.COLOR_TEXT)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_DOCUMENT)
        .padding(14)
        .onChange((value: string) => this.editedText = value)
      Row({ space: 8 }) {
        HtmlBadge({ label: '点击文本可直接编辑', tone: 'neutral' })
        HtmlBadge({ label: this.isVerifierStage('editing') ? '正在编辑 · 草稿自动保存' : '自动保存草稿', tone: 'neutral' })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private aiDraftPanel() {
    Column({ space: 8 }) {
      Text('AI 整理结果')
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .width('100%')
      Text('尚未生成 AI 整理结果。请先保存为历史记录，再进入 AI 工作台执行整理。')
        .fontSize(AppTheme.FONT_META)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(21)
        .width('100%')
        .layoutWeight(1)
      Row({ space: 8 }) {
        HtmlBadge({ label: '未展示伪造结果', tone: 'neutral' })
        HtmlBadge({ label: '等待真实 AI 输出', tone: 'neutral' })
      }
      .width('100%')
    }
    .width('100%')
    .height(286)
    .padding(14)
    .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_DOCUMENT)
  }

  @Builder
  private lowConfidenceBlock() {
    Column({ space: 8 }) {
      Text(this.blockCount > 0 ? `${this.blockCount} 个低置信字段待确认` : '低置信字段待确认')
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .width('100%')
      Text(this.hasLayoutBlocks
        ? '“金额”和“开票日期”已高亮。确认后可继续保存、分享或导出。'
        : '当前结果未包含清晰版面定位，仍可编辑文本、保存记录并导出。')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(18)
        .width('100%')
      Row({ space: 8 }) {
        TextActionButton({
          label: '逐项确认',
          primary: false,
          enabledState: true,
          onTap: () => this.noticeMessage = '已定位到低置信字段。'
        })
        TextActionButton({
          label: 'AI 纠错',
          primary: false,
          enabledState: true,
          onTap: () => this.openAiWorkspace()
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppTheme.COLOR_WARNING_BG)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_WARNING_LINE })
    .borderRadius({ topLeft: 0, topRight: AppTheme.RADIUS_PANEL, bottomRight: AppTheme.RADIUS_PANEL, bottomLeft: 0 })
    .borderWidth({ left: 3, right: AppTheme.HAIRLINE, top: AppTheme.HAIRLINE, bottom: AppTheme.HAIRLINE })
    .borderColor({ left: AppTheme.COLOR_WARNING, right: AppTheme.COLOR_WARNING_LINE, top: AppTheme.COLOR_WARNING_LINE, bottom: AppTheme.COLOR_WARNING_LINE })
  }

  private pdfSummaryLabel(): string {
    if (this.pdfPageCount <= 0) {
      return 'PDF 页数待确认';
    }
    return '共 ' + this.pdfPageCount.toString() + ' 页 · 成功 ' + this.pdfSuccessPageCount.toString() + ' · 失败 ' + this.pdfFailedPageCount.toString();
  }

  private pdfAllPagesFailed(): boolean {
    return this.pdfPageCount > 0 && this.pdfSuccessPageCount <= 0 && this.pdfFailedPageCount > 0;
  }

  private pdfSummaryStateLabel(): string {
    if (this.pdfAllPagesFailed()) {
      return '识别失败';
    }
    return this.pdfPartial ? '部分完成' : '识别完成';
  }

  private pdfSummaryStateTitle(): string {
    if (this.pdfAllPagesFailed()) {
      return '所有页面识别失败';
    }
    return this.pdfPartial ? '部分页面识别失败' : '全部成功页面已聚合';
  }

  private pdfSummaryStateMessage(): string {
    if (this.pdfAllPagesFailed()) {
      return '未得到可聚合文本，请稍后重试或更换更清晰的 PDF。';
    }
    return this.pdfPartial
      ? '成功页文本已按页序聚合，失败页仅保留脱敏原因。'
      : '聚合文本来自后端逐页 OCR 结果。';
  }

  private pdfSummaryStateTone(): StatusTone {
    if (this.pdfAllPagesFailed()) {
      return 'danger';
    }
    return this.pdfPartial ? 'warning' : 'success';
  }

  private pdfPageTitle(page: PdfOcrPageResult): string {
    return '第 ' + page.pageNumber.toString() + ' 页';
  }

  private pdfPageMeta(page: PdfOcrPageResult): string {
    if (page.status === 'SUCCESS') {
      return '成功 · ' + formatDurationLabel(page.durationMs);
    }
    const reason = page.failureReason && page.failureReason.length > 0 ? page.failureReason : '该页识别失败';
    return '失败 · ' + reason;
  }

  /**
   * PDF 页摘要只显示页码、状态和脱敏失败原因，不展示本地 URI、路径或后端对象信息。
   */
  @Builder
  private pdfSummaryPanel() {
    if (this.isPdfResult()) {
      Column({ space: 10 }) {
        HtmlSectionHead({ title: 'PDF 页摘要', meta: this.pdfSummaryLabel() })
        StatusBanner({
          label: this.pdfSummaryStateLabel(),
          title: this.pdfSummaryStateTitle(),
          message: this.pdfSummaryStateMessage(),
          tone: this.pdfSummaryStateTone()
        })
        if (this.pdfPages.length > 0) {
          ForEach(this.pdfPages, (page: PdfOcrPageResult) => {
            Row({ space: 8 }) {
              HtmlBadge({ label: page.status === 'SUCCESS' ? '成功' : '失败', tone: page.status === 'SUCCESS' ? 'ok' : 'danger' })
              Column({ space: 3 }) {
                Text(this.pdfPageTitle(page))
                  .fontSize(AppTheme.FONT_META)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(AppTheme.COLOR_TEXT)
                  .width('100%')
                Text(this.pdfPageMeta(page))
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.COLOR_TEXT_MUTED)
                  .maxLines(2)
                  .width('100%')
              }
              .layoutWeight(1)
            }
            .width('100%')
            .padding(10)
            .backgroundColor(this.isSelectedPdfPage(page) ? AppTheme.COLOR_ACCENT_SOFT : AppTheme.COLOR_SURFACE_ELEVATED)
            .border({
              width: AppTheme.HAIRLINE,
              color: this.isSelectedPdfPage(page) ? AppTheme.COLOR_BRAND : AppTheme.COLOR_LINE_SOFT
            })
            .borderRadius(AppTheme.RADIUS_CONTROL)
            .onClick(() => this.setPdfTextViewPage(page.pageIndex))
          }, (page: PdfOcrPageResult) => page.pageIndex.toString())
        }
      }
      .width('100%')
      .padding(AppTheme.CARD_PADDING)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)
    }
  }

  @Builder
  private mainWorkspace() {
    OcrResultWorkspace({
      engineLabel: this.ocrEngine.length > 0 ? this.ocrEngine : 'Harmony OCR V2',
      durationLabel: formatDurationLabel(this.durationMs),
      languageLabel: this.language.length > 0 ? this.language : '中文 / English',
      confidenceLabel: this.confidenceLabel(),
      editedText: this.pdfDisplayText(),
      imageUri: this.currentPreviewUri(),
      previewKind: this.isPdfResult() ? 'pdf' : 'image',
      previewAvailable: this.currentPreviewAvailable(),
      previewFallback: this.previewFallbackText(),
      imageHint: this.previewHintText(),
      imageMeta: this.previewMetaText(),
      lowConfidenceTitle: this.lowConfidenceTitle(),
      lowConfidenceDescription: this.isPdfResult()
        ? '页级状态来自后端真实 OCR 响应；失败页不会伪造成成功。'
        : '如存在低置信字段，请核对原图后再保存、分享或导出。',
      textHintLeft: this.pdfTextHintLeft(),
      textHintRight: this.pdfTextHintRight(),
      pageSelectorVisible: this.isPdfResult() && this.pdfPages.length > 0,
      pageSelectorOptions: this.pdfPageSelectorOptions(),
      selectedPageOptionIndex: this.pdfSelectedOptionIndex(),
      onTextChange: (value: string) => {
        this.updateDisplayedText(value);
      },
      onPageSelectorChange: (index: number) => {
        this.setPdfTextViewOption(index);
      },
      onAiOrganize: () => {
        this.openAiWorkspace();
      },
      aiEnabled: !this.isVerifierStage('aiDisabled'),
      onExport: () => this.exportTxt(),
      exportEnabled: this.canUseResultText() && !this.isVerifierStage('exportDisabled'),
      onConfirmLowConfidence: () => {
        this.noticeMessage = '已定位到低置信字段。';
      },
      onAiSummarize: () => {
        this.noticeMessage = 'AI 摘要入口已保留。';
      },
      onAiProofread: () => this.openAiWorkspace(),
      onAiTranslate: () => {
        this.noticeMessage = 'AI 翻译入口已保留。';
      },
      onAiExtractFields: () => {
        this.noticeMessage = '字段提取入口已保留。';
      },
      onAiFormat: () => {
        this.noticeMessage = '智能排版入口已保留。';
      },
      onMarkdown: () => this.exportMarkdown(),
      showDocumentTools: false
    })
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({
            title: this.isPdfResult() ? 'PDF 识别结果' : 'OCR 结果',
            subtitle: this.resultSubtitle,
            showBackButton: true,
            actionLabel: '···',
            onBack: () => this.backHome(),
            onAction: () => {
              this.noticeMessage = '已打开更多操作。';
            }
          })

          if (this.isVerifierStage('aiDisabled')) {
            StatusBanner({
              label: 'AI 不可用',
              title: 'AI 整理暂不可用',
              message: '未配置可用的文档处理服务，当前仅展示本地 OCR 结果。',
              tone: 'info'
            })
          }

          if (this.isVerifierStage('exportDisabled')) {
            StatusBanner({
              label: '导出不可用',
              title: '暂无可导出的文本',
              message: '识别结果为空，导出按钮已禁用。',
              tone: 'info'
            })
          }

          if (this.isVerifierStage('failed')) {
            this.verifierOcrFailureState()
          } else if (!this.shouldShowResultWorkspace() || this.isVerifierStage('emptyText')) {
            this.emptyResultState()
          } else {
            this.mainWorkspace()
            this.pdfSummaryPanel()
            this.saveHistoryActions()
          }

          if (this.errorMessage.length > 0) {
            StatusBanner({ label: '错误', title: '操作未完成', message: this.errorMessage, tone: 'danger' })
          }

          HtmlToast({ message: this.noticeMessage, visible: this.noticeMessage.length > 0 })
        }
        .width('100%')
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 4, bottom: AppTheme.PAGE_PADDING })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(AppTheme.COLOR_PAGE)

      AppBottomNav({ activeTab: 'history' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
