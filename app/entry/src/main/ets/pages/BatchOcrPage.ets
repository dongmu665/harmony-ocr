import { common } from '@kit.AbilityKit';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { TokenStorage } from '../common/storage/TokenStorage';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import {
  HtmlAppBar,
  HtmlBadge,
  HtmlCompactActionButton,
  HtmlFileMark,
  HtmlToast,
  HtmlSectionHead,
  HtmlStatusBar,
  HtmlToolChip,
  StatusBanner,
  TextActionButton
} from '../components/BrandComponents';
import { DeviceImagePickerService } from '../features/ocr/DeviceImagePickerService';
import { DeviceImageSelection } from '../features/ocr/DeviceOcrModels';
import { HistoryState } from '../features/history/HistoryState';
import { UserPreferenceService } from '../features/settings/UserPreferenceService';
import { BatchOcrTaskItemSummaryResponse, BatchOcrTaskSummaryResponse, OcrHealthResponse } from '../features/v2/V2Models';
import { V2Service } from '../features/v2/V2Service';

type BatchPageStage =
  'guestDisabled' |
  'empty' |
  'selectingImages' |
  'uploadReady' |
  'creating' |
  'createFailed' |
  'running' |
  'partialFailed' |
  'retryDisabled' |
  'completed' |
  'cancelled' |
  'backendError';

/**
 * BatchUiItem 表示批量 OCR 页面单个队列项的展示模型。
 * 维护边界：只保存文件名、状态和进度摘要，不保存图片 URI、objectKey 或 OCR 全文。
 */
class BatchUiItem {
  index: number = 0;
  fileName: string = '';
  status: string = '';
  note: string = '';
  progress: number = 0;
}

/**
 * BatchDraftItem 仅保存待提交批量 OCR 的脱敏展示信息。
 * 安全边界：真实 DeviceImageSelection 只放在页面私有瞬态队列里，不进入 @State。
 */
class BatchDraftItem {
  displayName: string = '';
  sourceLabel: string = '';
  mimeLabel: string = '';
}

/**
 * BatchMiniProgress 使用 Canvas 复刻 HTML `.mini-progress` 的 conic-gradient 标记。
 * 维护边界：仅绘制脱敏队列状态和百分比，不读取图片 URI、objectKey 或 OCR 正文。
 */
@Component
struct BatchMiniProgress {
  status: string = '';
  progress: number = 0;
  private progressContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  /**
   * 根据队列状态换算 HTML 原型中的 conic 角度。
   */
  private progressDegrees(): number {
    if (this.status === 'FAILED') {
      return 40;
    }
    if (this.status === 'RUNNING' || this.status === 'RETRYING') {
      return 260;
    }
    return this.progress >= 100 ? 360 : Math.max(0, Math.min(360, Math.floor(this.progress * 3.6)));
  }

  /**
   * 画布使用圆角矩形裁剪 + 扇形填充近似 CSS conic-gradient，避免堆叠矩形造成截图切块错位。
   */
  private drawProgress(): void {
    const ctx = this.progressContext;
    const size = 44;
    const radius = 14;
    const degree = this.progressDegrees();
    ctx.clearRect(0, 0, size, size);

    ctx.save();
    this.roundRectPath(ctx, 0.5, 0.5, size - 1, size - 1, radius);
    ctx.clip();
    ctx.fillStyle = AppTheme.COLOR_SURFACE_SOFT;
    ctx.fillRect(0, 0, size, size);
    ctx.beginPath();
    ctx.moveTo(size / 2, size / 2);
    ctx.arc(size / 2, size / 2, size, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * degree / 360, false);
    ctx.closePath();
    ctx.fillStyle = AppTheme.COLOR_BRAND;
    ctx.fill();
    ctx.restore();

    this.roundRectPath(ctx, 0.5, 0.5, size - 1, size - 1, radius);
    ctx.strokeStyle = AppTheme.COLOR_LINE_SOFT;
    ctx.lineWidth = 1;
    ctx.stroke();
  }

  private roundRectPath(ctx: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, radius: number): void {
    ctx.beginPath();
    ctx.moveTo(x + radius, y);
    ctx.lineTo(x + width - radius, y);
    ctx.arcTo(x + width, y, x + width, y + radius, radius);
    ctx.lineTo(x + width, y + height - radius);
    ctx.arcTo(x + width, y + height, x + width - radius, y + height, radius);
    ctx.lineTo(x + radius, y + height);
    ctx.arcTo(x, y + height, x, y + height - radius, radius);
    ctx.lineTo(x, y + radius);
    ctx.arcTo(x, y, x + radius, y, radius);
    ctx.closePath();
  }

  private progressLabel(): string {
    if (this.status === 'CANCELED') {
      return '已取消';
    }
    if (this.status === 'FAILED') {
      return '失败';
    }
    if (this.status === 'QUEUED' || this.status === 'PENDING') {
      return '排队';
    }
    if (this.status === 'RETRYING') {
      return '重试';
    }
    return this.progress.toString();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Canvas(this.progressContext)
        .width(44)
        .height(44)
        .onReady(() => this.drawProgress())
        .onAreaChange(() => this.drawProgress())
      Text(this.progressLabel())
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
    }
    .width(44)
    .height(44)
  }
}

/**
 * BatchOcrPage 对齐 HTML 原型的批量 OCR 队列页面。
 * 维护边界：队列为脱敏 UI 状态，不展示媒体 URI、objectKey 或 OCR 全文。
 */
@Entry
@Component
struct BatchOcrPage {
  @State authenticated: boolean = false;
  @State pageStage: BatchPageStage = 'guestDisabled';
  @State providerText: string = '识别服务待检查';
  @State providerAvailable: boolean = false;
  @State batchErrorMessage: string = '';
  @State noticeMessage: string = '';
  @State noticeVisible: boolean = false;
  @State retrying: boolean = false;
  @State items: BatchUiItem[] = [];
  @State progress: number = 0;
  @State currentJobId: string = '';
  @State currentJobStatus: string = '';
  @State currentBatchRecordId: number = 0;
  @State overviewTitle: string = '暂无批量任务';
  @State overviewMeta: string = '登录后创建批量 OCR，任务会显示在这里。';
  @State overviewBadge: string = '空';
  @State overviewTone: 'neutral' | 'ok' | 'warn' | 'danger' | 'dark' = 'neutral';
  @State appbarSubtitle: string = '多图识别队列';
  @State selectedCount: number = 0;
  @State createBusy: boolean = false;
  @State createErrorMessage: string = '';
  @State createHint: string = '';
  @State recognitionLanguageLabel: string = '跟随设置';
  @State saveToHistory: boolean = true;
  @State overviewEntered: boolean = false;
  @State listEntered: boolean = false;
  @State actionsEntered: boolean = false;
  private draftSelections: DeviceImageSelection[] = [];
  @State draftItems: BatchDraftItem[] = [];
  private batchRefreshRequestId: number = 0;
  private batchPickerMaxSelectNumber: number = 20;

