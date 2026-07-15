import { common } from '@kit.AbilityKit';
import { ApiError } from '../common/network/ApiTypes';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { TokenStorage } from '../common/storage/TokenStorage';
import { AppMotion } from '../common/theme/AppMotion';
import { AppTheme } from '../common/theme/AppTheme';
import { AppBottomNav } from '../components/AppBottomNav';
import { HtmlAppBar, HtmlSectionHead, HtmlStatusBar, StatusBanner, StatusTone, TextActionButton } from '../components/BrandComponents';
import { DeviceImageSelection } from '../features/ocr/DeviceOcrModels';
import { DeviceOcrService } from '../features/ocr/DeviceOcrService';
import { OcrFlowState } from '../features/ocr/OcrFlowState';
import { OcrResult, OcrSourceType } from '../features/ocr/OcrModels';

type OcrProcessingStage = 'running' | 'slowNetwork' | 'success' | 'failed' | 'cancelled' | 'missingImage';

/**
 * OcrProcessingPage 承接 V1.0 单图 OCR 的真实处理状态，属于 C2 输入流。
 * 维护说明：本页只消费 OcrFlowState 中的短期图片引用，完成后写入内存结果；取消、失败和无图状态都不会伪造 OCR 文本或历史记录。
 */
@Entry
@Component
struct OcrProcessingPage {
  @State stage: OcrProcessingStage = 'running';
  @State sourceType: OcrSourceType = 'camera';
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State isProcessing: boolean = false;
  @State hasSelectedImage: boolean = false;
  @State private scanBeamOffset: number = -42;
  private operationToken: number = 0;
  private pageActive: boolean = false;
  private slowTimerId: number = -1;
  private resultTimerId: number = -1;
  private scanTimerId: number = -1;
  private scanKickTimerId: number = -1;
  private readonly slowNetworkThresholdMs: number = 2200;
  private readonly minimumRunningStageMs: number = 1800;
  private readonly successTransitionMs: number = 420;
  private readonly scanBeamTravel: number = 276;

  aboutToAppear(): void {
    this.pageActive = true;
    this.sourceType = OcrFlowState.getSourceType();
    this.startRecognition();
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.operationToken++;
    this.clearTimers();
  }

