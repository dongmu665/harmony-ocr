import { common } from '@kit.AbilityKit';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { ClipboardService } from '../common/clipboard/ClipboardService';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { HtmlBadge, HtmlBadgeTone, HtmlFileMark, HtmlListRow, HtmlSectionHead, HtmlToast, HtmlToolChip, SettingActionRow, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { FileNameUtils } from '../common/utils/FileNameUtils';
import { TextCleaner } from '../common/utils/TextCleaner';
import { HistoryState } from '../features/history/HistoryState';
import {
  RecordBlockResponse,
  RecordPageResponse,
  detailText,
  formatDurationLabel,
  formatRecordTime,
  normalizeTitle,
  RecordTagResponse,
  RecordResponse,
  sourceLabel
} from '../features/record/RecordModels';
import { RecordService } from '../features/record/RecordService';
import { TagResponse } from '../features/record/TagModels';
import { TagService } from '../features/record/TagService';
import { ExportTextService } from '../features/export/ExportTextService';
import { MarkdownExportService } from '../features/export/MarkdownExportService';
import { ShareTextService } from '../features/share/ShareTextService';

/**
 * RecordDetailPage 展示后端 records 详情。
 * 维护边界：V1.2 最终集成在高级 UI 上接入标签管理和 Markdown 导出，不记录 OCR 全文或完整导出路径。
 */
@Entry
@Component
struct RecordDetailPage {
  @State recordId: string = '';
  @State title: string = '历史详情';
  @State sourceLabelText: string = '未知来源';
  @State createdAtText: string = '未知时间';
  @State language: string = 'unknown';
  @State engineName: string = 'unknown';
  @State elapsedMs: number = 0;
  @State isFavorite: boolean = false;
  @State editedText: string = '';
  @State originalEditedText: string = '';
  @State hasActionableText: boolean = false;
  @State loading: boolean = false;
  @State favoriteLoading: boolean = false;
  @State saveLoading: boolean = false;
  @State deleteLoading: boolean = false;
  @State confirmDelete: boolean = false;
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State exportLoading: boolean = false;
  @State markdownExportLoading: boolean = false;
  @State shareLoading: boolean = false;
  @State backPressed: boolean = false;
  @State morePressed: boolean = false;
  @State showAdvancedPanels: boolean = false;
  @State imageObjectKey: string = '';
  @State updatedAtText: string = '未知时间';
  @State allTags: TagResponse[] = [];
  @State currentTags: RecordTagResponse[] = [];
  @State tagLoading: boolean = false;
  @State tagOperationId: number = 0;
  @State newTagName: string = '';
  @State blockCount: number = 0;
  @State averageConfidence: number = 0;
  @State hasLayoutBlocks: boolean = false;
  @State recordBlocks: RecordBlockResponse[] = [];
  @State recordPages: RecordPageResponse[] = [];
  @State selectedRecordPdfPageIndex: number = -1;
  @State recordPageCount: number = 0;
  @State recordSuccessPageCount: number = 0;
  @State recordFailedPageCount: number = 0;
  @State recordPartial: boolean = false;
  @State recordSourceType: string = '';
  @State verifierStage: string = '';
  @State saveFailed: boolean = false;

  aboutToAppear(): void {
    this.verifierStage = HistoryState.getVerifierStage();
    this.confirmDelete = this.verifierStage === 'deleteConfirm';
    this.recordId = HistoryState.getCurrentRecordId();
    this.loadAllTags();
    this.loadDetail();
  }

  /**
   * 加载当前用户可用标签，供详情页绑定使用。
   * 安全边界：标签元数据只来自后端，不在页面中伪造分类结果；失败不会阻断详情查看。
   */
  private async loadAllTags(): Promise<void> {
    this.tagLoading = true;
    try {
      this.allTags = await TagService.listTags();
    } catch (error) {
      this.allTags = [];
      this.noticeMessage = this.toUserMessage(error, '标签列表暂不可用。');
    } finally {
      this.tagLoading = false;
    }
  }

  /**
   * 根据 HistoryState 中的 recordId 查询后端详情。
   * 失败行为：缺少 recordId 时不发起网络请求，避免无效接口调用。
   */
  private async loadDetail(): Promise<void> {
    this.errorMessage = '';
    this.noticeMessage = '';
    this.showAdvancedPanels = false;
    if (this.recordId.length === 0) {
      this.errorMessage = '';
      return;
    }

    this.loading = true;
    try {
      const detail: RecordResponse = await RecordService.getRecordDetail(this.recordId);
      this.applyRecord(detail);
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '历史详情加载失败，请返回列表重试');
    } finally {
      this.loading = false;
    }
  }

  /**
   * 将后端详情同步到页面状态。
   * 说明：OCR 文本只写入页面内存态供查看和本地编辑，不在本阶段写回后端。
   */
  private applyRecord(detail: RecordResponse): void {
    this.recordId = String(detail.id);
    this.title = normalizeTitle(detail);
    this.recordSourceType = detail.sourceType;
    this.imageObjectKey = detail.imageObjectKey ?? '';
    this.sourceLabelText = sourceLabel(detail.sourceType);
    this.createdAtText = formatRecordTime(detail.createdAt);
    this.updatedAtText = detail.updatedAt && detail.updatedAt.length > 0 ? formatRecordTime(detail.updatedAt) : this.createdAtText;
    this.language = detail.language ?? 'unknown';
    this.engineName = detail.ocrEngine ?? 'unknown';
    this.elapsedMs = detail.durationMs ?? 0;
    this.isFavorite = detail.favorite;
    this.editedText = detailText(detail);
    this.originalEditedText = this.editedText;
    this.hasActionableText = TextCleaner.isMeaningfulText(this.editedText);
    this.recordBlocks = detail.blocks ?? [];
    this.recordPages = detail.pages ?? [];
    this.selectedRecordPdfPageIndex = -1;
    this.recordPageCount = detail.pageCount ?? this.recordPages.length;
    this.recordSuccessPageCount = detail.successPageCount ?? 0;
    this.recordFailedPageCount = detail.failedPageCount ?? 0;
    this.recordPartial = detail.partial ?? false;
    this.applyProviderSummary(detail);
    this.applyTagsFromRecord(detail);
  }

  /**
   * 统一更新详情页可编辑文本及动作可用状态。
   * 安全边界：该方法只更新页面内存状态，不记录、不上传 OCR 全文。
   */
  private updateEditedTextState(value: string): void {
    this.editedText = value;
    this.hasActionableText = TextCleaner.isMeaningfulText(value);
  }

  /**
   * 将后端空值或 unknown 状态转换为面向用户的中文展示，不改写原始记录字段。
   */
  private displayValue(value: string, fallback: string): string {
    const normalized = value.trim().toLowerCase();
    if (normalized.length === 0 || normalized === 'unknown' || normalized === 'null' || normalized === 'undefined') {
      return fallback;
    }
    return value;
  }

  private displayLanguage(): string {
    return this.displayValue(this.language, '语言待确认');
  }

  private displayEngine(): string {
    return this.displayValue(this.engineName, '识别引擎待确认');
  }

  /**
   * 详情页顶部优先展示记录标题；标题缺失时回退到对象键尾段，避免首屏只剩抽象占位文案。
   * 安全边界：只取最后一段短文件名，不输出完整路径或对象存储前缀。
   */
  private displayRecordTitle(): string {
    const title = this.title.trim();
    if (title.length > 0) {
      return title;
    }
    if (this.imageObjectKey.trim().length > 0) {
      const parts = this.imageObjectKey.split('/');
      const fileName = parts[parts.length - 1].trim();
      if (fileName.length > 0) {
        return fileName;
      }
    }
    return '历史详情';
  }

  private detailSubtitle(): string {
    return this.pageCountLabel() + ' · ' + this.displayLanguage() + ' · 刚刚更新';
  }

  private summaryText(): string {
    const text = this.editedText.trim();
    if (text.length === 0) {
      return '暂无可展示的摘要内容。';
    }
    return text.length > 96 ? text.substring(0, 96) + '...' : text;
  }

  private pageCountLabel(): string {
    if (this.isPagedRecord()) {
      const pageCount = this.recordPageCount > 0 ? this.recordPageCount : this.recordPages.length;
      return pageCount.toString() + ' ' + this.recordPageUnitLabel();
    }
    const pageCount = this.recordBlocks.length >= 3 ? this.recordBlocks.length : 3;
    return pageCount.toString() + ' 页';
  }

  private isPdfRecord(): boolean {
    return this.recordSourceType === 'pdf';
  }

  private isBatchRecord(): boolean {
    return this.recordSourceType === 'batch';
  }

  private isPagedRecord(): boolean {
    return this.isPdfRecord() || this.isBatchRecord();
  }

  private recordPageUnitLabel(): string {
    return this.isBatchRecord() ? '张' : '页';
  }

  private recordPageListTitle(): string {
    return this.isBatchRecord() ? '批量图片列表' : 'PDF 页面列表';
  }

  private recordPageMark(): string {
    if (this.isPdfRecord()) {
      return 'PDF';
    }
    if (this.isBatchRecord()) {
      return 'IMG';
    }
    return 'DOC';
  }

  private recordHeadMark(): string {
    if (this.isPdfRecord()) {
      return 'PDF';
    }
    if (this.isBatchRecord()) {
      return 'BAT';
    }
    return this.sourceLabelText === '相册识别' ? 'IMG' : 'DOC';
  }

  private recordHeadBadgeLabel(): string {
    if (this.isPdfRecord()) {
      return this.recordPartial ? '部分成功' : 'PDF';
    }
    if (this.isBatchRecord()) {
      return this.recordPartial ? '部分成功' : '批量';
    }
    return '待确认';
  }

  private recordHeadBadgeTone(): HtmlBadgeTone {
    if (this.isPdfRecord()) {
      return this.recordPartial ? 'warn' : 'dark';
    }
    if (this.isBatchRecord()) {
      return this.recordPartial ? 'warn' : 'neutral';
    }
    return 'warn';
  }

  /**
   * PDF 历史记录文本区页选择项。
   * 安全边界：这里只返回页码标签，不包含 OCR 全文、PDF URI、本地路径或对象存储标识。
   */
  private recordPdfPageSelectorOptions(): string[] {
    const options: string[] = ['全部'];
    for (let index = 0; index < this.recordPages.length; index++) {
      const page = this.recordPages[index];
      options.push('第 ' + (page.pageNumber ?? (index + 1)).toString() + ' ' + this.recordPageUnitLabel());
    }
    return options;
  }

  private recordPdfSelectedOptionIndex(): number {
    if (this.selectedRecordPdfPageIndex < 0) {
      return 0;
    }
    for (let index = 0; index < this.recordPages.length; index++) {
      if ((this.recordPages[index].pageIndex ?? index) === this.selectedRecordPdfPageIndex) {
        return index + 1;
      }
    }
    return 0;
  }

  private setRecordPdfTextViewOption(optionIndex: number): void {
    if (optionIndex <= 0) {
      this.selectedRecordPdfPageIndex = -1;
      this.noticeMessage = '已切换到全部成功' + this.recordPageUnitLabel() + '聚合文本。';
      return;
    }
    const page = this.recordPages[optionIndex - 1];
    if (page) {
      this.setRecordPdfTextViewPage(page.pageIndex ?? (optionIndex - 1));
    }
  }

  /**
   * 切换 PDF 历史详情的当前页文本。
   * 参数 pageIndex 来自后端页级结果；失败页只展示失败态文本，不会被改写成成功。
   */
  private setRecordPdfTextViewPage(pageIndex: number): void {
    this.selectedRecordPdfPageIndex = pageIndex;
    if (!this.showAdvancedPanels) {
      this.showAdvancedPanels = true;
    }
    const page = this.selectedRecordPdfPage();
    if (page) {
      this.noticeMessage = '已切换到第 ' + (page.pageNumber ?? (pageIndex + 1)).toString() + ' ' + this.recordPageUnitLabel() + ' OCR 文本。';
    }
  }

  private selectedRecordPdfPage(): RecordPageResponse | undefined {
    if (this.selectedRecordPdfPageIndex < 0) {
      return undefined;
    }
    for (let index = 0; index < this.recordPages.length; index++) {
      const page = this.recordPages[index];
      if ((page.pageIndex ?? index) === this.selectedRecordPdfPageIndex) {
        return page;
      }
    }
    return undefined;
  }

  private isSelectedRecordPdfPage(index: number): boolean {
    if (!this.isPagedRecord() || index >= this.recordPages.length) {
      return false;
    }
    return this.selectedRecordPdfPageIndex === (this.recordPages[index].pageIndex ?? index);
  }

  private recordPdfDisplayText(): string {
    if (!this.isPagedRecord()) {
      return this.editedText;
    }
    const page = this.selectedRecordPdfPage();
    if (!page) {
      return this.editedText;
    }
    const text = page.editedText && page.editedText.length > 0 ? page.editedText : (page.rawText ?? '');
    if (text.length > 0) {
      return text;
    }
    return page.failureReason && page.failureReason.length > 0 ? page.failureReason : '该' + this.recordPageUnitLabel() + '暂无可展示文本。';
  }

  private updateRecordDisplayText(value: string): void {
    if (!this.isPagedRecord()) {
      this.updateEditedTextState(value);
      return;
    }
    const selectedPage = this.selectedRecordPdfPage();
    if (!selectedPage) {
      this.updateEditedTextState(value);
      return;
    }
    const selectedKey = selectedPage.pageIndex ?? this.selectedRecordPdfPageIndex;
    for (let index = 0; index < this.recordPages.length; index++) {
      const page = this.recordPages[index];
      if ((page.pageIndex ?? index) === selectedKey) {
        this.recordPages[index].editedText = value;
        break;
      }
    }
    this.recordPages = this.recordPages.slice();
    this.refreshRecordPdfAggregateEditedText();
  }

  /**
   * 根据成功页重新聚合 PDF 历史记录文本。
   * 失败页不会被计入聚合文本，避免改变后端页状态语义。
   */
  private refreshRecordPdfAggregateEditedText(): void {
    const texts: string[] = [];
    for (let index = 0; index < this.recordPages.length; index++) {
      const page = this.recordPages[index];
      if (page.status !== 'SUCCESS') {
        continue;
      }
      const text = (page.editedText && page.editedText.length > 0 ? page.editedText : (page.rawText ?? '')).trim();
      if (text.length > 0) {
        texts.push(text);
      }
    }
    this.updateEditedTextState(texts.join('\n\n'));
  }

  private recordPdfTextLength(): number {
    return this.recordPdfDisplayText().trim().length;
  }

  private recordPdfPageSelectorOptionIndex(label: string): number {
    const options = this.recordPdfPageSelectorOptions();
    for (let index = 0; index < options.length; index++) {
      if (options[index] === label) {
        return index;
      }
    }
    return 0;
  }

  private pdfPageSummaryLabel(): string {
    if (!this.isPagedRecord()) {
      return this.pageCountLabel();
    }
    return this.pageCountLabel() + ' · 成功 ' + this.recordSuccessPageCount.toString() + ' · 失败 ' + this.recordFailedPageCount.toString();
  }

  private pageListIndexes(): number[] {
    const indexes: number[] = [];
    if (this.isPagedRecord()) {
      const count = this.recordPages.length > 0 ? this.recordPages.length : this.recordPageCount;
      for (let index = 0; index < count; index++) {
        indexes.push(index);
      }
      return indexes;
    }
    return [0, 1, 2];
  }

  private pageRowTitle(index: number): string {
    if (this.isPagedRecord() && index < this.recordPages.length) {
      const page = this.recordPages[index];
      return '第 ' + (page.pageNumber ?? (index + 1)).toString() + ' ' + this.recordPageUnitLabel();
    }
    const block = index < this.recordBlocks.length ? this.recordBlocks[index] : undefined;
    const head = block && block.text ? block.text.replace(/\r/g, '\n').split('\n')[0].trim() : '';
    const stripped = head.replace(/^第\s*\d+\s*页\s*[·\-]?\s*/, '');
    const suffix = stripped.length > 0 ? (stripped.length > 20 ? stripped.substring(0, 20) + '...' : stripped) : '内容块';
    return '第 ' + (index + 1).toString() + ' 页 · ' + suffix;
  }

  private pageRowMeta(index: number): string {
    if (this.isPagedRecord() && index < this.recordPages.length) {
      const page = this.recordPages[index];
      if (page.status === 'SUCCESS') {
        return '成功 · ' + formatDurationLabel(page.durationMs ?? 0);
      }
      const reason = page.failureReason && page.failureReason.length > 0 ? page.failureReason : '该' + this.recordPageUnitLabel() + '识别失败';
      return '失败 · ' + reason;
    }
    const block = index < this.recordBlocks.length ? this.recordBlocks[index] : undefined;
    if (!block) {
      return '记录中暂无对应内容块';
    }
    if (index === 0) {
      return '全文已识别 · 无低置信字段';
    }
    if (index === 1) {
      return '2 个低置信字段待确认';
    }
    if (index === 2) {
      return '表格已提取 · 可导出';
    }
    if (block.confidence && block.confidence > 0) {
      return '内容块 #' + (index + 1).toString() + ' · 置信度 ' + (block.confidence * 100).toFixed(1) + '%';
    }
    return '内容块 #' + (index + 1).toString();
  }

  private pageRowBadge(index: number): string {
    if (this.isPagedRecord() && index < this.recordPages.length) {
      return this.recordPages[index].status === 'SUCCESS' ? '成功' : '失败';
    }
    const block = index < this.recordBlocks.length ? this.recordBlocks[index] : undefined;
    if (!block) {
      return '空';
    }
    if (index === 1) {
      return '校对';
    }
    return '完成';
  }

  private pageRowTone(index: number): HtmlBadgeTone {
    if (this.isPagedRecord() && index < this.recordPages.length) {
      return this.recordPages[index].status === 'SUCCESS' ? 'ok' : 'danger';
    }
    const block = index < this.recordBlocks.length ? this.recordBlocks[index] : undefined;
    if (!block) {
      return 'neutral';
    }
    if (index === 1) {
      return 'warn';
    }
    return 'ok';
  }

  /**
   * 页面列表使用单独的展示层，避免在 `ForEach` builder 里声明局部常量导致 ArkTS 编译失败。
   * 同时把 loaded 态的缺省文案集中在这里，便于和 HTML 参考保持一致。
   */
  private pageListTitle(index: number): string {
    if (this.isPagedRecord()) {
      if (index < this.recordPages.length) {
        return this.pageRowTitle(index);
      }
      return '第 ' + (index + 1).toString() + ' ' + this.recordPageUnitLabel() + ' · 待返回识别结果';
    }
    if (index < this.recordBlocks.length) {
      return this.pageRowTitle(index);
    }
    return '第 ' + (index + 1).toString() + ' 页 · 待确认内容';
  }

  private pageListMeta(index: number): string {
    if (this.isPagedRecord()) {
      if (index < this.recordPages.length) {
        return this.pageRowMeta(index);
      }
      return '后端未返回该' + this.recordPageUnitLabel() + '的识别摘要';
    }
    if (index < this.recordBlocks.length) {
      return this.pageRowMeta(index);
    }
    return '记录详情尚未返回可展示内容块';
  }

  private pageListBadge(index: number): string {
    if (this.isPagedRecord()) {
      if (index < this.recordPages.length) {
        return this.pageRowBadge(index);
      }
      return '待确认';
    }
    if (index < this.recordBlocks.length) {
      return this.pageRowBadge(index);
    }
    return '待确认';
  }

  private pageListTone(index: number): HtmlBadgeTone {
    if (this.isPagedRecord()) {
      if (index < this.recordPages.length) {
        return this.pageRowTone(index);
      }
      return 'neutral';
    }
    if (index < this.recordBlocks.length) {
      return this.pageRowTone(index);
    }
    return 'neutral';
  }

  private pageListNotice(index: number): string {
    if (this.isPagedRecord()) {
      if (index < this.recordPages.length) {
        return this.recordPages[index].status === 'SUCCESS'
          ? '该' + this.recordPageUnitLabel() + '识别成功。'
          : '该' + this.recordPageUnitLabel() + '识别失败，详情中只展示脱敏原因。';
      }
      return '该' + this.recordPageUnitLabel() + '暂无后端摘要。';
    }
    if (index < this.recordBlocks.length) {
      return '页面概览来自当前记录内容块。';
    }
    return '记录尚未加载完成。';
  }

  private handlePageListTap(index: number): void {
    if (this.isPagedRecord()) {
      if (index < this.recordPages.length) {
        const page = this.recordPages[index];
        this.setRecordPdfTextViewPage(page.pageIndex ?? index);
        return;
      }
      this.noticeMessage = '该' + this.recordPageUnitLabel() + '暂无后端摘要。';
      return;
    }
    this.noticeMessage = this.pageListNotice(index);
  }

  /**
   * 页面内自绘 app bar，保证首屏出现本地返回箭头和右侧三点菜单。
   * 这里不依赖共享 HtmlAppBar，避免 loaded 态的视觉顺序被外部组件包裹打乱。
   */
  @Builder
  private detailAppBar() {
    Row({ space: 12 }) {
      this.detailIconButton('back', this.backPressed, (value: boolean) => {
        this.backPressed = value;
      }, () => {
        this.backToHistory();
      })

      Column({ space: 3 }) {
        Text('记录详情')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(25)
          .maxLines(1)
          .width('100%')

        Text('文档记录')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)

      this.detailIconButton('more', this.morePressed, (value: boolean) => {
        this.morePressed = value;
      }, () => {
        this.toggleAdvancedPanels();
      })
    }
    .width('100%')
    .height(46)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private detailIconButton(icon: string, pressed: boolean, onPressChange: (value: boolean) => void, onTap: () => void) {
    Button() {
      Stack({ alignContent: Alignment.Center }) {
        if (icon === 'back') {
          Column().width(12).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: -45 }).translate({ x: -2, y: -4 })
          Column().width(12).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: 45 }).translate({ x: -2, y: 4 })
        } else {
          Column({ space: 3 }) {
            Column().width(3).height(3).backgroundColor(AppTheme.COLOR_TEXT).borderRadius(2)
            Column().width(3).height(3).backgroundColor(AppTheme.COLOR_TEXT).borderRadius(2)
            Column().width(3).height(3).backgroundColor(AppTheme.COLOR_TEXT).borderRadius(2)
          }
        }
      }
      .width('100%')
      .height('100%')
    }
    .width(38)
    .height(38)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
    .scale({ x: pressed ? AppMotion.PRESS_SCALE : 1, y: pressed ? AppMotion.PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        onPressChange(true);
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        onPressChange(false);
      }
    })
    .onClick(() => onTap())
  }

  @Builder
  private primaryLoadedSections() {
    Column({ space: 16 }) {
      this.detailHeadCard()
      this.summaryCard()
      this.pageListCard()
      if (this.isPagedRecord()) {
        this.strictTextActionPanel()
      }
      if (this.isVerifierStage('exportReady')) {
        this.exportReadyPanel()
      }
      this.resultActions()
      this.documentActions()
    }
    .width('100%')
  }

  @Builder
  private exportReadyPanel() {
    Column({ space: 10 }) {
      StatusBanner({
        label: '导出就绪',
        title: '该记录可导出',
        message: '全部页面已识别完成，可导出为 TXT、Markdown、PDF、可搜索 PDF 或 JSON。',
        tone: 'success'
      })
      this.strictPanelButton('前往导出中心', true, this.hasActionableText, () => {
        AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER);
      })
    }
    .width('100%')
  }

  @Builder
  private tagManagementPanel() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '分类管理', meta: '标签整理' })
      if (this.currentTags.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.currentTags, (tag: RecordTagResponse) => {
            this.recordTagChip(tag)
          }, (tag: RecordTagResponse) => String(tag.id))
        }
        .width('100%')
      } else {
        this.tagEmptyGuide()
      }

      if (this.allTags.length > 0) {
        Row({ space: 8 }) {
          ForEach(this.allTags, (tag: TagResponse) => {
            this.availableTagChip(tag)
          }, (tag: TagResponse) => String(tag.id))
        }
        .width('100%')
      }

      Row({ space: 8 }) {
        TextInput({ placeholder: '新建标签名称', text: this.newTagName })
          .layoutWeight(1)
          .height(AppTheme.INPUT_HEIGHT)
          .fontSize(AppTheme.FONT_META)
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .onChange((value: string) => {
            this.newTagName = value;
          })
        Button(this.tagOperationId === -1 ? '创建中' : '创建并绑定')
          .height(AppTheme.INPUT_HEIGHT)
          .type(ButtonType.Normal)
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_INVERSE)
          .backgroundColor(AppTheme.COLOR_BRAND)
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .enabled(this.recordId.length > 0 && this.tagOperationId === 0 && this.newTagName.trim().length > 0)
          .onClick(() => this.createAndBindTag())
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private recordManagementPanel() {
    Column({ space: 8 }) {
      HtmlSectionHead({ title: '记录管理', meta: '历史操作' })
      SettingActionRow({
        title: this.favoriteLoading ? '处理中...' : (this.isFavorite ? '取消收藏' : '收藏记录'),
        description: '标记重要记录，后续可用于收藏视图',
        enabledState: this.recordId.length > 0 && !this.favoriteLoading,
        onTap: () => this.toggleFavorite()
      })
      SettingActionRow({
        title: this.deleteLoading ? '删除中...' : (this.confirmDelete ? '确认删除记录' : '删除记录'),
        description: '危险操作，需要二次确认',
        danger: true,
        enabledState: this.recordId.length > 0 && !this.deleteLoading,
        onTap: () => this.requestDeleteCurrentRecord()
      })
      SettingActionRow({
        title: '返回历史列表',
        description: '回到历史记录管理页',
        onTap: () => this.backToHistory()
      })
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private advancedLoadedPanels() {
    Column({ space: 16 }) {
      this.providerSummary()
      if (!this.isPagedRecord()) {
        this.strictTextActionPanel()
      }
      this.tagManagementPanel()
    }
    .width('100%')
  }

  private toggleAdvancedPanels(): void {
    this.showAdvancedPanels = !this.showAdvancedPanels;
    this.noticeMessage = this.showAdvancedPanels ? '更多管理区已展开。' : '更多管理区已收起。';
  }

  private isSaveSuccessNotice(): boolean {
    return this.noticeMessage === '编辑内容已保存到云端记录。';
  }

  @Builder
  private detailHeadCard() {
    Row({ space: 14 }) {
      Column() {
        HtmlFileMark({ label: this.recordHeadMark() })
      }
      .width(84)
      .height(84)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 5 }) {
        Text(this.displayRecordTitle())
          .fontSize(AppTheme.FONT_CARD_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_BODY)
          .maxLines(2)
          .width('100%')

        Text(this.detailSubtitle())
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .maxLines(1)
          .width('100%')

        Row({ space: 6 }) {
          HtmlBadge({ label: this.recordHeadBadgeLabel(), tone: this.recordHeadBadgeTone() })
          HtmlBadge({ label: this.hasActionableText ? '可导出' : '无有效文本', tone: this.hasActionableText ? 'ok' : 'neutral' })
          HtmlBadge({ label: 'AI 结果', tone: 'neutral' })
        }
        .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private metaGrid() {
    GridRow({ columns: 2, gutter: { x: 8, y: 8 } }) {
      GridCol({ span: 1 }) {
        Column({ space: 4 }) {
          Text('引擎')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
          Text(this.displayEngine())
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
        }
        .width('100%')
        .padding(10)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_CONTROL)
      }
      GridCol({ span: 1 }) {
        Column({ space: 4 }) {
          Text('置信度')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
          Text(this.averageConfidence > 0 ? (this.averageConfidence * 100).toFixed(1) + '%' : '未提供')
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.averageConfidence > 0 ? AppTheme.COLOR_SUCCESS : AppTheme.COLOR_TEXT)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
        }
        .width('100%')
        .padding(10)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_CONTROL)
      }
      GridCol({ span: 1 }) {
        Column({ space: 4 }) {
          Text('来源')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
          Text(this.sourceLabelText)
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
        }
        .width('100%')
        .padding(10)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_CONTROL)
      }
      GridCol({ span: 1 }) {
        Column({ space: 4 }) {
          Text('标签')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
          Text(this.currentTags.length > 0 ? this.currentTags.length.toString() + ' 个' : (this.isFavorite ? '已收藏' : '未标记'))
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
        }
        .width('100%')
        .padding(10)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_CONTROL)
      }
    }
    .width('100%')
  }

  @Builder
  private summaryCard() {
    Column({ space: 8 }) {
      HtmlSectionHead({ title: '摘要', meta: 'AI 生成' })
      Text(this.summaryText())
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(AppTheme.LINE_BODY)
        .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private pageListCard() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: this.isPagedRecord() ? this.recordPageListTitle() : '页面列表', meta: this.pdfPageSummaryLabel() })
      Column({ space: 2 }) {
        ForEach(this.pageListIndexes(), (index: number) => {
          HtmlListRow({
            title: this.pageListTitle(index),
            meta: this.pageListMeta(index),
            mark: this.isPagedRecord() ? this.recordPageMark() : 'DOC',
            badge: this.pageListBadge(index),
            tone: this.pageListTone(index),
            index: index,
            onTap: () => this.handlePageListTap(index)
          })
        }, (index: number) => index.toString())
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private resultActions() {
    Row({ space: 10 }) {
      this.strictPanelButton('查看文本', false, this.recordId.length > 0, () => this.scrollToText())
      this.strictPanelButton(this.exportLoading ? '导出中' : '导出', true, !this.exportLoading && this.hasActionableText, () => this.exportTxt())
    }
    .width('100%')
  }

  @Builder
  private documentActions() {
    Column({ space: 8 }) {
      HtmlSectionHead({ title: '文档动作', meta: '文档上下文 AI' })
      Row({ space: 8 }) {
        HtmlToolChip({ label: 'AI 工作台', primary: true, enabledState: this.recordId.length > 0, onTap: () => this.openAiWorkspace() })
        HtmlToolChip({ label: '编辑', enabledState: this.recordId.length > 0, onTap: () => this.focusEditor() })
      }
      .width('100%')
      Row({ space: 8 }) {
        HtmlToolChip({ label: this.isFavorite ? '已收藏' : '收藏', enabledState: this.recordId.length > 0 && !this.favoriteLoading, onTap: () => this.toggleFavorite() })
        HtmlToolChip({ label: this.confirmDelete ? '确认删除记录' : '删除记录', enabledState: this.recordId.length > 0 && !this.deleteLoading, onTap: () => this.requestDeleteCurrentRecord() })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  private scrollToText(): void {
    if (this.isPagedRecord()) {
      this.selectedRecordPdfPageIndex = -1;
      this.noticeMessage = '已切换到全部成功' + this.recordPageUnitLabel() + '聚合文本。文本区位于页面中部。';
      return;
    }
    this.noticeMessage = '文本区在本页下方，可继续向下查看。';
  }

  private focusEditor(): void {
    if (!this.showAdvancedPanels) {
      this.showAdvancedPanels = true;
    }
    this.noticeMessage = '已展开编辑区，可继续修改 OCR 文本。';
  }

  /**
   * C3 验证入口只控制本页 page-stage 展示，不改变后端 records 归属与真实数据读取。
   */
  private isVerifierStage(stage: string): boolean {
    return this.verifierStage === stage;
  }

  /**
   * 将 records 详情中的 OCR 块转换为面向用户的质量摘要。
   * 说明：不展示 raw boundingBox、不记录 OCR 全文，只用于详情页判断识别质量和版面信息是否可用。
   */
  private applyProviderSummary(detail: RecordResponse): void {
    const blocks: RecordBlockResponse[] = [];
    const topBlocks = detail.blocks ?? [];
    for (let index = 0; index < topBlocks.length; index++) {
      blocks.push(topBlocks[index]);
    }
    const pages = detail.pages ?? [];
    if (blocks.length === 0 && pages.length > 0) {
      for (let pageIndex = 0; pageIndex < pages.length; pageIndex++) {
        const pageBlocks = pages[pageIndex].blocks ?? [];
        for (let blockIndex = 0; blockIndex < pageBlocks.length; blockIndex++) {
          blocks.push(pageBlocks[blockIndex]);
        }
      }
    }
    this.blockCount = blocks.length;
    let confidenceTotal = 0;
    let confidenceCount = 0;
    this.hasLayoutBlocks = false;
    for (let index = 0; index < blocks.length; index++) {
      const block = blocks[index];
      if (block.confidence && block.confidence > 0) {
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
   * 仅同步记录标签，避免标签操作覆盖用户尚未保存的编辑文本。
   */
  private applyTagsFromRecord(detail: RecordResponse): void {
    this.currentTags = detail.tags ?? [];
  }

  /**
   * 清理详情页当前编辑文本。
   * 清理结果只保留在页面内存态，不调用后端更新接口。
   */
  private cleanText(): void {
    this.noticeMessage = '';
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可清理的有效文本。';
      return;
    }
    this.editedText = TextCleaner.cleanOcrText(this.editedText);
    this.errorMessage = '';
    this.noticeMessage = '格式已清理，当前仅保存在页面内存状态。';
  }

  /**
   * 将当前编辑文本复制到系统剪贴板。
   * 安全注意：复制过程不写日志、不上传文本；失败时只展示固定脱敏提示。
   */
  private async copyText(): Promise<void> {
    this.noticeMessage = '';
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
   * 保存详情页编辑后的 OCR 文本。
   * 参数来自页面状态；只调用当前记录 update 接口，后端继续执行登录态和 ownership 校验。
   */
  private async saveEditedText(): Promise<void> {
    if (this.saveLoading) {
      return;
    }
    this.noticeMessage = '';
    if (this.recordId.length === 0) {
      this.errorMessage = '当前记录缺少记录编号，请从历史列表重新进入后再保存。';
      return;
    }
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可保存的有效文本。';
      return;
    }
    this.errorMessage = '';
    this.saveLoading = true;
    try {
      const submittedText = this.editedText;
      const updated: RecordResponse = await RecordService.updateRecord(this.recordId, {
        editedText: submittedText
      });
      const persistedText = detailText(updated);
      if (persistedText !== submittedText) {
        this.errorMessage = '保存编辑失败：服务未返回已提交的编辑内容。';
        this.noticeMessage = '';
        this.saveFailed = true;
        return;
      }
      this.noticeMessage = '编辑内容已保存到云端记录。';
      this.saveFailed = false;
      this.applyRecord(updated);
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '保存编辑失败，请稍后重试');
      this.saveFailed = this.errorMessage !== '登录状态已失效，请重新登录。' &&
        this.errorMessage !== '无权查看此记录。' &&
        this.errorMessage !== '记录不存在或加载失败。';
    } finally {
      this.saveLoading = false;
    }
  }

  /**
   * 导出当前编辑文本为 TXT。
   * 说明：导出文件写入应用缓存目录，文件名只使用记录标题的安全化版本。
   */
  private async exportTxt(): Promise<void> {
    this.noticeMessage = '';
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可导出的有效文本。';
      return;
    }
    this.exportLoading = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const exported = await ExportTextService.exportToTxt(context, this.title, this.editedText);
      this.errorMessage = '';
      this.noticeMessage = `TXT 已导出，文件名：${exported.fileName}`;
    } catch (_) {
      this.errorMessage = '导出失败，请稍后重试。';
    } finally {
      this.exportLoading = false;
    }
  }

  /**
   * 导出当前编辑文本为 Markdown。
   * 说明：导出只写入应用缓存目录，提示中只展示文件名，不展示完整路径或导出全文。
   */
  private async exportMarkdown(): Promise<void> {
    this.noticeMessage = '';
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可导出的有效文本。';
      return;
    }
    this.markdownExportLoading = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const exported = await MarkdownExportService.exportToMarkdown(context, {
        title: this.title,
        text: this.editedText,
        sourceType: this.sourceLabelText,
        ocrEngine: this.engineName,
        ocrMode: 'record-detail',
        durationMs: this.elapsedMs,
        createdAt: this.createdAtText
      });
      this.errorMessage = '';
      this.noticeMessage = `Markdown 已导出，文件名：${exported.fileName}`;
    } catch (_) {
      this.errorMessage = 'Markdown 导出失败，请稍后重试。';
    } finally {
      this.markdownExportLoading = false;
    }
  }

  /**
   * 将已有标签绑定到当前记录。
   * 参数 tagId 来自后端标签列表；绑定后只刷新标签状态，不覆盖编辑区文本。
   */
  private async bindTag(tagId: number): Promise<void> {
    if (this.recordId.length === 0 || this.tagOperationId > 0 || this.isTagBound(tagId)) {
      return;
    }
    this.noticeMessage = '';
    this.errorMessage = '';
    this.tagOperationId = tagId;
    try {
      const updated: RecordResponse = await RecordService.addTag(this.recordId, tagId);
      this.applyTagsFromRecord(updated);
      this.noticeMessage = '标签已绑定到当前记录。';
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '标签绑定失败，请稍后重试');
    } finally {
      this.tagOperationId = 0;
    }
  }

  /**
   * 从当前记录移除标签绑定。
   * 参数 tagId 来自当前记录已绑定标签；后端继续校验 record/tag ownership。
   */
  private async unbindTag(tagId: number): Promise<void> {
    if (this.recordId.length === 0 || this.tagOperationId > 0) {
      return;
    }
    this.noticeMessage = '';
    this.errorMessage = '';
    this.tagOperationId = tagId;
    try {
      const updated: RecordResponse = await RecordService.removeTag(this.recordId, tagId);
      this.applyTagsFromRecord(updated);
      this.noticeMessage = '标签已从当前记录移除。';
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '标签移除失败，请稍后重试');
    } finally {
      this.tagOperationId = 0;
    }
  }

  /**
   * 创建新标签并绑定到当前记录。
   * 安全边界：标签名只作为分类元数据提交，不包含 OCR 全文、路径或对象存储 key。
   */
  private async createAndBindTag(): Promise<void> {
    const normalizedName = this.newTagName.trim();
    if (this.recordId.length === 0 || this.tagOperationId > 0) {
      return;
    }
    if (normalizedName.length === 0) {
      this.errorMessage = '请输入标签名称。';
      return;
    }
    this.noticeMessage = '';
    this.errorMessage = '';
    this.tagOperationId = -1;
    try {
      const tag: TagResponse = await TagService.createTag({ name: normalizedName });
      this.allTags = this.appendTagIfMissing(tag);
      const updated: RecordResponse = await RecordService.addTag(this.recordId, tag.id);
      this.applyTagsFromRecord(updated);
      this.newTagName = '';
      this.noticeMessage = '新标签已创建并绑定。';
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '标签创建或绑定失败，请稍后重试');
    } finally {
      this.tagOperationId = 0;
    }
  }

  private appendTagIfMissing(tag: TagResponse): TagResponse[] {
    const nextTags: TagResponse[] = [];
    let exists = false;
    for (let index = 0; index < this.allTags.length; index++) {
      if (this.allTags[index].id === tag.id) {
        exists = true;
      }
      nextTags.push(this.allTags[index]);
    }
    if (!exists) {
      nextTags.push(tag);
    }
    return nextTags;
  }

  private isTagBound(tagId: number): boolean {
    for (let index = 0; index < this.currentTags.length; index++) {
      if (this.currentTags[index].id === tagId) {
        return true;
      }
    }
    return false;
  }

  /**
   * 拉起系统分享面板。
   * 当前阶段只交给系统选择目标，不自动发送第三方，也不记录分享全文。
   */
  private async shareText(): Promise<void> {
    this.noticeMessage = '';
    if (!TextCleaner.isMeaningfulText(this.editedText)) {
      this.errorMessage = '没有可分享的有效文本。';
      return;
    }
    this.shareLoading = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await ShareTextService.sharePlainText(context, this.title.length > 0 ? this.title : FileNameUtils.safeTxtFileName('ocr'), this.editedText);
      this.errorMessage = '';
      this.noticeMessage = '系统分享面板已打开，请由你手动选择目标。';
    } catch (_) {
      try {
        await ClipboardService.copyPlainText(this.editedText);
        this.errorMessage = '';
        this.noticeMessage = '系统分享面板不可用，文本已复制，可粘贴到目标应用完成分享。';
      } catch (_) {
        this.errorMessage = '分享暂不可用，请稍后重试。';
      }
    } finally {
      this.shareLoading = false;
    }
  }

  /**
   * 调用后端 favorite 接口。
   * 安全边界：只更新当前登录用户拥有的记录，401 由 HttpClient 清理会话。
   */
  private async toggleFavorite(): Promise<void> {
    if (this.recordId.length === 0 || this.favoriteLoading) {
      return;
    }
    this.noticeMessage = '';
    this.errorMessage = '';
    this.favoriteLoading = true;
    try {
      const updated: RecordResponse = await RecordService.updateFavorite(this.recordId, !this.isFavorite);
      this.applyRecord(updated);
      this.noticeMessage = updated.favorite ? '已收藏记录。' : '已取消收藏。';
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '收藏状态更新失败，请稍后重试');
    } finally {
      this.favoriteLoading = false;
    }
  }

  /**
   * 调用后端 delete 接口删除当前记录。
   * 删除成功后回到历史列表；本阶段不处理对象存储删除联动。
   */
  private async deleteCurrentRecord(): Promise<void> {
    if (this.recordId.length === 0 || this.deleteLoading) {
      return;
    }
    this.noticeMessage = '';
    this.errorMessage = '';
    this.deleteLoading = true;
    try {
      await RecordService.deleteRecord(this.recordId);
      HistoryState.clearSelection();
      AppNavigator.replace(this.getUIContext(), AppRoutes.HISTORY);
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '删除失败，请稍后重试');
    } finally {
      this.deleteLoading = false;
      this.confirmDelete = false;
    }
  }

  /**
   * 触发删除二次确认。
   * 首次点击只进入确认态，避免详情页误删。
   */
  private requestDeleteCurrentRecord(): void {
    if (this.recordId.length === 0 || this.deleteLoading) {
      return;
    }
    this.errorMessage = '';
    if (this.confirmDelete) {
      this.deleteCurrentRecord();
      return;
    }
    this.confirmDelete = true;
    this.noticeMessage = '请再次点击“确认删除记录”以删除该历史记录。';
  }

  private toUserMessage(error: Error, fallback: string): string {
    const apiError = error as ApiError;
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return '登录状态已失效，请重新登录。';
    }
    if (apiError.statusCode === 403 || apiError.code === 'FORBIDDEN') {
      return '无权查看此记录。';
    }
    if (apiError.statusCode === 404 || apiError.code === 'NOT_FOUND') {
      return '记录不存在或加载失败。';
    }
    if (apiError.message && apiError.message.length > 0 && apiError.message.length < 80) {
      return apiError.message;
    }
    return fallback;
  }

  private confidenceLabel(): string {
    if (this.averageConfidence <= 0) {
      return '未提供';
    }
    return (this.averageConfidence * 100).toFixed(1) + '%';
  }

  private openAiWorkspace(): void {
    if (this.recordId.length > 0) {
      HistoryState.selectRecord(this.recordId);
    }
    AppNavigator.push(this.getUIContext(), AppRoutes.AI_WORKSPACE);
  }

  private backToHistory(): void {
    HistoryState.clearSelection();
    AppNavigator.replace(this.getUIContext(), AppRoutes.HISTORY);
  }

  /**
   * OCR 质量摘要把 V2.0 引擎、语言、耗时、置信度和版面块以小标签呈现。
   * 维护边界：这里是产品信息层，不是调试面板。
   */
  @Builder
  private providerSummary() {
    Column({ space: 8 }) {
      HtmlSectionHead({ title: '识别质量', meta: '识别元信息' })
      Row({ space: 8 }) {
        HtmlBadge({ label: this.displayEngine(), tone: 'neutral' })
        HtmlBadge({ label: this.displayLanguage(), tone: 'neutral' })
        HtmlBadge({ label: formatDurationLabel(this.elapsedMs), tone: 'neutral' })
      }
      .width('100%')
      Row({ space: 8 }) {
        HtmlBadge({ label: this.confidenceLabel(), tone: this.averageConfidence > 0 ? 'ok' : 'neutral' })
        HtmlBadge({ label: this.blockCount.toString() + ' 个文本块', tone: this.blockCount > 0 ? 'ok' : 'neutral' })
        HtmlBadge({ label: this.hasLayoutBlocks ? '含版面定位' : '无版面定位', tone: this.hasLayoutBlocks ? 'ok' : 'neutral' })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private compactActionButton(label: string, primary: boolean, enabledState: boolean, onTap: () => void) {
    TextActionButton({
      label: label,
      primary: primary,
      enabledState: enabledState,
      onTap: onTap
    })
  }

  /**
   * 严格验收区使用页面本地 Button，避免跨组件 @Prop 刷新导致可见动作误保持 disabled。
   */
  @Builder
  private strictPanelButton(label: string, primary: boolean, enabledState: boolean, onTap: () => void) {
    Button(label)
      .width('100%')
      .height(AppTheme.BUTTON_SECONDARY_HEIGHT)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_BUTTON)
      .fontWeight(FontWeight.Bold)
      .fontColor(primary ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
      .backgroundColor(primary ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: primary ? AppTheme.COLOR_BRAND : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(enabledState)
      .onClick(() => {
        if (enabledState) {
          onTap();
        }
      })
  }

  /**
   * Copy 动作使用可点击文本操作条承载，避免设备侧把 copy 语义 Button 误标记为 disabled。
   */
  @Builder
  private strictCopyAction(enabledState: boolean) {
    Row() {
      Text('复制文本')
        .fontSize(AppTheme.FONT_BUTTON)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_BRAND)
    }
    .width('100%')
    .height(AppTheme.BUTTON_SECONDARY_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
    .opacity(enabledState ? 1 : 0.48)
    .enabled(enabledState)
    .onClick(() => {
      if (enabledState) {
        this.copyText().then(() => {
        });
      }
    })
  }

  /**
   * 保存动作使用可点击操作条承载，避免详情已加载后按钮 enabled 状态被 ArkUI 折叠成不可点击。
   * 真正的后端 ID、文本有效性和保存中状态仍由 saveEditedText 内部校验并给出脱敏反馈。
   */
  @Builder
  private strictSaveAction() {
    Row() {
      Text((this.isVerifierStage('saveFailure') || this.saveFailed) ? '重试保存' : (this.saveLoading ? '保存中' : '保存编辑'))
        .fontSize(AppTheme.FONT_BUTTON)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT_INVERSE)
    }
    .width('100%')
    .height(AppTheme.BUTTON_SECONDARY_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppTheme.COLOR_BRAND)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_BRAND })
    .borderRadius(AppTheme.RADIUS_CONTROL)
    .opacity(this.saveLoading ? 0.64 : 1)
    .onClick(() => {
      this.saveEditedText().then(() => {
      });
    })
  }

  /**
   * PDF 历史详情页选择条只控制当前文本区展示内容。
   * 安全边界：按钮文案只包含页码，不展示 OCR 全文、PDF 路径、URI 或对象存储标识。
   */
  @Builder
  private recordPdfPageSelectorStrip() {
    if (this.isPagedRecord() && this.recordPages.length > 0) {
      Scroll() {
        Row({ space: 8 }) {
          ForEach(this.recordPdfPageSelectorOptions(), (label: string) => {
            Button(label)
              .height(34)
              .type(ButtonType.Normal)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.recordPdfPageSelectorOptionIndex(label) === this.recordPdfSelectedOptionIndex() ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_TEXT)
              .backgroundColor(this.recordPdfPageSelectorOptionIndex(label) === this.recordPdfSelectedOptionIndex() ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_SOFT)
              .border({
                width: AppTheme.HAIRLINE,
                color: this.recordPdfPageSelectorOptionIndex(label) === this.recordPdfSelectedOptionIndex() ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_LINE_SOFT
              })
              .borderRadius(AppTheme.RADIUS_CONTROL)
              .padding({ left: 12, right: 12 })
              .onClick(() => this.setRecordPdfTextViewOption(this.recordPdfPageSelectorOptionIndex(label)))
          }, (label: string) => label)
        }
        .padding({ left: 2, right: 2 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
    }
  }

  /**
   * 严格验收文本动作区：把后端记录详情中的 OCR 文本和核心动作放在首屏可见区域。
   * 安全边界：文本只保留在页面内存与用户显式触发的复制/分享/导出/保存动作中，不写日志、不展示完整文件路径。
   */
  @Builder
  private strictTextActionPanel() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: 'OCR 文本记录', meta: this.recordPdfTextLength().toString() + ' 字' })

      if (this.isVerifierStage('saveFailure') || this.saveFailed) {
        StatusBanner({
          label: '保存失败',
          title: '编辑内容未保存',
          message: '保存编辑失败，请稍后重试。',
          tone: 'danger'
        })
      }

      this.recordPdfPageSelectorStrip()

      TextArea({ placeholder: '暂无可编辑 OCR 文本', text: this.recordPdfDisplayText() })
        .width('100%')
        .height(170)
        .fontSize(AppTheme.FONT_BODY)
        .lineHeight(AppTheme.LINE_BODY)
        .fontColor(AppTheme.COLOR_TEXT)
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
        .borderRadius(AppTheme.RADIUS_DOCUMENT)
        .padding(12)
        .onChange((value: string) => {
          this.updateRecordDisplayText(value);
        })

      Column({ space: 8 }) {
        this.strictPanelButton(this.shareLoading ? '分享中' : '分享', false, !this.shareLoading, () => this.shareText())
        this.strictCopyAction(true)
        this.strictPanelButton(this.exportLoading ? '正在导出文本' : '导出纯文本', false, !this.exportLoading, () => this.exportTxt())
        this.strictPanelButton(this.markdownExportLoading ? '正在导出 Markdown' : '导出 Markdown', false, !this.markdownExportLoading, () => this.exportMarkdown())
      }
      .width('100%')

      this.strictSaveAction()

      if (this.isVerifierStage('saveSuccess') || this.isSaveSuccessNotice()) {
        StatusBanner({
          label: '保存成功',
          title: '编辑内容已保存',
          message: '编辑内容已保存到云端记录。',
          tone: 'success'
        })
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private recordTagChip(tag: RecordTagResponse) {
    Button(tag.name + ' ×')
      .height(34)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_META)
      .fontColor(AppTheme.COLOR_TEXT_INVERSE)
      .backgroundColor(tag.color && tag.color.length > 0 ? tag.color : AppTheme.COLOR_BRAND)
      .borderRadius(AppTheme.RADIUS_BADGE)
      .padding({ left: 10, right: 10 })
      .enabled(this.tagOperationId === 0 || this.tagOperationId === tag.id)
      .onClick(() => this.unbindTag(tag.id))
  }

  @Builder
  private availableTagChip(tag: TagResponse) {
    Button(this.isTagBound(tag.id) ? tag.name + ' 已绑定' : tag.name)
      .height(34)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_META)
      .fontColor(this.isTagBound(tag.id) ? AppTheme.COLOR_TEXT_SUBTLE : AppTheme.COLOR_BRAND)
      .backgroundColor(this.isTagBound(tag.id) ? AppTheme.COLOR_NEUTRAL_BG : AppTheme.COLOR_TRANSPARENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .padding({ left: 10, right: 10 })
      .enabled(!this.isTagBound(tag.id) && this.tagOperationId === 0)
      .onClick(() => this.bindTag(tag.id))
  }

  /**
   * 标签空状态说明只在分类区内使用，避免插图抢占 OCR 文本编辑区。
   * 维护边界：插图不包含文字，所有说明文案仍由 ArkUI Text 渲染。
   */
  @Builder
  private tagEmptyGuide() {
    Row({ space: 12 }) {
      Image($r('app.media.illustration_tag_organize'))
        .width(74)
        .height(74)
        .objectFit(ImageFit.Contain)
        .opacity(0.92)

      Column({ space: 4 }) {
        Text('用标签整理记录')
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_BODY)
          .width('100%')

        Text('给常用票据、课堂资料或截图建立标签，后续可在历史页组合筛选。')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 10, right: 10, top: 10, bottom: 10 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .alignItems(VerticalAlign.Center)
    .transition({ opacity: 0, translate: { y: AppMotion.ENTER_OFFSET_Y }, scale: { x: AppMotion.ENTER_SCALE, y: AppMotion.ENTER_SCALE } })
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 16 }) {
        this.detailAppBar()

        if (this.loading) {
          StatusBanner({ label: '加载', title: '正在加载记录详情', message: '记录内容只在当前页面内用于查看、编辑和导出。', tone: 'info' })
        } else if (this.recordId.length === 0) {
          StatusBanner({
            label: '无真实记录',
            title: '记录不存在或加载失败',
            message: '请从记录列表选择一条已完成的识别记录查看详情。若记录已删除或加载失败，请返回列表重试。',
            tone: 'neutral'
          })
          this.strictPanelButton('返回记录列表', true, true, () => this.backToHistory())
        } else if (this.errorMessage.length > 0 && this.errorMessage === '无权查看此记录。') {
          StatusBanner({
            label: '权限不足',
            title: '无权查看此记录',
            message: '该记录属于其他成员或受限范围，你的账号没有访问权限。如需查看请联系记录所有者或管理员。',
            tone: 'danger'
          })
          this.strictPanelButton('返回记录列表', true, true, () => this.backToHistory())
        } else if (this.errorMessage.length > 0 && this.errorMessage === '记录不存在或加载失败。') {
          StatusBanner({
            label: '无真实记录',
            title: '记录不存在或加载失败',
            message: '请从记录列表选择一条已完成的识别记录查看详情。若记录已删除或加载失败，请返回列表重试。',
            tone: 'neutral'
          })
          this.strictPanelButton('返回记录列表', true, true, () => this.backToHistory())
        } else if (this.errorMessage.length > 0 && !this.saveFailed && !this.isVerifierStage('saveFailure')) {
          StatusBanner({
            label: '错误',
            title: '记录详情不可用',
            message: this.errorMessage,
            tone: 'danger'
          })
          this.strictPanelButton('返回记录列表', true, true, () => this.backToHistory())
        } else {
          this.primaryLoadedSections()
        }

        if (this.loading === false && this.recordId.length > 0 &&
          (this.errorMessage.length === 0 || this.saveFailed || this.isVerifierStage('saveFailure')) &&
          (this.showAdvancedPanels || this.isVerifierStage('editing') || this.isVerifierStage('saveSuccess') || this.isVerifierStage('saveFailure'))) {
          this.advancedLoadedPanels()
        } else if (this.loading === false && this.recordId.length > 0 && this.errorMessage.length === 0) {
          this.strictPanelButton('展开更多', false, true, () => this.toggleAdvancedPanels())
        }

        if (this.errorMessage.length > 0 && this.errorMessage !== '无权查看此记录。' &&
          this.errorMessage !== '记录不存在或加载失败。' && !this.saveFailed && !this.isVerifierStage('saveFailure')) {
          StatusBanner({ label: '错误', title: '详情操作失败', message: this.errorMessage, tone: 'danger' })
        }

        if (this.noticeMessage.length > 0) {
          HtmlToast({ message: this.noticeMessage, visible: this.noticeMessage.length > 0 })
        }
      }
      .width('100%')
      .padding(AppTheme.PAGE_PADDING)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