  aboutToAppear(): void {
    this.triggerCardReveal();
    this.bootstrapPage();
  }

  /**
   * 页面启动时先做登录门禁，避免游客态触发受保护批量任务接口。
   */
  private async bootstrapPage(): Promise<void> {
    this.loadProvider();
    const hasToken = await TokenStorage.hasToken();
    this.authenticated = hasToken;
    if (!hasToken) {
      this.applyGuestState();
      return;
    }
    this.pageStage = 'empty';
    this.loadCreateHint();
    this.loadLatestBatch();
  }

  /**
   * 批量页主要卡片按 HTML motion-card 的 40ms stagger 进入；进度条仍保留 300ms tween。
   */
  private triggerCardReveal(): void {
    this.revealCard(() => this.overviewEntered = true, 0);
    this.revealCard(() => this.listEntered = true, 1);
    this.revealCard(() => this.actionsEntered = true, 2);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  /**
   * 查询 OCR 服务状态，只用于能力提示。
   */
  private async loadProvider(): Promise<void> {
    try {
      const health: OcrHealthResponse = await V2Service.getOcrHealth();
      this.providerAvailable = health.available;
      this.providerText = this.ocrServiceDisplayName(health.ocrEngine, health.available);
    } catch (_) {
      this.providerAvailable = false;
      this.providerText = '暂不可用';
      this.showNotice('识别服务状态暂不可用，可先查看批量任务页面。');
    }
  }

  /**
   * 将后端 OCR 引擎名称转换为面向用户的服务类别。
   * 安全边界：不把 backend fallback、CoreVisionKit 类名或内部引擎标识直接暴露到页面徽标。
   */
  private ocrServiceDisplayName(engine: string, available: boolean): string {
    if (!available) {
      return '暂不可用';
    }
    const normalized = engine.toLowerCase();
    if (normalized.includes('corevision') || normalized.includes('textrecognition') ||
      normalized.includes('device') || normalized.includes('端侧')) {
      return '端侧识别';
    }
    if (normalized.includes('backend') || normalized.includes('fallback') ||
      normalized.includes('server') || normalized.includes('paddle') || normalized.includes('云端')) {
      return '云端识别';
    }
    return '识别服务就绪';
  }

  /**
   * 展示批量任务的短反馈 toast。
   * 安全边界：只接收脱敏 UI 文案，不拼接媒体 URI、objectKey、OCR 全文或账号数据。
   */
  private showNotice(message: string): void {
    this.noticeMessage = message;
    this.noticeVisible = true;
    setTimeout(() => {
      if (this.noticeMessage === message) {
        this.noticeVisible = false;
      }
    }, AppMotion.DURATION_TOAST * 8);
  }

  private async loadLatestBatch(): Promise<void> {
    const requestId = ++this.batchRefreshRequestId;
    try {
      const hasToken = await TokenStorage.hasToken();
      this.authenticated = hasToken;
      if (!hasToken) {
        this.applyGuestState();
        return;
      }
      const jobs = await V2Service.listBatchTasks();
      if (requestId !== this.batchRefreshRequestId) {
        return;
      }
      if (jobs.length === 0) {
        this.batchErrorMessage = '';
        this.applyEmptyBatch('暂无批量任务', '选择多张图片后统一提交，任务会显示在这里。', '多图识别队列');
        return;
      }
      this.applyBatchJob(jobs[0]);
    } catch (error) {
      if (requestId !== this.batchRefreshRequestId) {
        return;
      }
      if (this.isUnauthorizedError(error)) {
        await this.applyAuthExpiredState();
        return;
      }
      const hasToken = await TokenStorage.hasToken();
      if (!hasToken) {
        this.applyGuestState();
        return;
      }
      this.applyBackendError();
      this.showNotice('批量任务暂时无法同步。');
    }
  }

  private applyGuestState(): void {
    this.authenticated = false;
    this.pageStage = 'guestDisabled';
    this.batchErrorMessage = '';
    this.clearBatchJobState();
    this.clearDraftQueueOnly();
    this.overviewTitle = '批量 OCR 需要登录';
    this.overviewMeta = '批量识别属于账户功能，游客状态下不可用。登录后即可创建批量任务并保存结果。';
    this.overviewBadge = '游客';
    this.overviewTone = 'dark';
    this.appbarSubtitle = '批量识别队列';
  }

  private isUnauthorizedError(error: Error): boolean {
    if (error instanceof ApiError) {
      return error.statusCode === 401 || error.code === 'UNAUTHORIZED' || error.code === 'AUTH_TOKEN_EXPIRED';
    }
    return false;
  }

  /**
   * 受保护批量接口返回认证失败时，立即收敛到未登录态，避免误报为后端不可用。
   */
  private async applyAuthExpiredState(): Promise<void> {
    await TokenStorage.clearTokens();
    this.applyGuestState();
    this.showNotice('登录状态已过期，请重新登录后使用批量 OCR。');
  }

  private applyBackendError(): void {
    this.pageStage = 'backendError';
    this.batchErrorMessage = '当前无法连接服务器，批量任务状态暂时无法显示。请检查网络后重试。';
    this.clearBatchJobState();
    this.overviewTitle = '无法加载批量队列';
    this.overviewMeta = this.batchErrorMessage;
    this.overviewBadge = '后端不可用';
    this.overviewTone = 'danger';
    this.appbarSubtitle = '批量识别队列';
  }

  private clearBatchJobState(): void {
    this.items = [];
    this.progress = 0;
    this.currentJobId = '';
    this.currentJobStatus = '';
    this.currentBatchRecordId = 0;
  }

  private applyEmptyBatch(title: string, meta: string, subtitle: string): void {
    this.pageStage = this.draftItems.length > 0 ? 'uploadReady' : 'empty';
    this.clearBatchJobState();
    this.overviewTitle = title;
    this.overviewMeta = meta;
    this.overviewBadge = '空';
    this.overviewTone = 'neutral';
    this.appbarSubtitle = subtitle;
  }

  /**
   * 计算批量上传区的软提示限制。
   * 说明：前端只给出建议值，最终是否可提交以后端 QUOTA_EXCEEDED 或 validation 为准。
   */
  private batchCreateLimitForMembership(level: string): number {
    const normalized = level.trim().toUpperCase();
    if (normalized === 'PRO') {
      return 10;
    }
    if (normalized === 'TEAM') {
      return 20;
    }
    return 2;
  }

  /**
   * 计算待提交图片列表的显示高度，避免长队列把后续卡片挤压得过于剧烈。
   * 说明：高度只基于脱敏条目数量，不读取图片内容或 URI。
   */
  private draftListHeight(): number {
    if (this.draftItems.length === 0) {
      return 84;
    }
    const rawHeight = this.draftItems.length * 62 + 12;
    return Math.min(Math.max(rawHeight, 84), 280);
  }

  /**
   * 将系统图片选择结果加入页面瞬态队列。
   * 安全边界：真实 selection 只进入私有数组；页面状态仅保存脱敏展示项和计数。
   */
  private addDraftSelection(selection: DeviceImageSelection): void {
    this.addDraftSelections([selection]);
  }

  /**
   * 将系统多选结果批量加入页面瞬态队列。
   * 安全边界：只批量生成脱敏展示项；本地 URI 仍只保留在私有内存数组中，离开页面即丢弃。
   */
  private addDraftSelections(selections: DeviceImageSelection[]): void {
    if (selections.length === 0) {
      return;
    }
    const nextSelections: DeviceImageSelection[] = [...this.draftSelections];
    const nextItems: BatchDraftItem[] = [...this.draftItems];
    selections.forEach((selection: DeviceImageSelection) => {
      nextSelections.push(selection);
      nextItems.push(this.toDraftItem(selection));
    });
    this.draftSelections = nextSelections;
    this.draftItems = nextItems;
    this.selectedCount = this.draftItems.length;
    this.createErrorMessage = '';
    this.pageStage = 'uploadReady';
  }

  /**
   * 将真实图片选择转换为脱敏展示项。
   * 维护说明：只显示安全文件名、来源和 mime 类型，不显示 URI 或二进制内容。
   */
  private toDraftItem(selection: DeviceImageSelection): BatchDraftItem {
    const item = new BatchDraftItem();
    item.displayName = selection.fileName.length > 0 ? selection.fileName : '未命名图片';
    item.sourceLabel = selection.sourceType === 'camera' ? '拍照' : '相册';
    item.mimeLabel = selection.mimeType.length > 0 ? selection.mimeType : 'image/*';
    return item;
  }

  /**
   * 单次从系统相册选择多张图片并追加到待提交队列。
   * 说明：系统选择器支持多选时会一次返回多张；若设备能力退化为单选，仍可继续调用追加。
   */
  private async appendImageToDraft(): Promise<void> {
    if (!this.authenticated) {
      this.applyGuestState();
      return;
    }
    this.pageStage = 'selectingImages';
    try {
      const selections: DeviceImageSelection[] = await DeviceImagePickerService.selectImages('album', this.batchPickerMaxSelectNumber);
      if (selections.length === 0) {
        this.pageStage = this.draftItems.length > 0 ? 'uploadReady' : 'empty';
        this.showNotice('未选择图片，待提交队列未变化。');
        return;
      }
      this.addDraftSelections(selections);
      this.showNotice('已添加 ' + selections.length.toString() + ' 张图片到待提交队列。');
    } catch (_) {
      this.pageStage = this.draftItems.length > 0 ? 'uploadReady' : 'createFailed';
      this.createErrorMessage = '图片选择失败，请稍后重试。';
      this.showNotice('图片选择失败。');
    }
  }

  /**
   * 删除待提交队列中的单张图片。
   * 维护说明：仅移除页面瞬态队列中的选择，不触碰已提交任务。
   */
  private removeDraftItem(index: number): void {
    if (index < 0 || index >= this.draftSelections.length) {
      return;
    }
    const nextSelections: DeviceImageSelection[] = [];
    const nextItems: BatchDraftItem[] = [];
    this.draftSelections.forEach((selection: DeviceImageSelection, itemIndex: number) => {
      if (itemIndex !== index) {
        nextSelections.push(selection);
        nextItems.push(this.toDraftItem(selection));
      }
    });
    this.draftSelections = nextSelections;
    this.draftItems = nextItems;
    this.selectedCount = nextItems.length;
    this.createErrorMessage = '';
    if (nextItems.length === 0 && (this.pageStage === 'uploadReady' || this.pageStage === 'createFailed')) {
      this.pageStage = this.currentJobId.length === 0 ? 'empty' : this.stageFromCurrentJob();
    }
  }

  /**
   * 清空待提交批量 OCR 队列。
   * 安全边界：只清除页面瞬态选择，不写本地存储、不影响已创建任务。
   */
  private clearDraftQueue(): void {
    this.clearDraftQueueOnly();
    if (this.currentJobId.length === 0 && this.authenticated) {
      this.pageStage = 'empty';
    }
  }

  private clearDraftQueueOnly(): void {
    this.draftSelections = [];
    this.draftItems = [];
    this.selectedCount = 0;
    this.createErrorMessage = '';
  }

  /**
   * 提交待提交图片并创建真实批量 OCR 任务。
   * 成功后先应用创建响应，再受控刷新最新任务，防止旧的列表刷新覆盖新任务。
   */
  private async createBatchFromDraft(): Promise<void> {
    if (this.createBusy) {
      return;
    }
    if (!this.authenticated) {
      this.applyGuestState();
      return;
    }
    if (this.draftSelections.length === 0) {
      this.createErrorMessage = '请先添加至少 1 张图片。';
      this.showNotice('请先添加图片。');
      this.pageStage = 'createFailed';
      return;
    }
    this.pageStage = 'creating';
    this.createBusy = true;
    this.createErrorMessage = '';
    this.batchRefreshRequestId++;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const preferences = await UserPreferenceService.load(context);
      const languageHint = UserPreferenceService.toBackendLanguageHint(preferences.recognitionLanguage);
      const createdJob = await V2Service.createBatchTask(context, this.draftSelections, languageHint, this.saveToHistory);
      if (createdJob.jobId.length > 0) {
        this.applyBatchJob(createdJob);
      }
      this.clearDraftQueue();
      this.showNotice(createdJob.recordId === undefined ? '批量 OCR 已创建。' : '批量 OCR 已创建，并保存为一条历史记录。');
      await this.loadLatestBatch();
    } catch (error) {
      if (this.isUnauthorizedError(error)) {
        await this.applyAuthExpiredState();
        return;
      }
      const message = error instanceof Error && error.message.length > 0 ? error.message : '批量 OCR 创建失败，请稍后重试。';
      this.createErrorMessage = message;
      this.pageStage = 'createFailed';
      this.showNotice('批量 OCR 创建失败。');
    } finally {
      this.createBusy = false;
    }
  }

