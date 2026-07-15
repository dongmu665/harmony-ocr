import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { HtmlAppBar, HtmlBadge, HtmlSectionHead, OcrScanBadge, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { DeviceImageSelection } from '../features/ocr/DeviceOcrModels';
import { OcrFlowState } from '../features/ocr/OcrFlowState';
import { OcrSourceType } from '../features/ocr/OcrModels';

/**
 * ImagePreviewPage 负责展示本轮用户授权图片的真实预览，并把确认动作交给 OCR 处理页。
 * 维护边界：本页不执行 OCR、不写入结果文本，也不使用 Mock 图片伪装用户预览。
 */
@Entry
@Component
struct ImagePreviewPage {
  @State sourceType: OcrSourceType = 'camera';
  @State selectedImageUri: string = '';
  @State cropConfirmed: boolean = false;
  @State errorMessage: string = '';
  @State noticeMessage: string = '';

  aboutToAppear(): void {
    this.sourceType = OcrFlowState.getSourceType();
    const selection: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    this.selectedImageUri = selection ? selection.uri : '';
    this.cropConfirmed = selection ? selection.uploadSource === 'generated_crop_cache' : false;
    this.errorMessage = '';
    this.noticeMessage = this.selectedImageUri.length > 0
      ? (this.cropConfirmed ? '裁剪输出已就绪，确认识别后进入处理页。' : '图片已加载，可先裁剪，也可确认进入识别处理页。')
      : '未检测到导入图片，请返回相册或相机重新选择。';
  }

  /**
   * 返回上一页或首页兜底。
   * 说明：只做路由返回，不清理本轮图片，避免用户误触返回后丢失已授权的图片引用。
   */
  private goBack(): void {
    AppNavigator.back(this.getUIContext(), AppRoutes.HOME);
  }

  /**
   * 进入裁剪页调整取景范围。
   * 说明：裁剪页会再次校验图片是否存在，本页只负责入口状态和视觉提示。
   */
  private goCrop(): void {
    if (!this.hasPreviewContent()) {
      this.errorMessage = '未找到可裁剪的图片，请先重新选择。';
      this.noticeMessage = '没有真实图片时不会进入裁剪或识别流程。';
      return;
    }
    AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_CROP);
  }

  /**
   * 确认当前真实图片并进入 OCR 处理页。
   * 安全边界：这里不调用 OCR 服务、不生成结果文本，后续真实识别由 OcrProcessingPage 所属流程统一处理。
   */
  private confirmRecognition(): void {
    const selection: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    if (!selection || selection.uri.length === 0) {
      this.errorMessage = '未找到可识别的图片，请返回拍照或相册入口重新选择。';
      this.noticeMessage = '识别流程不会使用临时示例图片或伪造结果。';
      return;
    }
    this.selectedImageUri = selection.uri;
    this.cropConfirmed = selection.uploadSource === 'generated_crop_cache';
    this.errorMessage = '';
    this.noticeMessage = '已确认当前图片，正在进入识别处理页。';
    AppNavigator.push(this.getUIContext(), AppRoutes.OCR_PROCESSING);
  }

  /**
   * 重新打开来源入口。
   * 说明：主动重新选择会清空旧图片，避免用户取消新选择后仍误识别上一张图片。
   */
  private reselectImage(): void {
    OcrFlowState.start(this.sourceType);
    AppNavigator.push(this.getUIContext(), this.sourceType === 'camera' ? AppRoutes.CAPTURE : AppRoutes.ALBUM);
  }

  private getSourceLabel(): string {
    return this.sourceType === 'album' ? '相册导入' : '拍照导入';
  }

  private getReselectLabel(): string {
    return this.sourceType === 'album' ? '重新选择' : '重新拍摄';
  }

  private hasPreviewContent(): boolean {
    return this.selectedImageUri.length > 0;
  }

  private previewStatusLabel(): string {
    if (!this.hasPreviewContent()) {
      return '无图片';
    }
    return this.cropConfirmed ? '可识别' : '可裁剪';
  }

  private previewStatusTitle(): string {
    if (!this.hasPreviewContent()) {
      return '没有可预览的图片';
    }
    return this.cropConfirmed ? '裁切已确认，可直接识别' : '图片已加载，可进入裁切';
  }

  private cropMetaValue(): string {
    return this.cropConfirmed ? '已确认' : '待确认';
  }

  private stageMetaValue(): string {
    if (!this.hasPreviewContent()) {
      return '待选择';
    }
    return this.cropConfirmed ? 'readyOcr' : 'readyCrop';
  }

  private statusTone(): 'success' | 'neutral' {
    return this.hasPreviewContent() ? 'success' : 'neutral';
  }

  private metaValueColor(tone: string): string {
    if (tone === 'success') {
      return AppTheme.COLOR_SUCCESS;
    }
    if (tone === 'warning') {
      return AppTheme.COLOR_WARNING;
    }
    return AppTheme.COLOR_TEXT;
  }

  @Builder
  private previewMetaItem(label: string, value: string, tone: string = 'default') {
    Column({ space: 4 }) {
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .lineHeight(AppTheme.LINE_CAPTION)
        .width('100%')

      Text(value)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.metaValueColor(tone))
        .lineHeight(AppTheme.LINE_META)
        .maxLines(1)
        .width('100%')
    }
    .layoutWeight(1)
    .padding({ left: 12, right: 12, top: 10, bottom: 10 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }

  @Builder
  private previewMetaGrid() {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        this.previewMetaItem('来源', this.getSourceLabel())
        this.previewMetaItem('图片', '用户授权')
      }
      .width('100%')

      Row({ space: 8 }) {
        this.previewMetaItem('裁切', this.cropMetaValue(), this.cropConfirmed ? 'success' : 'warning')
        this.previewMetaItem('状态', this.previewStatusLabel(), this.hasPreviewContent() ? 'success' : 'warning')
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private previewStage() {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: '图片预览', meta: this.stageMetaValue() })

      Stack({ alignContent: Alignment.Center }) {
        Image(this.selectedImageUri)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Contain)
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)

        Column()
          .width('74%')
          .height(2)
          .backgroundColor(AppTheme.COLOR_SCAN_LINE)
          .opacity(0.76)
      }
      .width('100%')
      .height(300)
      .padding(14)
      .clip(true)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
      .borderRadius(AppTheme.RADIUS_DOCUMENT)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private noImageState() {
    Column({ space: 14 }) {
      OcrScanBadge({ label: '无图片' })
        .borderRadius(AppTheme.RADIUS_PANEL)
        .clip(true)

      Text('没有可预览的图片')
        .fontSize(AppTheme.FONT_CARD_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(AppTheme.LINE_SECTION_TITLE)

      HtmlBadge({ label: '无图片', tone: 'warn' })

      Text('未检测到导入的图片。请返回相册或相机重新选择 / 拍摄文档后再进入预览。')
        .fontSize(AppTheme.FONT_META)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(AppTheme.LINE_META)
        .textAlign(TextAlign.Center)
        .width('100%')

      TextActionButton({
        label: '返回相册',
        primary: true,
        onTap: () => {
          OcrFlowState.start('album');
          AppNavigator.push(this.getUIContext(), AppRoutes.ALBUM);
        }
      })

      TextActionButton({
        label: '去拍摄',
        onTap: () => {
          OcrFlowState.start('camera');
          AppNavigator.push(this.getUIContext(), AppRoutes.CAPTURE);
        }
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({
            title: '图片预览',
            subtitle: '确认清晰度后进入裁切',
            showBackButton: true,
            actionLabel: '···',
            onBack: () => this.goBack()
          })

          StatusBanner({
            label: this.previewStatusLabel(),
            title: this.previewStatusTitle(),
            message: this.noticeMessage,
            tone: this.statusTone()
          })

          if (this.errorMessage.length > 0) {
            StatusBanner({
              label: '错误',
              title: '图片未确认',
              message: this.errorMessage,
              tone: 'danger'
            })
          }

          if (this.hasPreviewContent()) {
            this.previewStage()
            this.previewMetaGrid()

            TextActionButton({
              label: '确认识别',
              primary: true,
              enabledState: this.hasPreviewContent(),
              onTap: () => this.confirmRecognition()
            })

            TextActionButton({
              label: this.cropConfirmed ? '重新裁切' : '下一步：裁切',
              enabledState: this.hasPreviewContent(),
              onTap: () => this.goCrop()
            })

            TextActionButton({
              label: this.getReselectLabel(),
              enabledState: true,
              onTap: () => this.reselectImage()
            })

            TextActionButton({
              label: '返回',
              enabledState: true,
              onTap: () => this.goBack()
            })
          } else {
            this.noImageState()

            TextActionButton({
              label: '返回',
              enabledState: true,
              onTap: () => this.goBack()
            })
          }
        }
        .width('100%')
        .padding(AppTheme.PAGE_PADDING)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