  /**
   * 启动真实 OCR 识别。
   * 安全边界：只读取当前内存中的用户授权图片 URI；没有图片时停留在无图态，不生成 Mock 结果。
   */
  private async startRecognition(): Promise<void> {
    const selection: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    this.hasSelectedImage = selection !== undefined && selection.uri.length > 0;
    this.sourceType = OcrFlowState.getSourceType();
    this.errorMessage = '';
    this.noticeMessage = '';

    if (!selection || selection.uri.length === 0) {
      this.operationToken++;
      this.clearTimers();
      this.isProcessing = false;
      this.stage = 'missingImage';
      this.errorMessage = '当前没有可识别图片，请返回拍照或相册入口重新选择。';
      this.noticeMessage = '处理页不会使用示例图片或旧结果补位。';
      return;
    }

    const token = this.nextOperationToken();
    this.isProcessing = true;
    this.stage = 'running';
    this.noticeMessage = '正在调用端侧真实 OCR；端侧能力不可用时会按既有服务进入后端 fallback。';
    this.armSlowNetworkTimer(token);
    this.startScanMotion();
    const runningVisibleSince = Date.now();

    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result: OcrResult = await DeviceOcrService.recognizeSelection(context, selection);
      if (!this.isCurrentRunningOperation(token)) {
        return;
      }
      if (!(await this.holdMinimumRunningStage(token, runningVisibleSince))) {
        return;
      }
      this.clearSlowTimer();
      this.clearScanTimer();
      OcrFlowState.setResult(result);
      this.isProcessing = false;
      this.stage = 'success';
      this.noticeMessage = '真实 OCR 结果已写入当前流程，正在进入结果页。';
      this.armResultNavigation(token);
    } catch (error) {
      if (!this.isCurrentRunningOperation(token)) {
        return;
      }
      if (!(await this.holdMinimumRunningStage(token, runningVisibleSince))) {
        return;
      }
      this.clearSlowTimer();
      this.clearScanTimer();
      this.isProcessing = false;
      this.stage = 'failed';
      this.errorMessage = this.toUserMessage(error as Error, token, 'OCR 处理失败，请检查图片质量或服务可用性后重试。');
      this.noticeMessage = '识别失败时不会保存历史，也不会回退到临时示例文本。';
    }
  }

  /**
   * 取消当前 OCR 操作。
   * 说明：底层 CoreVisionKit 或 HTTP Promise 可能无法立即中止；operation token 会阻止过期完成回写结果或自动跳页。
   */
  private cancelRecognition(): void {
    if (!this.isProcessing && this.stage !== 'running' && this.stage !== 'slowNetwork') {
      return;
    }
    this.operationToken++;
    this.clearTimers();
    this.isProcessing = false;
    this.stage = 'cancelled';
    this.errorMessage = '';
    this.noticeMessage = '已取消本次识别。底层调用如稍后返回，也会因本轮 token 失效而被丢弃。';
  }

  private retryRecognition(): void {
    if (this.isProcessing) {
      return;
    }
    this.startRecognition().then(() => {
    });
  }

  private handleBack(): void {
    if (this.isProcessing) {
      this.cancelRecognition();
    }
    AppNavigator.back(this.getUIContext(), AppRoutes.HOME);
  }

  private openCapture(): void {
    this.invalidateCurrentOperation();
    AppNavigator.push(this.getUIContext(), AppRoutes.CAPTURE);
  }

  private openAlbum(): void {
    this.invalidateCurrentOperation();
    AppNavigator.push(this.getUIContext(), AppRoutes.ALBUM);
  }

  private openCrop(): void {
    this.invalidateCurrentOperation();
    AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_CROP);
  }

  private returnHome(): void {
    this.invalidateCurrentOperation();
    OcrFlowState.clear();
    AppNavigator.replaceRoot(this.getUIContext(), AppRoutes.HOME);
  }

  private openResultIfReady(): void {
    if (this.stage !== 'success' || OcrFlowState.getResult() === undefined) {
      return;
    }
    this.clearResultTimer();
    AppNavigator.push(this.getUIContext(), AppRoutes.OCR_RESULT);
  }

  private nextOperationToken(): number {
    this.operationToken++;
    this.clearTimers();
    return this.operationToken;
  }

  private invalidateCurrentOperation(): void {
    this.operationToken++;
    this.clearTimers();
    this.isProcessing = false;
  }

  private isCurrentRunningOperation(token: number): boolean {
    return this.pageActive && this.operationToken === token && this.isProcessing &&
      (this.stage === 'running' || this.stage === 'slowNetwork');
  }

  private isCurrentPageToken(token: number): boolean {
    return this.pageActive && this.operationToken === token;
  }

  /**
   * 慢网态只表达当前等待时间过长，不推断真实网络层原因。
   */
  private armSlowNetworkTimer(token: number): void {
    this.clearSlowTimer();
    this.slowTimerId = setTimeout(() => {
      if (this.isCurrentRunningOperation(token) && this.stage === 'running') {
        this.stage = 'slowNetwork';
        this.noticeMessage = '识别耗时较长，可能正在等待后端 OCR fallback；可继续等待或取消后换用更稳定网络。';
      }
    }, this.slowNetworkThresholdMs);
  }

  private armResultNavigation(token: number): void {
    this.clearResultTimer();
    this.resultTimerId = setTimeout(() => {
      if (this.isCurrentPageToken(token) && this.stage === 'success') {
        this.openResultIfReady();
      }
    }, this.successTransitionMs);
  }

  /**
   * 保证真实 OCR 返回过快时，用户仍能看到 canonical 的处理中扫描过渡态。
   * 该等待只延迟状态切换，不生成 OCR 结果，也不会覆盖取消 token。
   */
  private async holdMinimumRunningStage(token: number, runningVisibleSince: number): Promise<boolean> {
    const remainingMs = this.minimumRunningStageMs - (Date.now() - runningVisibleSince);
    if (remainingMs > 0) {
      await new Promise<void>((resolve: () => void) => {
        setTimeout(resolve, remainingMs);
      });
    }
    return this.isCurrentRunningOperation(token);
  }

  private clearTimers(): void {
    this.clearSlowTimer();
    this.clearResultTimer();
    this.clearScanTimer();
  }

  private clearSlowTimer(): void {
    if (this.slowTimerId >= 0) {
      clearTimeout(this.slowTimerId);
      this.slowTimerId = -1;
    }
  }

  private clearResultTimer(): void {
    if (this.resultTimerId >= 0) {
      clearTimeout(this.resultTimerId);
      this.resultTimerId = -1;
    }
  }

  /**
   * 启动过渡页扫描光束动效。
   * 说明：该动效只表达当前正在识别，不改变真实 OCR 调用和取消 token 语义。
   */
  private startScanMotion(): void {
    this.clearScanTimer();
    this.scanBeamOffset = -42;
    this.scheduleScanSweep(40);
    this.scanTimerId = setInterval(() => {
      if (!this.pageActive || (this.stage !== 'running' && this.stage !== 'slowNetwork')) {
        this.clearScanTimer();
        return;
      }
      this.scanBeamOffset = -42;
      this.scheduleScanSweep(40);
    }, 1640);
  }

  private scheduleScanSweep(delayMs: number): void {
    this.clearScanKickTimer();
    this.scanKickTimerId = setTimeout(() => {
      this.scanKickTimerId = -1;
      if (this.pageActive && (this.stage === 'running' || this.stage === 'slowNetwork')) {
        this.scanBeamOffset = this.scanBeamTravel;
      }
    }, delayMs);
  }

  private clearScanTimer(): void {
    if (this.scanTimerId >= 0) {
      clearInterval(this.scanTimerId);
      this.scanTimerId = -1;
    }
    this.clearScanKickTimer();
  }

  private clearScanKickTimer(): void {
    if (this.scanKickTimerId >= 0) {
      clearTimeout(this.scanKickTimerId);
      this.scanKickTimerId = -1;
    }
  }

  private toUserMessage(error: Error, token: number, fallback: string): string {
    if (error instanceof ApiError && (error.statusCode === 401 || error.code === 'UNAUTHORIZED')) {
      TokenStorage.clearTokens().catch(() => {
      });
      setTimeout(() => {
        if (this.isCurrentPageToken(token) && this.stage === 'failed') {
          AppNavigator.replace(this.getUIContext(), AppRoutes.LOGIN);
        }
      }, 800);
      return '登录已失效，请重新登录后再识别。';
    }
    if (error.message && error.message.length > 0 && error.message.length < 96) {
      return error.message;
    }
    return fallback;
  }

  private stageTitle(): string {
    if (this.stage === 'slowNetwork') {
      return '网络缓慢：识别进度放缓';
    }
    if (this.stage === 'success') {
      return '识别完成';
    }
    if (this.stage === 'failed') {
      return 'OCR 处理失败';
    }
    if (this.stage === 'cancelled') {
      return '已取消本次识别';
    }
    if (this.stage === 'missingImage') {
      return '未选择图片';
    }
    return '识别处理中';
  }

  private stageSubtitle(): string {
    if (this.stage === 'success') {
      return '结果已就绪 · 即将跳转';
    }
    if (this.stage === 'failed') {
      return '可重试 · 不保存失败结果';
    }
    if (this.stage === 'cancelled') {
      return '已阻止结果回写';
    }
    if (this.stage === 'missingImage') {
      return '请返回输入入口';
    }
    return 'Harmony OCR V2 处理中';
  }

  private stageTone(): StatusTone {
    if (this.stage === 'success') {
      return 'success';
    }
    if (this.stage === 'failed') {
      return 'danger';
    }
    if (this.stage === 'cancelled' || this.stage === 'missingImage') {
      return 'neutral';
    }
    return 'warning';
  }

  private stageLabel(): string {
    if (this.stage === 'slowNetwork') {
      return '网络缓慢';
    }
    if (this.stage === 'success') {
      return '成功过渡';
    }
    if (this.stage === 'failed') {
      return '识别失败';
    }
    if (this.stage === 'cancelled') {
      return '已取消';
    }
    if (this.stage === 'missingImage') {
      return '无图片';
    }
    return '识别';
  }

  private stageMessage(): string {
    if (this.errorMessage.length > 0) {
      return this.errorMessage;
    }
    if (this.noticeMessage.length > 0) {
      return this.noticeMessage;
    }
    return '正在处理当前选择的图片。';
  }

  private progressWidth(): string {
    return this.stage === 'slowNetwork' ? '28%' : '64%';
  }

  private recognitionStepText(): string {
    return this.stage === 'slowNetwork' ? '网络较慢，正在等待服务器...' : '正在识别文字与表格...';
  }

  @Builder
  private stepIcon(done: boolean, active: boolean) {
    if (done) {
      Text('✓')
        .width(20)
        .height(20)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_SUCCESS)
        .textAlign(TextAlign.Center)
        .backgroundColor(AppTheme.COLOR_SUCCESS_BG)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(10)
    } else {
      Column()
        .width(active ? 12 : 9)
        .height(active ? 12 : 9)
        .backgroundColor(active ? AppTheme.COLOR_BRAND : AppTheme.COLOR_LINE_STRONG)
        .borderRadius(6)
    }
  }

  @Builder
  private stepRow(done: boolean, active: boolean, label: string) {
    Row({ space: 9 }) {
      this.stepIcon(done, active)
      Text(label)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(active ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(active ? AppTheme.COLOR_TEXT : AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(AppTheme.LINE_META)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private scanLine(widthValue: string, brand: boolean = false) {
    Column()
      .width(widthValue)
      .height(9)
      .backgroundColor(brand ? AppTheme.COLOR_PREVIEW_ACCENT_LINE : AppTheme.COLOR_PREVIEW_TEXT_LINE)
      .borderRadius(6)
  }

  @Builder
  private scanTableRow(first: boolean) {
    Row({ space: 0 }) {
      Column()
        .width('38%')
        .height(28)
        .backgroundColor(AppTheme.COLOR_PREVIEW_TABLE_BG)
        .borderWidth({ top: first ? 0 : AppTheme.HAIRLINE, right: AppTheme.HAIRLINE, bottom: 0, left: 0 })
        .borderColor(AppTheme.COLOR_LINE_SOFT)
      Column()
        .layoutWeight(1)
        .height(28)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .borderWidth({ top: first ? 0 : AppTheme.HAIRLINE, right: 0, bottom: 0, left: 0 })
        .borderColor(AppTheme.COLOR_LINE_SOFT)
    }
    .width('100%')
  }

  @Builder
  private scanTable() {
    Column({ space: 0 }) {
      this.scanTableRow(true)
      this.scanTableRow(false)
      this.scanTableRow(false)
    }
    .width('100%')
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(8)
    .clip(true)
  }

  @Builder
  private scanBeam() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height(42)
        .backgroundColor(AppTheme.COLOR_BRAND_SOFT)
        .opacity(this.stage === 'slowNetwork' ? 0.38 : 0.68)
      Column()
        .width('100%')
        .height(2)
        .backgroundColor(AppTheme.COLOR_SCAN_LINE)
        .opacity(this.stage === 'slowNetwork' ? 0.34 : 0.58)
        .translate({ y: 20 })
    }
    .width('100%')
    .height(42)
    .translate({ y: this.scanBeamOffset })
    .animation({ duration: 1500, curve: Curve.EaseInOut })
  }

  @Builder
  private processingPreview() {
    Column() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)

        this.scanBeam()

        Column({ space: 10 }) {
          this.scanLine('58%')
          this.scanLine('78%')
          this.scanLine('94%')
          this.scanLine('72%', true)
          Blank().height(6)
          this.scanTable()
          Blank().height(6)
          this.scanLine('78%')
          this.scanLine('58%')
        }
        .width('100%')
        .height('100%')
        .padding({ left: 16, right: 16, top: 24, bottom: 18 })
      }
      .width('100%')
      .height(272)
      .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
      .borderRadius(AppTheme.RADIUS_DOCUMENT)
      .clip(true)
    }
    .width('100%')
    .height(300)
    .padding(14)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private processingSteps() {
    Column({ space: 14 }) {
      Stack({ alignContent: Alignment.Start }) {
        Column()
          .width('100%')
          .height(8)
          .backgroundColor(AppTheme.COLOR_PAGE_DEEP)
          .borderRadius(6)
        Column()
          .width(this.progressWidth())
          .height(8)
          .backgroundColor(AppTheme.COLOR_BRAND)
          .borderRadius(6)
          .animation({ duration: AppMotion.DURATION_PROGRESS_TWEEN, curve: Curve.EaseOut })
      }
      .width('100%')
      .height(8)

      Column({ space: 10 }) {
        this.stepRow(true, false, '预处理与透视校正')
        this.stepRow(this.stage !== 'slowNetwork', this.stage === 'slowNetwork', '文字检测与版面分析')
        this.stepRow(false, this.stage !== 'slowNetwork', this.recognitionStepText())
        this.stepRow(false, false, '低置信字段标注')
      }
      .width('100%')

      if (this.stage === 'slowNetwork') {
        Text('网络较慢可能延长识别时间，可继续等待或取消后改用更稳定的网络。')
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private fullWidthAction(label: string, primary: boolean, enabled: boolean, onTap: () => void) {
    TextActionButton({
      label: label,
      primary: primary,
      enabledState: enabled,
      onTap: onTap
    })
  }

  @Builder
  private pairedActions(
    leftLabel: string,
    leftPrimary: boolean,
    leftEnabled: boolean,
    leftTap: () => void,
    rightLabel: string,
    rightPrimary: boolean,
    rightEnabled: boolean,
    rightTap: () => void
  ) {
    Row({ space: 10 }) {
      Column() {
        this.fullWidthAction(leftLabel, leftPrimary, leftEnabled, leftTap)
      }
      .layoutWeight(1)

      Column() {
        this.fullWidthAction(rightLabel, rightPrimary, rightEnabled, rightTap)
      }
      .layoutWeight(1)
    }
    .width('100%')
  }

  @Builder
  private terminalStatePanel() {
    Column({ space: 13 }) {
      HtmlSectionHead({ title: this.stageTitle(), meta: this.stageLabel() })
      StatusBanner({
        label: this.stageLabel(),
        title: this.stageTitle(),
        message: this.stageMessage(),
        tone: this.stageTone()
      })

      if (this.stage === 'success') {
        this.fullWidthAction('查看结果', true, OcrFlowState.getResult() !== undefined, () => this.openResultIfReady())
      } else if (this.stage === 'failed') {
        this.pairedActions('重试识别', true, this.hasSelectedImage, () => this.retryRecognition(), '重新裁切', false, this.hasSelectedImage, () => this.openCrop())
      } else if (this.stage === 'missingImage') {
        this.pairedActions('返回拍照', true, true, () => this.openCapture(), '打开相册', false, true, () => this.openAlbum())
      } else {
        this.pairedActions('重新识别', true, this.hasSelectedImage, () => this.retryRecognition(), '返回首页', false, true, () => this.returnHome())
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({
            title: '正在识别',
            subtitle: this.stageSubtitle(),
            showBackButton: true,
            actionLabel: '···',
            onBack: () => this.handleBack()
          })

          if (this.stage === 'running' || this.stage === 'slowNetwork') {
            this.processingPreview()
            this.processingSteps()
            this.fullWidthAction('取消识别', false, true, () => this.cancelRecognition())
          } else {
            StatusBanner({
              label: this.stageLabel(),
              title: this.stageTitle(),
              message: this.stageMessage(),
              tone: this.stageTone()
            })
            this.terminalStatePanel()
          }
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

      AppBottomNav({ activeTab: 'home' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