  private applyBatchJob(job: BatchOcrTaskSummaryResponse): void {
    this.batchErrorMessage = '';
    this.authenticated = true;
    this.currentJobId = job.jobId;
    this.currentJobStatus = job.status;
    this.currentBatchRecordId = this.batchRecordId(job);
    this.progress = job.progress;
    this.items = job.items.map((item: BatchOcrTaskItemSummaryResponse) => this.toUiItem(item, job.progress));
    this.overviewTitle = this.batchOverviewTitle(job);
    this.overviewMeta = job.total.toString() + ' 个文件 · ' + job.completed.toString() + ' 已完成 · ' + job.failed.toString() + ' 失败';
    this.overviewBadge = this.batchBadgeLabel(job);
    this.overviewTone = this.batchBadgeTone(job);
    this.appbarSubtitle = this.batchSubtitle(job);
    this.pageStage = this.stageForJob(job);
  }

  private stageForJob(job: BatchOcrTaskSummaryResponse): BatchPageStage {
    const hasFailed = job.failed > 0 || job.items.some((item: BatchOcrTaskItemSummaryResponse) => item.status === 'FAILED');
    if (job.status === 'CANCELED') {
      return 'cancelled';
    }
    if (hasFailed) {
      return 'partialFailed';
    }
    if (job.status === 'SUCCESS') {
      return 'completed';
    }
    if (job.status === 'QUEUED' || job.status === 'PENDING' || job.status === 'RUNNING' || job.status === 'RETRYING') {
      return 'running';
    }
    return 'retryDisabled';
  }

