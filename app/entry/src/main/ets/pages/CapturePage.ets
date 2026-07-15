import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import {
  HtmlAppBar,
  HtmlBadge,
  HtmlSectionHead,
  HtmlToolChip,
  StatusBanner,
  TextActionButton
} from '../components/BrandComponents';
import { DeviceImagePickerService } from '../features/ocr/DeviceImagePickerService';
import { DeviceImageSelection } from '../features/ocr/DeviceOcrModels';
import { OcrFlowState } from '../features/ocr/OcrFlowState';

type CaptureStage = 'permission' | 'ready' | 'unavailable' | 'captured';
type BannerTone = 'info' | 'success' | 'warning' | 'danger' | 'neutral';

/**
 * CapturePage 是拍照 OCR 图片获取入口，属于 features/ocr 页面层。
 * 维护说明：页面只通过系统图片入口获取用户确认图片；不会上传文件、创建记录或回退到示例结果。
 */
@Entry
@Component
struct CapturePage {
  @State private stage: CaptureStage = 'permission';
  @State private loading: boolean = false;
  @State private errorMessage: string = '';
  @State private noticeMessage: string = '请授权打开系统拍照入口；本页不会后台录制，也不会读取未选择的图片。';

  /**
   * 打开支持拍照入口的系统图片选择器。
   * 安全边界：只接收用户本轮确认返回的短期 URI；失败和取消都不会写入图片路径或创建 OCR 记录。
   */
  private async captureImage(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.stage = 'ready';
    this.noticeMessage = '正在打开系统拍照/图片选择入口，请在系统界面中完成拍照。';
    try {
      const selection: DeviceImageSelection | undefined = await DeviceImagePickerService.selectImage('camera');
      if (!selection) {
        this.stage = 'ready';
        this.noticeMessage = '已取消拍照或图片选择，未读取图片、未上传文件。';
        return;
      }
      OcrFlowState.startWithImage(selection);
      this.stage = 'captured';
      this.noticeMessage = '已获得用户确认的图片，正在进入预览。';
      AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_PREVIEW);
    } catch (_) {
      this.stage = 'unavailable';
      this.errorMessage = '无法访问系统拍照入口。可能是相机被占用、权限受限、设备不支持拍照入口，或当前平台仅允许相册选择。';
      this.noticeMessage = '当前未读取图片、未上传文件、未创建 OCR 记录；可重试或改用相册导入。';
    } finally {
      this.loading = false;
    }
  }

  private openAlbum(): void {
    if (!this.loading) {
      AppNavigator.push(this.getUIContext(), AppRoutes.ALBUM);
    }
  }

  private continuePreview(): void {
    if (this.loading) {
      return;
    }
    if (!OcrFlowState.hasSelectedImage()) {
      this.stage = 'ready';
      this.errorMessage = '当前没有可预览图片，请重新拍照或改用相册导入。';
      this.noticeMessage = '不会使用示例图片代替真实输入。';
      return;
    }
    AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_PREVIEW);
  }

  private showSinglePageNotice(): void {
    this.errorMessage = '';
    this.noticeMessage = '当前拍照入口一次只处理一张由系统返回的图片。';
  }

  private statusTitle(): string {
    if (this.loading) {
      return '正在等待系统拍照入口';
    }
    if (this.stage === 'permission') {
      return '需要相机访问授权';
    }
    if (this.stage === 'unavailable') {
      return '拍照入口不可用';
    }
    if (this.stage === 'captured') {
      return '图片已获取';
    }
    return '可打开系统拍照入口';
  }

  private statusTone(): BannerTone {
    if (this.stage === 'unavailable') {
      return 'danger';
    }
    if (this.loading) {
      return 'warning';
    }
    if (this.stage === 'captured') {
      return 'success';
    }
    return this.stage === 'permission' ? 'neutral' : 'info';
  }

  private statusLabel(): string {
    if (this.stage === 'permission') {
      return '相机权限';
    }
    if (this.stage === 'unavailable') {
      return '降级';
    }
    if (this.stage === 'captured') {
      return '已拍摄';
    }
    return '拍照';
  }

  @Builder
  private statePanel(tag: string, title: string, body: string, tone: BannerTone) {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: title, meta: tag })

      Row({ space: 12 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(34)
            .height(42)
            .border({ width: 2, color: tone === 'danger' ? AppTheme.COLOR_DANGER : AppTheme.COLOR_BRAND })
            .borderRadius(8)
          Column()
            .width(20)
            .height(2)
            .backgroundColor(tone === 'danger' ? AppTheme.COLOR_DANGER : AppTheme.COLOR_BRAND)
          Column()
            .width(2)
            .height(20)
            .backgroundColor(tone === 'danger' ? AppTheme.COLOR_DANGER : AppTheme.COLOR_BRAND)
        }
        .width(54)
        .height(58)
        .backgroundColor(tone === 'danger' ? AppTheme.COLOR_DANGER_BG : AppTheme.COLOR_SURFACE_SOFT)
        .border({ width: AppTheme.HAIRLINE, color: tone === 'danger' ? AppTheme.COLOR_DANGER_LINE : AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_CONTROL)

        Column({ space: 6 }) {
          Text(body)
            .fontSize(AppTheme.FONT_META)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')

          Row({ space: 8 }) {
            HtmlBadge({ label: '真实系统入口', tone: tone === 'danger' ? 'danger' : 'neutral' })
            HtmlBadge({ label: '不后台录制', tone: 'dark' })
          }
          .width('100%')
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: tone === 'danger' ? AppTheme.COLOR_DANGER_LINE : AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private permissionStage() {
    this.statePanel(
      'permission',
      '需要相机访问权限',
      '请通过系统入口授权本次拍照或图片选择。授权仅用于用户主动采集的文档图片，不会读取相册中的其他内容。',
      'neutral'
    )

    TextActionButton({
      label: this.loading ? '打开中...' : '授权并打开相机',
      primary: true,
      enabledState: !this.loading,
      onTap: () => this.captureImage()
    })

    TextActionButton({
      label: '返回首页',
      enabledState: !this.loading,
      onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.HOME)
    })
  }

  @Builder
  private unavailableStage() {
    this.statePanel(
      'unavailable',
      '无法访问相机',
      '相机被其他应用占用、被系统禁用或当前设备不支持系统拍照入口时，请重试或改用相册导入。',
      'danger'
    )

    TextActionButton({
      label: '改用相册导入',
      primary: true,
      enabledState: !this.loading,
      onTap: () => this.openAlbum()
    })

    TextActionButton({
      label: this.loading ? '重试中...' : '重试打开相机',
      enabledState: !this.loading,
      onTap: () => this.captureImage()
    })
  }

  @Builder
  private documentSkeleton() {
    Column({ space: 10 }) {
      Column().width('38%').height(6).backgroundColor(AppTheme.COLOR_PREVIEW_ACCENT_LINE).borderRadius(3)
      Column().width('82%').height(6).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
      Column().width('76%').height(6).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
      Column().width('90%').height(6).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
      Row({ space: 5 }) {
        Column().layoutWeight(1).height(26).backgroundColor(AppTheme.COLOR_PREVIEW_TABLE_BG).borderRadius(4)
        Column().layoutWeight(1).height(26).backgroundColor(AppTheme.COLOR_PREVIEW_TABLE_BG).borderRadius(4)
        Column().layoutWeight(1).height(26).backgroundColor(AppTheme.COLOR_PREVIEW_TABLE_BG).borderRadius(4)
      }
      .width('100%')
      Column().width('68%').height(6).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
      Column().width('50%').height(6).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
    }
    .width('64%')
    .height(190)
    .padding(18)
    .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_SCAN_BORDER })
    .borderRadius(AppTheme.RADIUS_DOCUMENT)
    .rotate({ angle: -2 })
  }

  @Builder
  private viewfinder(hint: string) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppTheme.COLOR_SCAN_BG)

      Column()
        .width('82%')
        .height(232)
        .border({ width: 2, color: AppTheme.COLOR_SCAN_LINE, style: BorderStyle.Dashed })
        .borderRadius(AppTheme.RADIUS_DOCUMENT)
        .backgroundColor(AppTheme.COLOR_SCAN_OVERLAY)

      this.documentSkeleton()

      Column().width(34).height(34).border({ width: 2, color: AppTheme.COLOR_SCAN_LINE }).borderRadius(5).position({ x: 26, y: 26 })
      Column().width(34).height(34).border({ width: 2, color: AppTheme.COLOR_SCAN_LINE }).borderRadius(5).position({ x: 292, y: 26 })
      Column().width(34).height(34).border({ width: 2, color: AppTheme.COLOR_SCAN_LINE }).borderRadius(5).position({ x: 26, y: 258 })
      Column().width(34).height(34).border({ width: 2, color: AppTheme.COLOR_SCAN_LINE }).borderRadius(5).position({ x: 292, y: 258 })

      Text(hint)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_SCAN_TEXT_MUTED)
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor(AppTheme.COLOR_SCAN_BORDER)
        .borderRadius(AppTheme.RADIUS_BADGE)
        .position({ x: 82, y: 276 })
    }
    .width('100%')
    .height(AppTheme.OCR_FRAME_HEIGHT)
    .backgroundColor(AppTheme.COLOR_SCAN_BG)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
    .borderRadius(AppTheme.RADIUS_DOCUMENT)
    .clip(true)
  }

  @Builder
  private captureBar() {
    Row({ space: 14 }) {
      Button() {
        Column({ space: 3 }) {
          Text('相册')
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_BRAND)
          Text('导入')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(64)
      .type(ButtonType.Normal)
      .backgroundColor(AppTheme.COLOR_PAGE_DEEP)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(!this.loading)
      .onClick(() => this.openAlbum())

      Button() {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(70)
            .height(70)
            .border({ width: 4, color: AppTheme.COLOR_SURFACE_ELEVATED })
            .borderRadius(35)
          Column()
            .width(50)
            .height(50)
            .backgroundColor(AppTheme.COLOR_BRAND)
            .borderRadius(25)
        }
        .width('100%')
        .height('100%')
      }
      .width(88)
      .height(88)
      .type(ButtonType.Normal)
      .backgroundColor(AppTheme.COLOR_TRANSPARENT)
      .enabled(!this.loading)
      .onClick(() => this.captureImage())

      Button() {
        Column({ space: 3 }) {
          Text('重试')
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_BRAND)
          Text('系统')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(64)
      .type(ButtonType.Normal)
      .backgroundColor(AppTheme.COLOR_PAGE_DEEP)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(!this.loading)
      .onClick(() => this.captureImage())
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private readyStage() {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: '取景与边缘检测', meta: 'ready' })

      this.viewfinder('系统拍照入口 · 对准文档后确认')

      Row({ space: 8 }) {
        HtmlToolChip({ label: '单页', primary: true, enabledState: !this.loading, onTap: () => this.showSinglePageNotice() })
        HtmlToolChip({ label: '相册', enabledState: !this.loading, onTap: () => this.openAlbum() })
        HtmlToolChip({ label: '隐私', enabledState: !this.loading, onTap: () => {
          this.errorMessage = '';
          this.noticeMessage = '拍照结果只在用户确认后进入预览；失败时不会使用示例图片兜底。';
        } })
      }
      .width('100%')

      this.captureBar()
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private capturedStage() {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: '已拍摄预览', meta: 'captured' })

      this.viewfinder('已获取图片 · 进入预览确认')

      Row({ space: 8 }) {
        HtmlBadge({ label: '已选择 1 张', tone: 'ok' })
        HtmlBadge({ label: '预览确认', tone: 'dark' })
        HtmlBadge({ label: '未上传', tone: 'neutral' })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)

    TextActionButton({
      label: '继续预览',
      primary: true,
      enabledState: !this.loading,
      onTap: () => this.continuePreview()
    })

    TextActionButton({
      label: this.loading ? '重拍中...' : '重拍',
      enabledState: !this.loading,
      onTap: () => this.captureImage()
    })
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({
            title: '拍照扫描',
            subtitle: '系统拍照入口 · 预览后 OCR',
            actionLabel: '···'
          })

          StatusBanner({
            label: this.statusLabel(),
            title: this.statusTitle(),
            message: this.noticeMessage,
            tone: this.statusTone()
          })

          if (this.errorMessage.length > 0) {
            StatusBanner({
              label: '错误',
              title: '图片获取失败',
              message: this.errorMessage,
              tone: 'danger'
            })
          }

          if (this.stage === 'permission') {
            this.permissionStage()
          } else if (this.stage === 'unavailable') {
            this.unavailableStage()
          } else if (this.stage === 'captured') {
            this.capturedStage()
          } else {
            this.readyStage()
          }
        }
        .width('100%')
        .padding(AppTheme.PAGE_PADDING)
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
