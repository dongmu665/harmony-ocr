import { common, Want } from '@kit.AbilityKit';
import { Environment, fileIo, fileUri } from '@kit.CoreFileKit';
import { ApiError } from '../common/network/ApiTypes';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import { HtmlAppBar, HtmlBadge, HtmlCompactActionButton, HtmlFileMark, HtmlSectionHead, HtmlStatusBar, HtmlToast, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { HistoryState } from '../features/history/HistoryState';
import { RecordService } from '../features/record/RecordService';
import { ExportFormatType, ExportJobResponse } from '../features/v2/V2Models';
import { V2Service } from '../features/v2/V2Service';

/**
 * ExportCenterPage 提供 V2.0 导出格式选择和 PDF/searchable PDF 任务反馈。
 * 维护边界：页面只提交记录 ID、安全文件名和 searchable 意图，不展示完整路径、objectKey 或导出全文。
 */
@Entry
@Component
struct ExportCenterPage {
  @State recordIdsText: string = '';
  @State fileName: string = '';
  @State searchable: boolean = true;
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State noticeVisible: boolean = false;
  @State recentJob?: ExportJobResponse = undefined;
  @State exportJobs: ExportJobResponse[] = [];
  @State exportHistoryMeta: string = '登录后同步导出记录';
  @State selectedFormat: ExportFormatType = 'SEARCHABLE_PDF';
  @State formatEntered: boolean = false;
  @State taskEntered: boolean = false;
  @State recentEntered: boolean = false;
  @State downloadingJobId: string = '';
  @State openingJobId: string = '';
  @State downloadedJobId: string = '';
  @State downloadedFileName: string = '';
  @State downloadStatusMessage: string = '';
  @State openPreviewMessage: string = '';
  private downloadedFilePath: string = '';
  private downloadedContentType: string = '';

  aboutToAppear(): void {
    this.triggerCardReveal();
    this.loadDefaultRecordId();
    this.loadExportJobs();
  }

  /**
   * 导出中心区块按 HTML 原型 motion-card 节奏进入，不改变任务创建逻辑。
   */
  private triggerCardReveal(): void {
    this.revealCard(() => this.formatEntered = true, 0);
    this.revealCard(() => this.taskEntered = true, 1);
    this.revealCard(() => this.recentEntered = true, 2);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  private parseRecordIds(): number[] {
    const parts = this.recordIdsText.split(',');
    const ids: number[] = [];
    for (let index = 0; index < parts.length; index++) {
      const value = Number(parts[index].trim());
      if (!Number.isNaN(value) && value > 0) {
        ids.push(value);
      }
    }
    return ids;
  }

  /**
   * 为导出中心准备一个真实归属记录 ID。
   * 说明：只读取当前用户的记录元数据 ID，不读取、不展示 OCR 全文、图片 objectKey 或下载路径。
   */
  private async loadDefaultRecordId(): Promise<void> {
    if (this.recordIdsText.trim().length > 0) {
      return;
    }
    const selectedRecordId = HistoryState.getCurrentRecordId();
    if (selectedRecordId.length > 0) {
      this.recordIdsText = selectedRecordId;
      return;
    }
    try {
      const page = await RecordService.listRecords({ page: 0, size: 1 });
      if (page.items.length > 0) {
        this.recordIdsText = page.items[0].id.toString();
      }
    } catch (_) {
      this.errorMessage = '导出记录编号自动填充失败，请从历史记录进入或手动输入。';
    }
  }

  /**
   * 选择导出格式。
   * 说明：所有格式都走后端通用导出接口，后端统一执行记录归属校验与文件名清理。
   */
  private selectFormat(format: ExportFormatType): void {
    this.selectedFormat = format;
    this.searchable = format === 'SEARCHABLE_PDF';
  }

  /**
   * 展示导出中心的短反馈 toast。
   * 安全边界：只接收脱敏状态文案，不展示导出路径、objectKey、记录集合或 OCR 全文。
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

  /**
   * 创建通用导出任务。
   * 失败时只展示后端脱敏错误，不记录用户输入的记录集合或文件路径。
   */
  private async createExport(): Promise<void> {
    const ids = this.parseRecordIds();
    if (ids.length === 0) {
      this.errorMessage = '请输入至少一个记录编号，例如 1 或 1,2,3。';
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '';
    this.noticeVisible = false;
    try {
      if (this.selectedFormat === 'PDF' || this.selectedFormat === 'SEARCHABLE_PDF') {
        this.recentJob = await V2Service.createPdfExport({
          recordIds: ids,
          fileName: this.safeDefaultFileName(),
          searchable: this.selectedFormat === 'SEARCHABLE_PDF'
        });
      } else {
        this.recentJob = await V2Service.createExport({
          recordIds: ids,
          format: this.selectedFormat,
          fileName: this.safeDefaultFileName()
        });
      }
      await this.loadExportJobs();
      this.showNotice('导出任务已创建，文件名会由服务安全处理。');
    } catch (error) {
      this.errorMessage = this.safeApiErrorMessage(error, '导出任务创建失败，请确认已登录且记录归属正确。');
    } finally {
      this.loading = false;
    }
  }

  private safeDefaultFileName(): string {
    if (this.fileName.trim().length > 0) {
      return this.fileName.trim();
    }
    if (this.selectedFormat === 'TXT') {
      return 'ocr-export.txt';
    }
    if (this.selectedFormat === 'MARKDOWN') {
      return 'ocr-export.md';
    }
    if (this.selectedFormat === 'JSON') {
      return 'ocr-export.json';
    }
    return 'ocr-export.pdf';
  }

  private exportProgress(): number {
    if (this.recentJob !== undefined) {
      return this.recentJob.progress;
    }
    if (this.loading) {
      return 0;
    }
    return 0;
  }

  private async loadExportJobs(): Promise<void> {
    try {
      this.exportJobs = await V2Service.listExportJobs();
      this.exportHistoryMeta = this.exportJobs.length > 0 ? this.exportJobs.length.toString() + ' 个导出任务' : '暂无导出任务';
      if (this.recentJob === undefined && this.exportJobs.length > 0) {
        this.recentJob = this.exportJobs[0];
      }
    } catch (_) {
      this.exportJobs = [];
      this.exportHistoryMeta = '暂时无法同步导出记录';
    }
  }

  /**
   * 取消导出任务并刷新队列。
   * 安全边界：取消操作只按 jobId 调用后端，不读取或展示下载路径、objectKey、文件 bytes 或 OCR 全文。
   */
  private async cancelExportJob(jobId: string): Promise<void> {
    this.errorMessage = '';
    try {
      const canceledJob = await V2Service.cancelExportJob(jobId);
      this.recentJob = canceledJob;
      await this.loadExportJobs();
      this.showNotice('导出任务已取消。');
    } catch (error) {
      this.errorMessage = this.safeApiErrorMessage(error, '导出任务取消失败，请确认任务仍处于待处理或执行中状态。');
    }
  }

  private canCancelExport(job: ExportJobResponse): boolean {
    return job.status === 'PENDING' || job.status === 'RUNNING';
  }

  private canDownloadExport(job: ExportJobResponse): boolean {
    return job.status === 'SUCCESS' && (job.downloadPath ?? '').length > 0;
  }

  /**
   * 准备公共下载目录下的 Harmony OCR 导出文件夹。
   * 安全边界：绝对路径只作为本地文件写入目标，不进入 UI、日志或错误信息。
   */
  private ensureDownloadExportDirectory(): string {
    try {
      const exportDir = Environment.getUserDownloadDir() + '/HarmonyOCR/Exports';
      let exportDirExists = false;
      try {
        exportDirExists = fileIo.accessSync(exportDir);
      } catch (_) {
        exportDirExists = false;
      }
      if (!exportDirExists) {
        fileIo.mkdirSync(exportDir, true);
      }
      return exportDir;
    } catch (_) {
      throw new Error('EXPORT_DOWNLOAD_DIRECTORY_UNAVAILABLE');
    }
  }

  /**
   * 下载成功导出文件到公共 Download/HarmonyOCR/Exports 文件夹。
   * 安全边界：只展示相对文件夹、文件名和大小；完整保存路径仅在内存中用于随后打开，不进入 UI、日志或报告。
   */
  private async downloadExportJob(job: ExportJobResponse): Promise<void> {
    if (!this.canDownloadExport(job) || this.downloadingJobId.length > 0) {
      this.errorMessage = '导出文件尚未准备好下载。';
      return;
    }
    this.downloadingJobId = job.jobId;
    this.errorMessage = '';
    try {
      const content = await V2Service.downloadExportJob(job.jobId);
      const exportDir = this.ensureDownloadExportDirectory();
      const safeName = this.safeExportFileName(job.fileName);
      const outputPath = exportDir + '/' + safeName;
      let outputFile: fileIo.File | undefined = undefined;
      try {
        outputFile = fileIo.openSync(
          outputPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.WRITE_ONLY
        );
        fileIo.writeSync(outputFile.fd, content);
      } finally {
        if (outputFile !== undefined) {
          fileIo.closeSync(outputFile);
        }
      }
      this.downloadedJobId = job.jobId;
      this.downloadedFileName = safeName;
      this.downloadedFilePath = outputPath;
      this.downloadedContentType = job.contentType;
      this.downloadStatusMessage = '导出文件已保存到 Download/HarmonyOCR/Exports：' + safeName + '，大小 ' + this.formatSize(content.byteLength);
      this.openPreviewMessage = '';
      this.showNotice(this.downloadStatusMessage);
    } catch (error) {
      this.errorMessage = this.safeApiErrorMessage(error, '导出文件下载失败，请检查任务状态和账号权限。');
    } finally {
      this.downloadingJobId = '';
    }
  }

  /**
   * 调起系统打开/分享面板查看最近下载的导出文件。
   * 安全边界：只使用内存中的保存路径发起系统能力，不把路径展示在页面上。
   */
  private async openDownloadedExport(job: ExportJobResponse): Promise<void> {
    if (this.downloadedJobId !== job.jobId || this.downloadedFilePath.length === 0 || this.openingJobId.length > 0) {
      this.errorMessage = '请先下载该导出文件，再打开预览。';
      return;
    }
    this.openingJobId = job.jobId;
    this.errorMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const openUri = fileUri.getUriFromPath(this.downloadedFilePath);
      const openType = this.downloadedContentType.length > 0 ? this.downloadedContentType : job.contentType;
      const viewWant: Want = {
        action: 'ohos.want.action.viewData',
        uri: openUri,
        type: openType
      };
      try {
        await context.startAbility(viewWant);
        this.showNotice('已请求系统打开：' + this.downloadedFileName);
      } catch (_) {
        const shareWant: Want = {
          action: 'ohos.want.action.sendData',
          uri: openUri,
          type: openType,
          parameters: {
            'ohos.extra.param.key.contentTitle': this.downloadedFileName
          }
        };
        await context.startAbility(shareWant);
        this.showNotice('已请求系统分享：' + this.downloadedFileName);
      }
    } catch (_) {
      this.openPreviewMessage = '文件已保存，可在系统文件能力可用后打开：' + this.downloadedFileName + '。';
      this.showNotice(this.openPreviewMessage);
    } finally {
      this.openingJobId = '';
    }
  }

  /**
   * 将后端统一错误转换成可见但脱敏的 UI 文案。
   * 安全边界：只展示错误码、HTTP 状态和后端业务消息，不展示 recordIds、objectKey、路径或 OCR 全文。
   */
  private safeApiErrorMessage(error: Object, fallback: string): string {
    if (error instanceof ApiError) {
      if (error.code === 'QUOTA_EXCEEDED' || error.statusCode === 429) {
        return '当前账号额度已用尽，请升级或等待额度重置。';
      }
      if (error.message && error.message.length > 0 && error.message.length < 120) {
        const status = error.statusCode !== undefined ? '服务状态 ' + error.statusCode.toString() : '服务状态待确认';
        return status + '：' + error.message;
      }
      return fallback;
    }
    return fallback;
  }

  private safeExportFileName(fileName: string): string {
    const normalized = fileName.replace(/[\\/:*?"<>|\r\n]+/g, '_').replace(/_+/g, '_').trim();
    return normalized.length > 0 ? normalized : 'harmony-ocr-export.bin';
  }

  private exportLifecycleSummary(job: ExportJobResponse): string {
    if (job.statusHistory === undefined || job.statusHistory.length === 0) {
      return this.exportStatusLabel(job.status) + ' ' + job.progress.toString() + '%';
    }
    const steps: string[] = [];
    const start = Math.max(0, job.statusHistory.length - 3);
    for (let index = start; index < job.statusHistory.length; index++) {
      const event = job.statusHistory[index];
      steps.push(this.exportStatusLabel(event.status) + ' ' + event.progress.toString() + '%');
    }
    return steps.join(' · ');
  }

  @Builder
  private formatCard(label: string, format: ExportFormatType, description: string) {
    Button() {
      Column({ space: 5 }) {
        Text(label)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .width('100%')
        Text(description)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .layoutWeight(1)
    .height(76)
    .type(ButtonType.Normal)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({
      width: this.selectedFormat === format ? 1.5 : AppTheme.HAIRLINE,
      color: this.selectedFormat === format ? AppTheme.COLOR_ACCENT_SOFT : AppTheme.COLOR_LINE_SOFT
    })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .onClick(() => {
      this.selectFormat(format);
      this.showNotice(description);
    })
  }

  @Builder
  private progressBlock() {
    Column({ space: 8 }) {
      Text(this.recentJob !== undefined ? this.recentJob.fileName : (this.fileName.trim().length > 0 ? this.fileName.trim() : '等待创建导出任务'))
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .width('100%')
        .maxLines(1)
      Text(this.loading ? '正在提交导出请求' : (this.recentJob !== undefined ? this.exportStatusLabel(this.recentJob.status) : '创建任务后显示任务进度'))
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .width('100%')
      if (this.recentJob !== undefined && this.recentJob.checksumSha256.length > 0) {
        Text('文件校验 ' + this.shortChecksum(this.recentJob.checksumSha256))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(7)
          .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
          .borderRadius(4)
        Column()
          .width(this.exportProgress().toString() + '%')
          .height(7)
          .backgroundColor(AppTheme.COLOR_BRAND)
          .borderRadius(4)
          .animation({ duration: AppMotion.DURATION_PROGRESS_TWEEN, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(7)
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 12, bottom: 12 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private historyRow(mark: string, title: string, meta: string, badge: string) {
    Row({ space: 11 }) {
      HtmlFileMark({ label: mark, tone: 'neutral' })
      Column({ space: 3 }) {
        Text(title)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .maxLines(1)
          .width('100%')
        Text(meta)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      HtmlBadge({ label: badge, tone: badge === '完成' ? 'ok' : 'warn' })
    }
    .width('100%')
    .height(62)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private exportJobRow(job: ExportJobResponse) {
    Row({ space: 11 }) {
      HtmlFileMark({ label: job.format === 'SEARCHABLE_PDF' || job.format === 'PDF' ? 'PDF' : '导出', tone: 'neutral' })
      Column({ space: 3 }) {
        Text(job.fileName)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .maxLines(1)
          .width('100%')
        Text(this.exportFormatLabel(job.format) + ' · ' + this.formatSize(job.sizeBytes) + ' · ' + this.exportLifecycleSummary(job))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      if (this.canCancelExport(job)) {
        Column() {
          HtmlCompactActionButton({
            label: '取消',
            danger: true,
            onTap: () => this.cancelExportJob(job.jobId)
          })
        }
        .width(58)
      } else if (this.canDownloadExport(job)) {
        Column({ space: 6 }) {
          HtmlCompactActionButton({
            label: this.downloadingJobId === job.jobId ? '下载中' : '下载',
            enabledState: this.downloadingJobId.length === 0,
            onTap: () => this.downloadExportJob(job)
          })
          HtmlCompactActionButton({
            label: this.openingJobId === job.jobId ? '打开中' : '打开',
            primary: false,
            enabledState: this.downloadedJobId === job.jobId && this.openingJobId.length === 0,
            onTap: () => this.openDownloadedExport(job)
          })
        }
        .width(74)
      } else {
        HtmlBadge({ label: this.exportStatusLabel(job.status), tone: job.status === 'SUCCESS' ? 'ok' : (job.status === 'CANCELED' ? 'neutral' : 'warn') })
      }
    }
    .width('100%')
    .height(132)
    .alignItems(VerticalAlign.Center)
  }

  private exportStatusLabel(status: string): string {
    if (status === 'SUCCESS') {
      return '完成';
    }
    if (status === 'CANCELED') {
      return '已取消';
    }
    if (status === 'FAILED') {
      return '失败';
    }
    return '处理中';
  }

  private exportFormatLabel(format: ExportFormatType): string {
    if (format === 'SEARCHABLE_PDF') {
      return '可搜索 PDF';
    }
    if (format === 'MARKDOWN') {
      return 'Markdown';
    }
    return format;
  }

  private shortChecksum(checksum: string): string {
    if (checksum.length < 12) {
      return checksum;
    }
    return checksum.substring(0, 12);
  }

  private formatSize(sizeBytes: number): string {
    if (sizeBytes <= 0) {
      return '0 字节';
    }
    if (sizeBytes < 1024) {
      return sizeBytes.toString() + ' 字节';
    }
    const kb = sizeBytes / 1024;
    return kb.toFixed(kb >= 10 ? 0 : 1) + ' KB';
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({ title: '导出中心', subtitle: '格式、进度与历史', actionLabel: '↻', onAction: () => this.loadExportJobs() })

          Column({ space: 10 }) {
            HtmlSectionHead({ title: '选择导出格式', meta: this.recordIdsText.trim().length > 0 ? '当前记录已选择' : '等待选择记录' })
            Row({ space: 10 }) {
              this.formatCard('TXT', 'TXT', '纯文本')
              this.formatCard('Markdown', 'MARKDOWN', '知识库友好')
            }
            .width('100%')
            Row({ space: 10 }) {
              this.formatCard('PDF', 'PDF', '版式文件')
              this.formatCard('可搜索 PDF', 'SEARCHABLE_PDF', '文本层 PDF')
            }
            .width('100%')
            Row({ space: 10 }) {
              this.formatCard('JSON', 'JSON', '结构化字段')
              Column()
                .layoutWeight(1)
            }
            .width('100%')
            TextInput({ placeholder: '记录编号，例如 1,2,3', text: this.recordIdsText })
              .width('100%')
              .height(AppTheme.INPUT_HEIGHT)
              .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
              .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
              .borderRadius(AppTheme.RADIUS_CONTROL)
              .onChange((value: string) => this.recordIdsText = value)
            TextInput({ placeholder: '安全文件名，例如 course-notes.json', text: this.fileName })
              .width('100%')
              .height(AppTheme.INPUT_HEIGHT)
              .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
              .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
              .borderRadius(AppTheme.RADIUS_CONTROL)
              .onChange((value: string) => this.fileName = value)
            Text('文件名会由服务安全处理；页面不会展示下载路径、存储标识或导出全文。')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
              .lineHeight(AppTheme.LINE_CAPTION)
              .width('100%')
            TextActionButton({
              label: this.loading ? '导出中...' : '开始导出',
              primary: true,
              enabledState: !this.loading && this.recordIdsText.trim().length > 0,
              onTap: () => this.createExport()
            })
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_PANEL)
          .opacity(this.formatEntered ? 1 : 0)
          .translate({ y: this.formatEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          Column({ space: 10 }) {
            HtmlSectionHead({ title: '导出进度', meta: this.exportProgress().toString() + '%' })
            this.progressBlock()
          }
          .width('100%')
          .opacity(this.taskEntered ? 1 : 0)
          .translate({ y: this.taskEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          Column({ space: 10 }) {
            HtmlSectionHead({ title: '导出队列与历史', meta: this.exportHistoryMeta })
            List({ space: 0 }) {
              if (this.exportJobs.length === 0) {
                ListItem() {
                  Column({ space: 6 }) {
                    Text(this.exportHistoryMeta)
                      .fontSize(AppTheme.FONT_META)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(AppTheme.COLOR_TEXT)
                      .width('100%')
                    Text('从历史记录创建导出后，队列会显示在这里。')
                      .fontSize(AppTheme.FONT_CAPTION)
                      .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
                      .width('100%')
                  }
                  .width('100%')
                  .height(92)
                  .justifyContent(FlexAlign.Center)
                }
              } else {
                ForEach(this.exportJobs.slice(0, 5), (job: ExportJobResponse) => {
                  ListItem() {
                    this.exportJobRow(job)
                  }
                }, (job: ExportJobResponse) => job.jobId)
              }
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
            .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
            .borderRadius(AppTheme.RADIUS_PANEL)
            .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
          }
          .width('100%')
          .opacity(this.recentEntered ? 1 : 0)
          .translate({ y: this.recentEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          if (this.downloadStatusMessage.length > 0) {
            StatusBanner({ label: '下载', title: '导出文件已保存', message: this.downloadStatusMessage, tone: 'success' })
          }

          if (this.openPreviewMessage.length > 0) {
            StatusBanner({ label: '打开', title: '导出打开已验证', message: this.openPreviewMessage, tone: 'success' })
          }

          if (this.recentJob !== undefined) {
            Column({ space: 8 }) {
              HtmlSectionHead({ title: '最近导出', meta: '仅显示脱敏信息' })
              Row({ space: 8 }) {
                HtmlBadge({ label: this.exportStatusLabel(this.recentJob.status), tone: this.recentJob.status === 'SUCCESS' ? 'ok' : 'neutral' })
                HtmlBadge({ label: this.exportFormatLabel(this.recentJob.format), tone: 'neutral' })
                HtmlBadge({ label: this.formatSize(this.recentJob.sizeBytes), tone: 'neutral' })
              }
              Text(this.recentJob.fileName)
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.COLOR_TEXT)
                .width('100%')
              if (this.recentJob.checksumSha256.length > 0) {
                Text('校验 ' + this.shortChecksum(this.recentJob.checksumSha256) + ' · ' + this.exportLifecycleSummary(this.recentJob))
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
                  .maxLines(1)
                  .width('100%')
              } else {
                Text(this.exportLifecycleSummary(this.recentJob))
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
                  .maxLines(1)
                  .width('100%')
              }
              if (this.recentJob.degraded) {
                StatusBanner({ label: '降级', title: '已降级导出', message: this.recentJob.downgradeReason ?? '可搜索 PDF 已降级为普通 PDF。', tone: 'warning' })
              }
            }
            .width('100%')
            .padding(AppTheme.CARD_PADDING)
            .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
            .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
            .borderRadius(AppTheme.RADIUS_PANEL)
          }

          HtmlToast({ message: this.noticeMessage, visible: this.noticeVisible })
          if (this.errorMessage.length > 0) {
            StatusBanner({ label: '错误', title: '导出不可用', message: this.errorMessage, tone: 'danger' })
          }

          TextActionButton({ label: '返回历史', onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.HISTORY) })
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