  private batchRecordId(job: BatchOcrTaskSummaryResponse): number {
    if (job.recordId !== undefined && job.recordId > 0) {
      return job.recordId;
    }
    for (let index = 0; index < job.items.length; index++) {
      const recordId = job.items[index].recordId;
      if (recordId !== undefined && recordId > 0) {
        return recordId;
      }
    }
    return 0;
  }

  private openBatchRecord(): void {
    if (this.currentBatchRecordId <= 0) {
      this.showNotice('当前批量任务还没有可查看的历史记录。');
      return;
    }
    HistoryState.selectRecord(this.currentBatchRecordId.toString());
    AppNavigator.push(this.getUIContext(), AppRoutes.RECORD_DETAIL);
  }

  /**
   * 批量概览标题优先反映终态，避免已取消任务继续显示为“已完成”进度。
   */
  private batchOverviewTitle(job: BatchOcrTaskSummaryResponse): string {
    if (job.status === 'CANCELED') {
      return '任务已取消';
    }
    if (job.failed > 0 || job.items.some((item: BatchOcrTaskItemSummaryResponse) => item.status === 'FAILED')) {
      return '已完成（' + job.completed.toString() + ' / ' + job.total.toString() + '）';
    }
    if (job.status === 'SUCCESS') {
      return '100% 已完成';
    }
    return job.progress.toString() + '% 已完成';
  }

  private batchBadgeLabel(job: BatchOcrTaskSummaryResponse): string {
    if (job.failed > 0 || job.items.some((item: BatchOcrTaskItemSummaryResponse) => item.status === 'FAILED')) {
      return '部分失败';
    }
    if (job.status === 'SUCCESS') {
      return '已完成';
    }
    return this.statusLabel(job.status);
  }

  private batchBadgeTone(job: BatchOcrTaskSummaryResponse): 'neutral' | 'ok' | 'warn' | 'danger' | 'dark' {
    if (job.failed > 0 || job.items.some((item: BatchOcrTaskItemSummaryResponse) => item.status === 'FAILED')) {
      return 'warn';
    }
    return this.badgeTone(job.status);
  }

  private toUiItem(item: BatchOcrTaskItemSummaryResponse, jobProgress: number): BatchUiItem {
    const status = this.effectiveItemStatus(item.status);
    return {
      index: item.itemIndex,
      fileName: item.fileName,
      status: status,
      note: this.itemNote(item, status),
      progress: this.itemProgress(status, jobProgress)
    };
  }

  /**
   * 批量任务取消后，后端可能保留单项原始 RUNNING 状态用于审计；UI 必须按整单取消结果诚实展示不可继续处理。
   */
  private effectiveItemStatus(status: string): string {
    if (this.currentJobStatus === 'CANCELED' && status !== 'SUCCESS') {
      return 'CANCELED';
    }
    return status;
  }

  private itemNote(item: BatchOcrTaskItemSummaryResponse, status: string): string {
    if (status === 'SUCCESS') {
      return item.recordId === undefined ? '已完成识别' : '已保存到历史记录';
    }
    if (status === 'FAILED') {
      return item.failureReason ?? '识别失败，请重新选择图片后重试';
    }
    if (status === 'CANCELED') {
      return '任务已取消，未继续处理该文件';
    }
    if (status === 'RUNNING') {
      return '正在识别上传文件';
    }
    if (status === 'RETRYING') {
      return '正在重试失败图片';
    }
    if (status === 'QUEUED') {
      return '已进入批量队列，等待识别处理';
    }
    return '等待识别服务处理';
  }

