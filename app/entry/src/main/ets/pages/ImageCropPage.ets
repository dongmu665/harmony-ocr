import { common } from '@kit.AbilityKit';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { HtmlAppBar, HtmlBadge, HtmlSectionHead, OcrScanBadge, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { DeviceImageSelection } from '../features/ocr/DeviceOcrModels';
import { CropImageSize, CropRect, ImageCropService } from '../features/ocr/ImageCropService';
import { OcrFlowState } from '../features/ocr/OcrFlowState';
import { OcrSourceType } from '../features/ocr/OcrModels';

/**
 * ImageCropPage 负责生成真实矩形裁剪输出，并把后续 OCR 交给处理页统一执行。
 * 维护边界：本页只写入应用 cache 中的裁剪图片，不执行 OCR、不伪造旋转/去噪/增强结果。
 */
@Entry
@Component
struct ImageCropPage {
  @State sourceType: OcrSourceType = 'camera';
  @State selectedImageUri: string = '';
  @State loading: boolean = false;
  @State cropConfirmed: boolean = false;
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State cropRatioPercent: number = 80;
  @State cropXPercent: number = 10;
  @State cropYPercent: number = 10;
  @State cropWidthPercent: number = 80;
  @State cropHeightPercent: number = 80;
  @State cropSurfaceWidthPx: number = 320;
  @State cropSurfaceHeightPx: number = AppTheme.OCR_FRAME_HEIGHT;
  @State sourceImageWidth: number = 0;
  @State sourceImageHeight: number = 0;
  private readonly minCropPercent: number = 8;
  private readonly minCropPixelSize: number = 44;
  private readonly handleSize: number = 22;
  private readonly edgeHandleThickness: number = 12;
  private dragStartXPercent: number = 10;
  private dragStartYPercent: number = 10;
  private resizeStartXPercent: number = 10;
  private resizeStartYPercent: number = 10;
  private resizeStartWidthPercent: number = 80;
  private resizeStartHeightPercent: number = 80;

  aboutToAppear(): void {
    this.sourceType = OcrFlowState.getSourceType();
    const selection: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    this.selectedImageUri = selection ? selection.uri : '';
    this.cropConfirmed = selection ? selection.uploadSource === 'generated_crop_cache' : false;
    this.errorMessage = '';
    this.noticeMessage = this.selectedImageUri.length > 0
      ? '拖动矩形位置，拖拽边角或边线调整长宽；确认后会生成真实裁剪输出。'
      : '当前没有可裁剪图片，不会生成裁剪文件或识别结果。';
    this.loadSourceImageSize();
  }

  /**
   * 生成真实裁剪图片并进入 OCR 处理页。
   * 安全边界：这里不调用 OCR 服务、不写入识别文本，避免与处理页的真实 OCR 编排重复。
   */
  private async cropAndProceed(): Promise<void> {
    if (this.loading) {
      return;
    }
    const selection: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    if (!selection || selection.uri.length === 0) {
      this.errorMessage = '未找到可裁剪的图片，请返回重新选择。';
      this.noticeMessage = '没有生成裁剪输出，也不会进入识别处理页。';
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '正在生成真实裁剪输出。';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const croppedSelection: DeviceImageSelection = await ImageCropService.createRectCrop(context, selection, this.currentCropRect());
      OcrFlowState.replaceSelectedImage(croppedSelection);
      this.selectedImageUri = croppedSelection.uri;
      this.cropConfirmed = true;
      this.noticeMessage = '裁剪输出已生成，正在进入识别处理页。';
      AppNavigator.push(this.getUIContext(), AppRoutes.OCR_PROCESSING);
    } catch (error) {
      this.errorMessage = this.toUserMessage(error as Error, '裁剪输出生成失败，请重新选择图片后再试。');
      this.noticeMessage = '失败时不会保存历史，也不会使用临时示例。';
    } finally {
      this.loading = false;
    }
  }

  /**
   * 返回预览页。
   * 说明：只切换页面，不清理已选图片，便于用户重新确认裁剪目标。
   */
  private backToPreview(): void {
    if (this.loading) {
      return;
    }
    AppNavigator.back(this.getUIContext(), AppRoutes.IMAGE_PREVIEW);
  }

  private setCropRatioPercent(value: number): void {
    if (this.loading || !this.hasCropImage()) {
      return;
    }
    this.cropRatioPercent = value;
    this.cropWidthPercent = value;
    this.cropHeightPercent = value;
    this.cropXPercent = Math.floor((100 - value) / 2);
    this.cropYPercent = Math.floor((100 - value) / 2);
    this.cropConfirmed = false;
    this.noticeMessage = `已选择中心 ${value}% 矩形快捷范围；仍可继续拖动边角自由调整长宽。`;
  }

  /**
   * 将裁剪框恢复为默认 80% 中心矩形。
   * 说明：只复位界面百分比，不读取或修改图片文件。
   */
  private resetCropFrame(): void {
    this.setCropRatioPercent(80);
    if (this.hasCropImage()) {
      this.noticeMessage = '已重置为中心 80% 矩形，仍可继续拖动边角或边线。';
    }
  }

  /**
   * 读取当前图片尺寸，用于把裁剪层限制在真实可见图片区域内。
   * 失败时保留外层容器作为兜底，不输出 URI 或图片路径。
   */
  private async loadSourceImageSize(): Promise<void> {
    const selection: DeviceImageSelection | undefined = OcrFlowState.getSelectedImage();
    if (!selection || selection.uri.length === 0) {
      this.sourceImageWidth = 0;
      this.sourceImageHeight = 0;
      return;
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const size: CropImageSize = await ImageCropService.getImageSize(context, selection);
      this.sourceImageWidth = Math.max(1, size.width);
      this.sourceImageHeight = Math.max(1, size.height);
    } catch (_) {
      this.sourceImageWidth = 0;
      this.sourceImageHeight = 0;
    }
  }

  /**
   * 记录裁剪画布实际像素尺寸，后续手势位移会按真实画布换算成百分比。
   */
  private updateCropSurfaceSize(width: number | string, height: number | string): void {
    const nextWidth = this.toPositiveNumber(width, this.cropSurfaceWidthPx);
    const nextHeight = this.toPositiveNumber(height, this.cropSurfaceHeightPx);
    if (nextWidth > 0) {
      this.cropSurfaceWidthPx = nextWidth;
    }
    if (nextHeight > 0) {
      this.cropSurfaceHeightPx = nextHeight;
    }
  }

  /**
   * 按 ImageFit.Contain 规则计算图片在裁剪画布内的实际绘制宽度。
   */
  private imageDrawWidth(): number {
    if (this.sourceImageWidth <= 0 || this.sourceImageHeight <= 0) {
      return this.cropSurfaceWidthPx;
    }
    const imageRatio = this.sourceImageWidth / this.sourceImageHeight;
    const frameRatio = this.cropSurfaceWidthPx / this.cropSurfaceHeightPx;
    return imageRatio >= frameRatio ? this.cropSurfaceWidthPx : this.cropSurfaceHeightPx * imageRatio;
  }

  /**
   * 按 ImageFit.Contain 规则计算图片在裁剪画布内的实际绘制高度。
   */
  private imageDrawHeight(): number {
    if (this.sourceImageWidth <= 0 || this.sourceImageHeight <= 0) {
      return this.cropSurfaceHeightPx;
    }
    const imageRatio = this.sourceImageWidth / this.sourceImageHeight;
    const frameRatio = this.cropSurfaceWidthPx / this.cropSurfaceHeightPx;
    return imageRatio >= frameRatio ? this.cropSurfaceWidthPx / imageRatio : this.cropSurfaceHeightPx;
  }

  /**
   * 计算图片绘制区域左侧留白，确保裁剪框不会跑到 letterbox 区域。
   */
  private imageDrawLeft(): number {
    return Math.max(0, Math.floor((this.cropSurfaceWidthPx - this.imageDrawWidth()) / 2));
  }

  /**
   * 计算图片绘制区域顶部留白，确保裁剪框只覆盖真实图片内容。
   */
  private imageDrawTop(): number {
    return Math.max(0, Math.floor((this.cropSurfaceHeightPx - this.imageDrawHeight()) / 2));
  }

  /**
   * 将归一化宽度转换为界面像素宽度，同时应用最小可操作尺寸保护。
   */
  private cropFrameWidth(): number {
    return Math.max(this.minCropPixelSize, Math.floor(this.imageDrawWidth() * this.cropWidthPercent / 100));
  }

  /**
   * 将归一化高度转换为界面像素高度，同时应用最小可操作尺寸保护。
   */
  private cropFrameHeight(): number {
    return Math.max(this.minCropPixelSize, Math.floor(this.imageDrawHeight() * this.cropHeightPercent / 100));
  }

  /**
   * 将归一化左边界转换为画布内像素位置，并叠加图片可见区域偏移。
   */
  private cropFrameLeft(): number {
    return this.imageDrawLeft() + Math.floor(this.imageDrawWidth() * this.cropXPercent / 100);
  }

  /**
   * 将归一化上边界转换为画布内像素位置，并叠加图片可见区域偏移。
   */
  private cropFrameTop(): number {
    return this.imageDrawTop() + Math.floor(this.imageDrawHeight() * this.cropYPercent / 100);
  }

  private currentCropRect(): CropRect {
    return {
      x: this.cropXPercent / 100,
      y: this.cropYPercent / 100,
      width: this.cropWidthPercent / 100,
      height: this.cropHeightPercent / 100
    };
  }

  private beginCropDrag(): void {
    this.dragStartXPercent = this.cropXPercent;
    this.dragStartYPercent = this.cropYPercent;
  }

  private beginCropResize(): void {
    this.resizeStartXPercent = this.cropXPercent;
    this.resizeStartYPercent = this.cropYPercent;
    this.resizeStartWidthPercent = this.cropWidthPercent;
    this.resizeStartHeightPercent = this.cropHeightPercent;
  }

  /**
   * 处理裁剪框平移手势。
   * ArkUI 当前页面只做移动框，不引入旋转、去噪等 V1.2 图像增强；裁剪服务会再次做边界兜底。
   */
  private moveCropFrame(offsetX: number, offsetY: number): void {
    if (this.loading || !this.hasCropImage()) {
      return;
    }
    const nextX = this.dragStartXPercent + offsetX * 100 / this.imageDrawWidth();
    const nextY = this.dragStartYPercent + offsetY * 100 / this.imageDrawHeight();
    this.cropXPercent = this.clampPercent(nextX, 0, 100 - this.cropWidthPercent);
    this.cropYPercent = this.clampPercent(nextY, 0, 100 - this.cropHeightPercent);
    this.cropConfirmed = false;
    this.noticeMessage = '已移动裁剪框，生成时会按当前矩形输出。';
  }

  /**
   * 处理四角和边线控制点缩放。
   * 只改变矩形裁剪区域，不引入旋转、透视校正或其他超出当前真实能力的图像增强。
   */
  private resizeCropFrame(handle: string, offsetX: number, offsetY: number): void {
    if (this.loading || !this.hasCropImage()) {
      return;
    }
    const deltaX = offsetX * 100 / this.imageDrawWidth();
    const deltaY = offsetY * 100 / this.imageDrawHeight();
    const minWidth = this.currentMinCropWidthPercent();
    const minHeight = this.currentMinCropHeightPercent();
    let nextX = this.resizeStartXPercent;
    let nextY = this.resizeStartYPercent;
    let nextWidth = this.resizeStartWidthPercent;
    let nextHeight = this.resizeStartHeightPercent;

    if (handle.indexOf('left') >= 0) {
      nextX = this.clampPercent(this.resizeStartXPercent + deltaX, 0, this.resizeStartXPercent + this.resizeStartWidthPercent - minWidth);
      nextWidth = this.resizeStartWidthPercent + (this.resizeStartXPercent - nextX);
    } else if (handle.indexOf('right') >= 0) {
      nextWidth = this.clampPercent(this.resizeStartWidthPercent + deltaX, minWidth, 100 - this.resizeStartXPercent);
    }

    if (handle.indexOf('top') >= 0) {
      nextY = this.clampPercent(this.resizeStartYPercent + deltaY, 0, this.resizeStartYPercent + this.resizeStartHeightPercent - minHeight);
      nextHeight = this.resizeStartHeightPercent + (this.resizeStartYPercent - nextY);
    } else if (handle.indexOf('bottom') >= 0) {
      nextHeight = this.clampPercent(this.resizeStartHeightPercent + deltaY, minHeight, 100 - this.resizeStartYPercent);
    }

    this.cropXPercent = this.clampPercent(nextX, 0, 100 - nextWidth);
    this.cropYPercent = this.clampPercent(nextY, 0, 100 - nextHeight);
    this.cropWidthPercent = this.clampPercent(nextWidth, minWidth, 100 - this.cropXPercent);
    this.cropHeightPercent = this.clampPercent(nextHeight, minHeight, 100 - this.cropYPercent);
    this.cropRatioPercent = Math.round(Math.min(this.cropWidthPercent, this.cropHeightPercent));
    this.cropConfirmed = false;
    this.noticeMessage = '已调整裁剪框大小，生成时会按当前矩形输出。';
  }

  private currentMinCropWidthPercent(): number {
    return Math.max(this.minCropPercent, Math.ceil(this.minCropPixelSize * 100 / this.imageDrawWidth()));
  }

  private currentMinCropHeightPercent(): number {
    return Math.max(this.minCropPercent, Math.ceil(this.minCropPixelSize * 100 / this.imageDrawHeight()));
  }

  private cropHandleX(isRight: boolean): number {
    return this.cropFrameLeft() + (isRight ? this.cropFrameWidth() : 0) - Math.floor(this.handleSize / 2);
  }

  private cropHandleY(isBottom: boolean): number {
    return this.cropFrameTop() + (isBottom ? this.cropFrameHeight() : 0) - Math.floor(this.handleSize / 2);
  }

  private edgeHandleX(edge: string): number {
    if (edge === 'left') {
      return this.cropFrameLeft() - Math.floor(this.edgeHandleThickness / 2);
    }
    if (edge === 'right') {
      return this.cropFrameLeft() + this.cropFrameWidth() - Math.floor(this.edgeHandleThickness / 2);
    }
    return this.cropFrameLeft();
  }

  private edgeHandleY(edge: string): number {
    if (edge === 'top') {
      return this.cropFrameTop() - Math.floor(this.edgeHandleThickness / 2);
    }
    if (edge === 'bottom') {
      return this.cropFrameTop() + this.cropFrameHeight() - Math.floor(this.edgeHandleThickness / 2);
    }
    return this.cropFrameTop();
  }

  private edgeHandleWidth(edge: string): number {
    return edge === 'top' || edge === 'bottom' ? this.cropFrameWidth() : this.edgeHandleThickness;
  }

  private edgeHandleHeight(edge: string): number {
    return edge === 'left' || edge === 'right' ? this.cropFrameHeight() : this.edgeHandleThickness;
  }

  private hasCropImage(): boolean {
    return this.selectedImageUri.length > 0;
  }

  private toPositiveNumber(value: number | string, fallback: number): number {
    const parsed = Number(value);
    if (Number.isNaN(parsed) || parsed <= 0) {
      return fallback;
    }
    return parsed;
  }

  private clampPercent(value: number, min: number, max: number): number {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }

  private toUserMessage(error: Error, fallback: string): string {
    if (error.message && error.message.length > 0 && error.message.length < 80) {
      return error.message;
    }
    return fallback;
  }

  private statusTitle(): string {
    if (this.loading) {
      return '正在生成裁剪输出';
    }
    if (!this.hasCropImage()) {
      return '未选择图片';
    }
    return this.cropConfirmed ? '裁切区域已确认' : '图片已加载，可调整裁切';
  }

  private statusTone(): 'info' | 'success' | 'warning' | 'neutral' {
    if (this.loading) {
      return 'warning';
    }
    if (!this.hasCropImage()) {
      return 'neutral';
    }
    return this.cropConfirmed ? 'success' : 'info';
  }

  @Builder
  private ratioButton(label: string, value: number) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_META)
      .fontColor(this.cropRatioPercent === value ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
      .backgroundColor(this.cropRatioPercent === value ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: this.cropRatioPercent === value ? AppTheme.COLOR_BRAND : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(!this.loading && this.hasCropImage())
      .onClick(() => this.setCropRatioPercent(value))
  }

  @Builder
  private emptyCropState() {
    Column({ space: 12 }) {
      OcrScanBadge({ label: '待选择' })
        .borderRadius(AppTheme.RADIUS_PANEL)
        .clip(true)

      Text('请返回相册或拍照入口重新选择')
        .fontSize(AppTheme.FONT_META)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(AppTheme.LINE_META)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 18, right: 18, top: 22, bottom: 22 })
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: AppTheme.SECTION_GAP }) {
        HtmlAppBar({
          title: '图片裁剪',
          subtitle: '拖动边角调整识别区域',
          showBackButton: true,
          actionLabel: '···',
          onBack: () => this.backToPreview()
        })

        StatusBanner({
          label: '裁剪',
          title: this.statusTitle(),
          message: this.noticeMessage,
          tone: this.statusTone()
        })

        if (this.errorMessage.length > 0) {
          StatusBanner({
            label: '错误',
            title: '裁剪未完成',
            message: this.errorMessage,
            tone: 'danger'
          })
        }

        Column({ space: 10 }) {
          HtmlSectionHead({ title: '裁剪工作台', meta: this.cropConfirmed ? 'confirmed' : 'adjusting' })

          Row({ space: 8 }) {
            HtmlBadge({ label: '拖动移动', tone: 'neutral' })
            HtmlBadge({ label: '边角缩放', tone: 'ok' })
            HtmlBadge({ label: '矩形范围', tone: 'warn' })
          }
          .width('100%')

          Text('当前支持矩形范围裁剪，适合票据、文档和屏幕截图。')
            .fontSize(AppTheme.FONT_META)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
        }
        .width('100%')

        Stack() {
          if (this.hasCropImage()) {
            Image(this.selectedImageUri)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Contain)

            Column()
              .width(this.cropFrameWidth())
              .height(this.cropFrameHeight())
              .border({ width: 2, color: AppTheme.COLOR_BRAND, style: BorderStyle.Solid })
              .backgroundColor(AppTheme.COLOR_BRAND_OVERLAY)
              .position({ x: this.cropFrameLeft(), y: this.cropFrameTop() })
              .gesture(
                PanGesture()
                  .onActionStart(() => this.beginCropDrag())
                  .onActionUpdate((event: GestureEvent) => {
                    this.moveCropFrame(event.offsetX, event.offsetY);
                  })
              )

            Column()
              .width(this.handleSize)
              .height(this.handleSize)
              .borderRadius(Math.floor(this.handleSize / 2))
              .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
              .border({ width: 2, color: AppTheme.COLOR_BRAND })
              .position({ x: this.cropHandleX(false), y: this.cropHandleY(false) })
              .gesture(
                PanGesture()
                  .onActionStart(() => this.beginCropResize())
                  .onActionUpdate((event: GestureEvent) => {
                    this.resizeCropFrame('top-left', event.offsetX, event.offsetY);
                  })
              )

            Column()
              .width(this.handleSize)
              .height(this.handleSize)
              .borderRadius(Math.floor(this.handleSize / 2))
              .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
              .border({ width: 2, color: AppTheme.COLOR_BRAND })
              .position({ x: this.cropHandleX(true), y: this.cropHandleY(false) })
              .gesture(
                PanGesture()
                  .onActionStart(() => this.beginCropResize())
                  .onActionUpdate((event: GestureEvent) => {
                    this.resizeCropFrame('top-right', event.offsetX, event.offsetY);
                  })
              )

            Column()
              .width(this.handleSize)
              .height(this.handleSize)
              .borderRadius(Math.floor(this.handleSize / 2))
              .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
              .border({ width: 2, color: AppTheme.COLOR_BRAND })
              .position({ x: this.cropHandleX(false), y: this.cropHandleY(true) })
              .gesture(
                PanGesture()
                  .onActionStart(() => this.beginCropResize())
                  .onActionUpdate((event: GestureEvent) => {
                    this.resizeCropFrame('bottom-left', event.offsetX, event.offsetY);
                  })
              )

            Column()
              .width(this.handleSize)
              .height(this.handleSize)
              .borderRadius(Math.floor(this.handleSize / 2))
              .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
              .border({ width: 2, color: AppTheme.COLOR_BRAND })
              .position({ x: this.cropHandleX(true), y: this.cropHandleY(true) })
              .gesture(
                PanGesture()
                  .onActionStart(() => this.beginCropResize())
                  .onActionUpdate((event: GestureEvent) => {
                    this.resizeCropFrame('bottom-right', event.offsetX, event.offsetY);
                  })
              )

            ForEach(['top', 'bottom', 'left', 'right'], (edge: string) => {
              Column()
                .width(this.edgeHandleWidth(edge))
                .height(this.edgeHandleHeight(edge))
                .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
                .opacity(0.96)
                .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_BRAND })
                .borderRadius(5)
                .position({ x: this.edgeHandleX(edge), y: this.edgeHandleY(edge) })
                .gesture(
                  PanGesture()
                    .onActionStart(() => this.beginCropResize())
                    .onActionUpdate((event: GestureEvent) => {
                      this.resizeCropFrame(edge, event.offsetX, event.offsetY);
                    })
                )
            })

            Column()
              .width(Math.max(this.minCropPixelSize, this.cropFrameWidth() - 24))
              .height(2)
              .backgroundColor(AppTheme.COLOR_SCAN_LINE)
              .opacity(0.75)
              .position({ x: this.cropFrameLeft() + 12, y: this.cropFrameTop() + Math.floor(this.cropFrameHeight() / 2) })
          } else {
            this.emptyCropState()
          }
        }
        .width('100%')
        .height(AppTheme.OCR_FRAME_HEIGHT)
        .padding(8)
        .backgroundColor(AppTheme.COLOR_SCAN_BG)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
        .borderRadius(AppTheme.RADIUS_DOCUMENT)
        .onAreaChange((oldArea: Area, newArea: Area) => {
          this.updateCropSurfaceSize(newArea.width as number | string, newArea.height as number | string);
        })

        Column({ space: 12 }) {
          Row({ space: 8 }) {
            HtmlBadge({ label: `宽 ${Math.round(this.cropWidthPercent)}%`, tone: 'neutral' })
            HtmlBadge({ label: `高 ${Math.round(this.cropHeightPercent)}%`, tone: 'neutral' })
            HtmlBadge({ label: this.cropConfirmed ? '已生成裁剪' : '边角/边线可拖动', tone: this.cropConfirmed ? 'ok' : 'dark' })
          }
          .width('100%')

          Row({ space: 8 }) {
            this.ratioButton('60%', 60)
            this.ratioButton('80%', 80)
            this.ratioButton('100%', 100)
            Button('重置')
              .layoutWeight(1)
              .height(36)
              .type(ButtonType.Normal)
              .fontSize(AppTheme.FONT_META)
              .fontColor(AppTheme.COLOR_ACCENT_DARK)
              .backgroundColor(AppTheme.COLOR_ACCENT_SOFT)
              .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
              .borderRadius(AppTheme.RADIUS_CONTROL)
              .enabled(!this.loading && this.hasCropImage())
              .onClick(() => this.resetCropFrame())
          }
          .width('100%')
        }
        .width('100%')
        .padding(AppTheme.CARD_PADDING)
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)

        TextActionButton({
          label: this.loading ? '生成裁剪中...' : '确认裁剪',
          primary: true,
          enabledState: !this.loading && this.hasCropImage(),
          onTap: () => this.cropAndProceed()
        })

        TextActionButton({
          label: '上一步',
          enabledState: !this.loading,
          onTap: () => this.backToPreview()
        })
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