  private itemProgress(status: string, jobProgress: number): number {
    if (status === 'SUCCESS') {
      return 100;
    }
    if (status === 'FAILED') {
      return 0;
    }
    if (status === 'CANCELED') {
      return 0;
    }
    if (status === 'RUNNING' || status === 'RETRYING') {
      return jobProgress;
    }
    return 0;
  }

  private batchSubtitle(job: BatchOcrTaskSummaryResponse): string {
    if (job.items.length > 0 && job.items[0].fileName.length > 0) {
      return job.items[0].fileName;
    }
    return '批量 OCR 任务';
  }

  private canCancelBatch(): boolean {
    if (this.currentJobId.length === 0) {
      return false;
    }
    return this.currentJobStatus === 'QUEUED' ||
      this.currentJobStatus === 'PENDING' ||
      this.currentJobStatus === 'RUNNING' ||
      this.currentJobStatus === 'RETRYING';
  }

  private hasFailedItem(): boolean {
    return this.items.some((item: BatchUiItem) => item.status === 'FAILED');
  }

  private hasSuccessfulItem(): boolean {
    return this.items.some((item: BatchUiItem) => item.status === 'SUCCESS');
  }

  private firstFailedItem(): BatchUiItem | undefined {
    const failedItems = this.items.filter((item: BatchUiItem) => item.status === 'FAILED');
    return failedItems.length > 0 ? failedItems[0] : undefined;
  }

  private async cancelCurrentBatch(): Promise<void> {
    if (!this.canCancelBatch()) {
      this.showNotice('当前批量任务无需取消。');
      return;
    }
    try {
      const canceledJob = await V2Service.cancelBatchTask(this.currentJobId);
      this.applyBatchJob(canceledJob);
      this.showNotice('批量任务已取消。');
    } catch (error) {
      if (this.isUnauthorizedError(error)) {
        await this.applyAuthExpiredState();
        return;
      }
      this.applyBackendError();
      this.showNotice('批量任务取消失败，请稍后重试。');
    }
  }

  private async retryFailed(): Promise<void> {
    const failedItem = this.firstFailedItem();
    if (failedItem === undefined || this.currentJobId.length === 0) {
      this.showNotice('当前批量任务没有可重试失败项。');
      return;
    }
    if (this.retrying) {
      return;
    }
    this.retrying = true;
    this.batchErrorMessage = '';
    try {
      const selection: DeviceImageSelection | undefined = await DeviceImagePickerService.selectImage('album');
      if (selection === undefined) {
        this.showNotice('未选择重试图片，批量任务未改变。');
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const retriedJob = await V2Service.retryBatchItem(context, this.currentJobId, failedItem.index, selection);
      this.applyBatchJob(retriedJob);
      this.showNotice('失败项已按新选择图片重新处理。');
    } catch (error) {
      if (this.isUnauthorizedError(error)) {
        await this.applyAuthExpiredState();
        return;
      }
      this.batchErrorMessage = '失败项重试未完成。请重新选择图片，并确认该任务仍包含失败项。';
      this.pageStage = 'partialFailed';
      this.showNotice('失败项重试失败。');
    } finally {
      this.retrying = false;
    }
  }

  /**
   * 读取会员等级与本地识别语言偏好，用于批量创建区的软提示。
   * 维护说明：这里只生成提示文案，不作为客户端真值拦截。
   */
  private async loadCreateHint(): Promise<void> {
    try {
      const membership = await V2Service.getMembership();
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const preferences = await UserPreferenceService.load(context);
      const languageLabel = UserPreferenceService.languageLabel(preferences.recognitionLanguage);
      const languageHint = UserPreferenceService.toBackendLanguageHint(preferences.recognitionLanguage);
      const limit = this.batchCreateLimitForMembership(membership.membershipLevel);
      this.recognitionLanguageLabel = languageLabel;
      this.createHint = `当前会员 ${membership.membershipLevel} · 软提示上限 ${limit} 张 · 识别语言 ${languageLabel}${languageHint.length > 0 ? '（' + languageHint + '）' : ''}`;
    } catch (_) {
      this.recognitionLanguageLabel = '跟随设置';
      this.createHint = '当前会员额度提示暂不可用，提交时以后端校验为准。';
    }
  }

  private badgeTone(status: string): 'neutral' | 'ok' | 'warn' | 'danger' | 'dark' {
    if (status === 'SUCCESS') {
      return 'ok';
    }
    if (status === 'FAILED') {
      return 'danger';
    }
    if (status === 'CANCELED') {
      return 'dark';
    }
    if (status === 'RETRYING') {
      return 'warn';
    }
    if (status === 'CONFIRM') {
      return 'warn';
    }
    return 'neutral';
  }

  /**
   * 将内部批处理状态映射为 HTML 原型中的中文短标签，避免设备截图出现工程态英文枚举。
   */
  private statusLabel(status: string): string {
    if (status === 'SUCCESS') {
      return '完成';
    }
    if (status === 'RUNNING') {
      return '运行中';
    }
    if (status === 'RETRYING') {
      return '重试中';
    }
    if (status === 'FAILED') {
      return '失败';
    }
    if (status === 'CANCELED') {
      return '已取消';
    }
    if (status === 'CONFIRM') {
      return '确认';
    }
    if (status === 'PENDING') {
      return '待处理';
    }
    if (status === 'QUEUED') {
      return '排队中';
    }
    return status;
  }

  @Builder
  private miniProgress(item: BatchUiItem) {
    BatchMiniProgress({ status: item.status, progress: item.progress })
  }

  @Builder
  private taskItem(item: BatchUiItem) {
    Row({ space: 10 }) {
      this.miniProgress(item)
      Column({ space: 3 }) {
        Text(item.fileName)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .maxLines(1)
          .width('100%')
        Text(item.note)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      HtmlBadge({ label: this.statusLabel(item.status), tone: this.badgeTone(item.status) })
    }
    .width('100%')
    .height(62)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private draftItemRow(item: BatchDraftItem, index: number) {
    Row({ space: 10 }) {
      HtmlFileMark({ label: 'IMG', tone: 'neutral' })
      Column({ space: 3 }) {
        Text(item.displayName)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .maxLines(1)
          .width('100%')
        Text(item.sourceLabel + ' · ' + item.mimeLabel)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      HtmlCompactActionButton({
        label: '删除',
        danger: true,
        enabledState: !this.createBusy,
        onTap: () => this.removeDraftItem(index)
      })
        .width(52)
    }
    .width('100%')
    .height(62)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private stateBlock(
    tag: string,
    title: string,
    body: string,
    tone: 'neutral' | 'ok' | 'warn' | 'danger' | 'dark',
    mark: string,
    primaryLabel: string,
    primaryTap: () => void,
    secondaryLabel: string,
    secondaryTap: () => void,
    thirdLabel: string,
    thirdTap: () => void
  ) {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        HtmlFileMark({ label: mark, tone: tone })
        Column({ space: 6 }) {
          HtmlBadge({ label: tag, tone: tone })
          Text(title)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(28)
            .width('100%')
          Text(body)
            .fontSize(AppTheme.FONT_META)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
            .maxLines(4)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (primaryLabel.length > 0) {
        TextActionButton({ label: primaryLabel, primary: true, onTap: primaryTap })
          .width('100%')
      }
      if (secondaryLabel.length > 0 || thirdLabel.length > 0) {
        Row({ space: 8 }) {
          if (secondaryLabel.length > 0) {
            TextActionButton({ label: secondaryLabel, onTap: secondaryTap })
              .layoutWeight(1)
          }
          if (thirdLabel.length > 0) {
            TextActionButton({ label: thirdLabel, onTap: thirdTap })
              .layoutWeight(1)
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: tone === 'danger' ? AppTheme.COLOR_DANGER_LINE : AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .opacity(this.overviewEntered ? 1 : 0)
    .translate({ y: this.overviewEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private emptyState() {
    Column({ space: 12 }) {
      Column({ space: 13 }) {
        Row({ space: 12 }) {
          HtmlFileMark({ label: 'IMG', tone: 'neutral' })
          Column({ space: 5 }) {
            Row({ space: 8 }) {
              Text('创建批量任务')
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .fontColor(AppTheme.COLOR_TEXT)
                .lineHeight(24)
                .layoutWeight(1)
              HtmlBadge({ label: this.providerAvailable ? '可用' : '待确认', tone: this.providerAvailable ? 'ok' : 'neutral' })
            }
            .width('100%')

            Text('一次选择多张图片，统一提交后按文件查看识别进度。')
              .fontSize(AppTheme.FONT_META)
              .fontColor(AppTheme.COLOR_TEXT_MUTED)
              .lineHeight(AppTheme.LINE_META)
              .width('100%')
              .maxLines(2)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)

        Row({ space: 8 }) {
          this.emptyStepPill('1', '多图选择')
          this.emptyStepPill('2', '统一提交')
          this.emptyStepPill('3', '逐项进度')
        }
        .width('100%')

        Row({ space: 8 }) {
          TextActionButton({
            label: '选择图片',
            primary: true,
            enabledState: !this.createBusy,
            onTap: () => this.appendImageToDraft()
          })
            .layoutWeight(1)
          HtmlCompactActionButton({
            label: '刷新',
            enabledState: !this.createBusy,
            onTap: () => this.loadLatestBatch()
          })
            .width(76)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(18)
      .opacity(this.overviewEntered ? 1 : 0)
      .translate({ y: this.overviewEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
    }
    .width('100%')

    HtmlSectionHead({ title: '最近任务', meta: '暂无' })
    this.recentEmptyCard()
  }

  @Builder
  private emptyStepPill(index: string, label: string) {
    Row({ space: 5 }) {
      Text(index)
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT_INVERSE)
        .textAlign(TextAlign.Center)
        .width(18)
        .height(18)
        .backgroundColor(AppTheme.COLOR_ACTION)
        .borderRadius(9)
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .maxLines(1)
    }
    .height(30)
    .padding({ left: 7, right: 8 })
    .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_BADGE)
    .layoutWeight(1)
  }

  @Builder
  private recentEmptyCard() {
    Row({ space: 10 }) {
      HtmlFileMark({ label: 'DOC', tone: 'neutral' })
      Column({ space: 3 }) {
        Text('还没有批量任务')
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .width('100%')
          .maxLines(1)
        Text('创建后会在这里显示任务状态、失败项和导出入口。')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')
          .maxLines(2)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height(66)
    .padding({ left: 12, right: 12 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  private finishSelectingImages(): void {
    this.pageStage = this.draftItems.length > 0 ? 'uploadReady' : 'empty';
  }

  @Builder
  private selectingImagesState() {
    this.stateBlock(
      '选择图片中',
      '正在选择图片',
      '已调起系统图片选择器。可一次选择多张图片，也可以返回后继续追加，选择完成后进入待上传队列。',
      'neutral',
      'IMG',
      '完成选择（已选 ' + this.selectedCount.toString() + ' 张）',
      () => this.finishSelectingImages(),
      '继续添加图片',
      () => this.appendImageToDraft(),
      '取消',
      () => this.cancelDraftSelection()
    )
  }

  private cancelDraftSelection(): void {
    this.clearDraftQueueOnly();
    this.pageStage = this.currentJobId.length === 0 ? 'empty' : this.stageFromCurrentJob();
  }

  private stageFromCurrentJob(): BatchPageStage {
    if (this.currentJobStatus === 'CANCELED') {
      return 'cancelled';
    }
    if (this.hasFailedItem()) {
      return 'partialFailed';
    }
    if (this.currentJobStatus === 'SUCCESS') {
      return 'completed';
    }
    if (this.canCancelBatch()) {
      return 'running';
    }
    return 'retryDisabled';
  }

  @Builder
  private selectedImageQueue() {
    List({ space: 0 }) {
      ForEach(this.draftItems, (item: BatchDraftItem, index?: number) => {
        ListItem() {
          this.draftItemRow(item, index === undefined ? 0 : index)
        }
      }, (item: BatchDraftItem, index?: number) => index === undefined ? item.displayName : `${index}-${item.displayName}`)
    }
    .width('100%')
    .height(this.draftListHeight())
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
  }

  @Builder
  private uploadReadyState() {
    Column({ space: 12 }) {
      Column({ space: 10 }) {
        Row({ space: 8 }) {
          Column({ space: 3 }) {
            Text('已选 ' + this.selectedCount.toString() + ' 张图片')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.COLOR_TEXT)
              .lineHeight(28)
              .width('100%')
            Text('确认设置后可开始批量识别')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
              .width('100%')
          }
          .layoutWeight(1)
          HtmlBadge({ label: '待上传', tone: 'neutral' })
        }
        .width('100%')
      }
      .width('100%')
      .padding(AppTheme.CARD_PADDING)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)

      HtmlSectionHead({ title: '已选图片', meta: this.selectedCount.toString() + ' 张' })
      this.selectedImageQueue()

      Column({ space: 12 }) {
        Row({ space: 10 }) {
          Text('识别语言')
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .layoutWeight(1)
          Text(this.recognitionLanguageLabel)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          HtmlBadge({ label: '可选', tone: 'neutral' })
        }
        .width('100%')

        Row({ space: 8 }) {
          Toggle({ type: ToggleType.Checkbox, isOn: this.saveToHistory })
            .enabled(!this.createBusy)
            .onChange((value: boolean) => this.saveToHistory = value)
          Text('识别成功后自动保存到历史记录')
            .fontSize(AppTheme.FONT_META)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .layoutWeight(1)
        }
        .width('100%')

        if (this.createHint.length > 0) {
          Text(this.createHint)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .width('100%')
            .maxLines(2)
        }
      }
      .width('100%')
      .padding(AppTheme.CARD_PADDING)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)

      Row({ space: 8 }) {
        TextActionButton({ label: '继续添加图片', enabledState: !this.createBusy, onTap: () => this.appendImageToDraft() })
          .layoutWeight(1)
        TextActionButton({ label: '开始批量识别', primary: true, enabledState: this.selectedCount > 0 && !this.createBusy, onTap: () => this.createBatchFromDraft() })
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .opacity(this.actionsEntered ? 1 : 0)
    .translate({ y: this.actionsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private creatingState() {
    this.stateBlock(
      '创建中',
      '正在创建批量 OCR 任务',
      '正在提交 ' + this.selectedCount.toString() + ' 张图片，请勿重复提交。创建成功后将自动进入任务进度页。',
      'warn',
      'IMG',
      '',
      () => {},
      '',
      () => {},
      '',
      () => {}
    )
    Column({ space: 8 }) {
      this.skeletonRow()
      this.skeletonRow()
    }
    .width('100%')
    .padding(12)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private skeletonRow() {
    Row({ space: 10 }) {
      Column().width(44).height(44).backgroundColor(AppTheme.COLOR_SURFACE_SOFT).borderRadius(14)
      Column({ space: 8 }) {
        Column().width('60%').height(10).backgroundColor(AppTheme.COLOR_SURFACE_SOFT).borderRadius(5)
        Column().width('42%').height(8).backgroundColor(AppTheme.COLOR_SURFACE_SOFT).borderRadius(4)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .height(56)
  }

  @Builder
  private createFailedState() {
    this.stateBlock(
      '创建失败',
      '批量任务创建失败',
      this.createErrorMessage.length > 0 ? this.createErrorMessage : '可能原因：未选择图片、图片格式或大小不符合要求、会员额度或并发数已达上限，或网络/服务暂时不可用。任务尚未创建。',
      'danger',
      'IMG',
      '重新选择图片',
      () => this.restartSelection(),
      '重试创建',
      () => this.createBatchFromDraft(),
      '返回',
      () => this.cancelDraftSelection()
    )
  }

  private restartSelection(): void {
    this.clearDraftQueueOnly();
    this.appendImageToDraft();
  }

  private retryButtonLabel(): string {
    if (this.retrying) {
      return '重试中...';
    }
    if (this.hasFailedItem()) {
      return '选择图片重试';
    }
    if (this.pageStage === 'completed' || this.pageStage === 'retryDisabled') {
      return '选择图片重试（无失败项）';
    }
    return '无失败项';
  }

  private exportButtonLabel(): string {
    return this.pageStage === 'partialFailed' ? '导出成功项' : '全部导出';
  }

  private queueMeta(): string {
    if (this.pageStage === 'partialFailed') {
      return this.items.filter((item: BatchUiItem) => item.status === 'FAILED').length.toString() + ' 个失败';
    }
    if (this.pageStage === 'completed' || this.pageStage === 'retryDisabled') {
      return '全部完成';
    }
    return '按处理状态排序';
  }

  private canShowCreateEntryWithJob(): boolean {
    return this.authenticated &&
      this.currentJobId.length > 0 &&
      (this.pageStage === 'running' ||
        this.pageStage === 'partialFailed' ||
        this.pageStage === 'completed' ||
        this.pageStage === 'retryDisabled');
  }

  @Builder
  private createEntryState() {
    Row({ space: 10 }) {
      HtmlFileMark({ label: 'IMG', tone: 'neutral' })
      Column({ space: 3 }) {
        Row({ space: 8 }) {
          Text('新建任务')
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .layoutWeight(1)
          HtmlBadge({ label: '多选', tone: 'neutral' })
        }
        .width('100%')
        Text('当前队列会保留')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')
          .maxLines(1)
      }
      .layoutWeight(1)
      HtmlCompactActionButton({
        label: '选择',
        primary: true,
        enabledState: !this.createBusy,
        onTap: () => this.appendImageToDraft()
      })
        .width(68)
      HtmlCompactActionButton({
        label: '刷新',
        enabledState: !this.createBusy,
        onTap: () => this.loadLatestBatch()
      })
        .width(68)
    }
    .width('100%')
    .height(82)
    .padding({ left: 12, right: 12 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(18)
    .alignItems(VerticalAlign.Center)
    .opacity(this.actionsEntered ? 1 : 0)
    .translate({ y: this.actionsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private jobOverviewState() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(this.overviewTitle)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(28)
          .layoutWeight(1)
        HtmlBadge({ label: this.overviewBadge, tone: this.overviewTone })
      }
      .width('100%')
      Text(this.overviewMeta)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .width('100%')
      Row({ space: 8 }) {
        HtmlBadge({ label: this.providerAvailable ? '识别服务可用' : '识别服务待确认', tone: this.providerAvailable ? 'ok' : 'warn' })
        HtmlBadge({ label: this.providerText, tone: 'neutral' })
      }
      .width('100%')
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(8)
          .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
          .borderRadius(4)
        Column()
          .width(this.progress.toString() + '%')
          .height(8)
          .backgroundColor(AppTheme.COLOR_BRAND)
          .borderRadius(4)
          .animation({ duration: AppMotion.DURATION_PROGRESS_TWEEN, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(8)
      Row({ space: 8 }) {
        if (this.canCancelBatch()) {
          TextActionButton({ label: '取消任务', onTap: () => this.cancelCurrentBatch() })
            .layoutWeight(1)
        }
        if (this.pageStage === 'partialFailed' || this.pageStage === 'retryDisabled') {
          TextActionButton({
            label: this.retryButtonLabel(),
            enabledState: this.hasFailedItem() && !this.retrying,
            onTap: () => this.retryFailed()
          })
            .layoutWeight(1)
        }
        if (this.pageStage === 'completed') {
          TextActionButton({
            label: '全部导出',
            primary: true,
            enabledState: this.hasSuccessfulItem(),
            onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER)
          })
            .layoutWeight(1)
        } else if (this.pageStage === 'partialFailed' || this.pageStage === 'retryDisabled') {
          TextActionButton({
            label: this.exportButtonLabel(),
            primary: true,
            enabledState: this.hasSuccessfulItem(),
            onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER)
          })
            .layoutWeight(1)
        }
      }
      .width('100%')

      if ((this.pageStage === 'completed' || this.pageStage === 'retryDisabled') && !this.hasFailedItem()) {
        Text('无失败项时「选择图片重试」不可用；失败项重试必须重新选择图片后才能调用真实接口。')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .width('100%')
          .maxLines(2)
      }

      if (this.currentBatchRecordId > 0) {
        Row({ space: 8 }) {
          TextActionButton({ label: '查看历史记录', primary: true, enabledState: true, onTap: () => this.openBatchRecord() })
            .layoutWeight(1)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .opacity(this.overviewEntered ? 1 : 0)
    .translate({ y: this.overviewEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private taskQueueState() {
    HtmlSectionHead({ title: '任务队列', meta: this.queueMeta() })
    List({ space: 0 }) {
      ForEach(this.items, (item: BatchUiItem) => {
        ListItem() {
          this.taskItem(item)
        }
      }, (item: BatchUiItem) => item.index.toString())
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    .opacity(this.listEntered ? 1 : 0)
    .translate({ y: this.listEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private plannedActionsState() {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: '批量处理动作', meta: '保留现有任务操作' })
      Scroll() {
        Row({ space: 8 }) {
          HtmlToolChip({ label: '批量纠错', enabledState: false, onTap: () => this.showNotice('批量纠错服务规划中，开放后可用于整理多张图片文本。') })
          HtmlToolChip({ label: '字段提取', enabledState: false, onTap: () => this.showNotice('字段提取服务规划中，开放后可用于批量整理关键信息。') })
          HtmlToolChip({ label: '转 Markdown', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER) })
        }
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      Row({ space: 8 }) {
        HtmlBadge({ label: '服务规划中', tone: 'neutral' })
        Text('批量结果完成后，可进入导出中心继续处理文档。')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .layoutWeight(1)
          .maxLines(2)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .opacity(this.actionsEntered ? 1 : 0)
    .translate({ y: this.actionsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private cancelledState() {
    this.stateBlock(
      '已取消',
      '批量任务已取消',
      '当前批量任务已被取消，已完成的文件仍保留在历史记录中。你可以重新发起批量识别。',
      'dark',
      'IMG',
      '重新发起',
      () => this.restartSelection(),
      '查看已完成',
      () => this.openCompletedRecords(),
      '',
      () => {}
    )
  }

  private openCompletedRecords(): void {
    if (this.currentBatchRecordId > 0) {
      this.openBatchRecord();
      return;
    }
    AppNavigator.push(this.getUIContext(), AppRoutes.HISTORY);
  }

  @Builder
  private backendErrorState() {
    this.stateBlock(
      '后端不可用',
      '无法加载批量队列',
      '当前无法连接服务器，批量任务状态暂时无法显示。请检查网络后重试。',
      'danger',
      'IMG',
      '重试',
      () => this.loadLatestBatch(),
      '',
      () => {},
      '',
      () => {}
    )
  }

  @Builder
  private guestDisabledState() {
    this.stateBlock(
      '游客 · 禁用',
      '批量 OCR 需要登录',
      '批量识别属于账户功能，游客状态下不可用。登录后即可创建批量任务并保存结果。',
      'dark',
      'DOC',
      '去登录',
      () => AppNavigator.push(this.getUIContext(), AppRoutes.LOGIN),
      '',
      () => {},
      '',
      () => {}
    )
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 16 }) {
          HtmlAppBar({
            title: '批量 OCR',
            subtitle: this.appbarSubtitle,
            actionLabel: '···',
            onAction: () => this.authenticated ? this.loadLatestBatch() : this.showNotice('请先登录后查看批量任务。')
          })

          if (this.pageStage === 'guestDisabled') {
            this.guestDisabledState()
          } else if (this.pageStage === 'backendError') {
            this.backendErrorState()
          } else if (this.pageStage === 'empty') {
            this.emptyState()
          } else if (this.pageStage === 'selectingImages') {
            this.selectingImagesState()
          } else if (this.pageStage === 'uploadReady') {
            this.uploadReadyState()
          } else if (this.pageStage === 'creating') {
            this.creatingState()
          } else if (this.pageStage === 'createFailed') {
            this.createFailedState()
          } else if (this.pageStage === 'cancelled') {
            this.cancelledState()
          } else {
            if (this.canShowCreateEntryWithJob()) {
              this.createEntryState()
            }
            this.jobOverviewState()
            this.taskQueueState()
            this.plannedActionsState()
          }

          if (this.batchErrorMessage.length > 0 && this.pageStage !== 'backendError') {
            StatusBanner({ label: '错误', title: '批量队列暂不可用', message: this.batchErrorMessage, tone: 'danger' })
          }

          HtmlToast({ message: this.noticeMessage, visible: this.noticeVisible })
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

      AppBottomNav({ activeTab: 'batch' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
