import { common } from '@kit.AbilityKit';
import { picker } from '@kit.CoreFileKit';
import { ApiError } from '../common/network/ApiTypes';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import {
  HtmlAppBar,
  HtmlBadge,
  HtmlFileMark,
  HtmlSectionHead,
  HtmlToolChip,
  StatusBanner,
  TextActionButton
} from '../components/BrandComponents';
import { DevicePdfPickerService, DevicePdfSelection } from '../features/file/DevicePdfPickerService';
import { DeviceImagePickerService } from '../features/ocr/DeviceImagePickerService';
import { DeviceImageSelection } from '../features/ocr/DeviceOcrModels';
import { OcrFlowState } from '../features/ocr/OcrFlowState';
import { PdfOcrService } from '../features/ocr/PdfOcrService';
import { UserPreferenceService } from '../features/settings/UserPreferenceService';

type AlbumStage =
  'permission'
  | 'emptySelection'
  | 'imageSelected'
  | 'pdfSelected'
  | 'pdfUploading'
  | 'pdfRecognized'
  | 'pdfPartial'
  | 'pdfFailed'
  | 'pdfEncrypted'
  | 'pdfTooLarge'
  | 'pdfTooManyPages'
  | 'importFailure';
type BannerTone = 'info' | 'success' | 'warning' | 'danger' | 'neutral';
type BadgeTone = 'neutral' | 'ok' | 'warn' | 'danger' | 'dark';

/**
 * AlbumPage 负责相册识别和文件导入入口。
 * 维护说明：页面只处理用户通过系统 picker 主动授权返回的图片/PDF URI，不记录本地完整路径。
 */
@Entry
@Component
struct AlbumPage {
  @State private stage: AlbumStage = 'emptySelection';
  @State private loading: boolean = false;
  @State private errorMessage: string = '';
  @State private noticeMessage: string = '请选择图片或扫描型 PDF；取消选择不会读取文件，也不会上传内容。';
  @State private selectedPdfNotice: string = '';
  private selectedPdf: DevicePdfSelection | undefined = undefined;

  /**
   * 打开系统相册选择器并进入图片预览。
   * 安全边界：只接收系统 PhotoViewPicker 返回的短期授权 URI，不展示、不记录原始 URI。
   */
  private async selectAlbumImage(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.selectedPdf = undefined;
    this.selectedPdfNotice = '';
    this.noticeMessage = '正在打开系统相册选择器...';
    try {
      const selection: DeviceImageSelection | undefined = await DeviceImagePickerService.selectImage('album');
      if (!selection) {
        this.stage = 'emptySelection';
        this.noticeMessage = '已取消相册选择，未读取图片，也未上传文件。';
        return;
      }
      OcrFlowState.startWithImage(selection);
      this.stage = 'imageSelected';
      this.noticeMessage = '已获得用户选择的图片，正在进入预览。';
      AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_PREVIEW);
    } catch (_) {
      this.stage = 'permission';
      this.errorMessage = '相册选择失败，请确认系统授权或当前平台图片选择能力后重试。';
      this.noticeMessage = '失败信息不包含本地路径，也不会创建记录或上传文件。';
    } finally {
      this.loading = false;
    }
  }

  /**
   * 通过系统文件选择器导入图片文件。
   * 安全边界：只接收本轮 DocumentViewPicker 返回的授权 URI，不保存原始路径或文件名。
   */
  private async selectImageFile(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.selectedPdf = undefined;
    this.selectedPdfNotice = '';
    this.noticeMessage = '正在打开系统文件图片选择器...';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['Image|.png,.jpg,.jpeg,.webp,.heic,.heif,.bmp,.gif,.tif,.tiff'];
      options.maxSelectNumber = 1;
      const documentPicker = new picker.DocumentViewPicker(context);
      const uris: Array<string> = await documentPicker.select(options);
      if (uris.length === 0) {
        this.stage = 'emptySelection';
        this.noticeMessage = '已取消文件图片选择，未读取图片，也未上传文件。';
        return;
      }
      const selection: DeviceImageSelection = {
        sourceType: 'album',
        uri: uris[0],
        fileName: `ocr-document-image-${Date.now()}`,
        mimeType: 'image/*',
        uploadSource: 'document_picker_image'
      };
      OcrFlowState.startWithImage(selection);
      this.stage = 'imageSelected';
      this.noticeMessage = '已通过系统文件选择器选择 1 张图片，正在进入预览。';
      AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_PREVIEW);
    } catch (_) {
      this.stage = 'importFailure';
      this.errorMessage = '文件图片选择失败或当前文件服务不可用。';
      this.noticeMessage = '未读取本地路径，未创建记录或上传文件。';
    } finally {
      this.loading = false;
    }
  }

  /**
   * 打开系统文件 picker 选择扫描型 PDF。
   * 安全边界：PDF URI 只保存在组件内存字段用于本轮上传；页面仅展示脱敏文件名和大小。
   */
  private async selectScannedPdf(): Promise<void> {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.selectedPdf = undefined;
    this.selectedPdfNotice = '';
    this.noticeMessage = '正在打开系统 PDF 文件选择器...';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const selection: DevicePdfSelection | undefined = await DevicePdfPickerService.selectPdf(context);
      if (!selection) {
        this.stage = 'emptySelection';
        this.noticeMessage = '已取消 PDF 选择，未读取文件，也未创建 OCR 记录。';
        return;
      }
      this.selectedPdf = selection;
      this.stage = 'pdfSelected';
      this.selectedPdfNotice = `已选择 ${selection.displayName} · ${this.fileSizeLabel(selection.size)}`;
      this.noticeMessage = 'PDF 已选择。点击开始识别后才会上传到后端逐页 OCR。';
    } catch (_) {
      this.stage = 'importFailure';
      this.errorMessage = 'PDF 文件选择失败或当前文件服务不可用。';
      this.noticeMessage = '未读取 PDF 内容，未创建 OCR 记录。';
    } finally {
      this.loading = false;
    }
  }

  /**
   * 上传本轮选择的扫描型 PDF 并进入真实后端 OCR。
   * 说明：没有选中文件时不会伪造结果；所有失败态只显示脱敏错误文案。
   */
  private async recognizeSelectedPdf(): Promise<void> {
    if (this.loading) {
      return;
    }
    const selection = this.selectedPdf;
    if (!selection) {
      this.stage = 'emptySelection';
      this.errorMessage = '请先选择扫描型 PDF。';
      this.noticeMessage = '未选择 PDF 时不会提交空任务或生成示例结果。';
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.stage = 'pdfUploading';
    this.noticeMessage = '正在上传 PDF 并请求后端逐页 OCR...';
    try {
      const result = await PdfOcrService.recognizePdf(selection, await this.pdfRecognitionLanguageHint());
      OcrFlowState.setPdfResult(result);
      this.stage = result.partial ? 'pdfPartial' : 'pdfRecognized';
      this.selectedPdfNotice = `共 ${result.pageCount} 页，成功 ${result.successPageCount} 页，失败 ${result.failedPageCount} 页`;
      this.noticeMessage = result.partial ? 'PDF 已完成部分识别，正在进入结果页。' : 'PDF 已完成识别，正在进入结果页。';
      AppNavigator.push(this.getUIContext(), AppRoutes.OCR_RESULT);
    } catch (error) {
      this.stage = this.pdfFailureStage(error as Error);
      this.errorMessage = this.pdfUserMessage(error as Error);
      this.noticeMessage = 'PDF 识别未完成，未伪造成功结果。';
    } finally {
      this.loading = false;
    }
  }

  /**
   * 读取 PDF OCR 语言提示。
   * 说明：Windows.Media.Ocr 在后端不会可靠地自动选择混排引擎；PDF 自动模式按中英混合计划处理，用户显式选择英文时才传 en。
   */
  private async pdfRecognitionLanguageHint(): Promise<string> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const preferences = await UserPreferenceService.load(context);
    const hint = UserPreferenceService.toBackendLanguageHint(preferences.recognitionLanguage);
    return hint.length > 0 ? hint : 'zh-Hans,en';
  }

  private continueImagePreview(): void {
    if (this.loading) {
      return;
    }
    if (!OcrFlowState.hasSelectedImage()) {
      this.stage = 'emptySelection';
      this.errorMessage = '当前没有可预览图片，请重新选择。';
      this.noticeMessage = '不会使用示例图片代替真实输入。';
      return;
    }
    AppNavigator.push(this.getUIContext(), AppRoutes.IMAGE_PREVIEW);
  }

  private fileSizeLabel(size: number): string {
    if (size <= 0) {
      return '大小未知';
    }
    if (size < 1024 * 1024) {
      return `${Math.max(1, Math.round(size / 1024))} KB`;
    }
    return `${(size / 1024 / 1024).toFixed(1)} MB`;
  }

  private pdfFailureStage(error: Error): AlbumStage {
    const apiError = error as ApiError;
    if (apiError.code === 'PDF_ENCRYPTED') {
      return 'pdfEncrypted';
    }
    if (apiError.code === 'PDF_TOO_MANY_PAGES') {
      return 'pdfTooManyPages';
    }
    if (apiError.code === 'FILE_TOO_LARGE') {
      return 'pdfTooLarge';
    }
    if (apiError.code === 'FILE_TYPE_NOT_ALLOWED' || apiError.code === 'PDF_INVALID' || apiError.code === 'PDF_READ_FAILED' || apiError.code === 'VALIDATION_ERROR') {
      return 'importFailure';
    }
    return 'pdfFailed';
  }

  private pdfUserMessage(error: Error): string {
    const apiError = error as ApiError;
    if (apiError.statusCode === 404 || apiError.code === 'NOT_FOUND') {
      return '扫描型 PDF 识别服务暂未开放';
    }
    if (apiError.code === 'PDF_ENCRYPTED') {
      return '加密 PDF 暂不支持识别';
    }
    if (apiError.code === 'PDF_TOO_MANY_PAGES') {
      return 'PDF 页数超过当前支持上限';
    }
    if (apiError.code === 'FILE_TOO_LARGE') {
      return 'PDF 文件过大，请选择较小文件';
    }
    if (apiError.code === 'FILE_TYPE_NOT_ALLOWED') {
      return '请选择 PDF 文件';
    }
    if (apiError.code === 'PDF_INVALID' || apiError.code === 'PDF_READ_FAILED' || apiError.code === 'VALIDATION_ERROR') {
      return 'PDF 文件损坏、为空或无法读取，请重新选择。';
    }
    if (apiError.code === 'QUOTA_EXCEEDED') {
      return 'OCR 额度不足，无法继续识别';
    }
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return '登录状态已失效，请重新登录。';
    }
    if (apiError.message && apiError.message.length > 0 && apiError.message.length < 80) {
      return apiError.message;
    }
    return 'PDF 文件选择或识别失败，请稍后重试。';
  }

  private statusTitle(): string {
    if (this.loading && this.stage === 'pdfUploading') {
      return '正在逐页识别 PDF';
    }
    if (this.loading) {
      return '正在等待系统选择器';
    }
    if (this.stage === 'permission') {
      return '需要相册访问权限';
    }
    if (this.stage === 'imageSelected') {
      return '图片已选择';
    }
    if (this.stage === 'pdfSelected') {
      return 'PDF 已选择';
    }
    if (this.stage === 'pdfRecognized') {
      return 'PDF 识别完成';
    }
    if (this.stage === 'pdfPartial') {
      return 'PDF 部分页失败';
    }
    if (this.stage === 'pdfEncrypted') {
      return '加密 PDF 暂不支持';
    }
    if (this.stage === 'pdfTooLarge') {
      return 'PDF 文件过大';
    }
    if (this.stage === 'pdfTooManyPages') {
      return 'PDF 页数超限';
    }
    if (this.stage === 'pdfFailed' || this.stage === 'importFailure') {
      return '导入或识别失败';
    }
    return '选择图片或 PDF';
  }

  private showFilters(): boolean {
    return this.stage === 'emptySelection' || this.stage === 'imageSelected';
  }

  private setFilterNotice(label: string): void {
    this.errorMessage = '';
    this.noticeMessage = `${label} 只改变当前入口提示；实际文件仍需通过系统选择器授权返回。`;
  }

  private pdfBadge(): string {
    if (this.stage === 'pdfUploading') {
      return '上传中';
    }
    if (this.stage === 'pdfRecognized') {
      return '成功';
    }
    if (this.stage === 'pdfPartial') {
      return '部分失败';
    }
    if (this.stage === 'pdfEncrypted') {
      return '加密';
    }
    if (this.stage === 'pdfTooLarge') {
      return '过大';
    }
    if (this.stage === 'pdfTooManyPages') {
      return '页数超限';
    }
    if (this.stage === 'pdfFailed') {
      return '失败';
    }
    return '已选择';
  }

  private pdfBadgeTone(): BadgeTone {
    if (this.stage === 'pdfRecognized') {
      return 'ok';
    }
    if (this.stage === 'pdfPartial' || this.stage === 'pdfEncrypted') {
      return 'warn';
    }
    if (this.stage === 'pdfFailed' || this.stage === 'pdfTooLarge' || this.stage === 'pdfTooManyPages') {
      return 'danger';
    }
    return 'neutral';
  }

  @Builder
  private statePanel(tag: string, title: string, body: string, tone: BannerTone) {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: title, meta: tag })

      Row({ space: 12 }) {
        HtmlFileMark({ label: 'DOC', tone: tone === 'danger' ? 'danger' : 'neutral' })

        Text(body)
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(AppTheme.LINE_META)
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
  private filterTools() {
    Row({ space: 8 }) {
      HtmlToolChip({ label: '全部', primary: true, enabledState: !this.loading, onTap: () => this.setFilterNotice('全部') })
      HtmlToolChip({ label: '图片', enabledState: !this.loading, onTap: () => this.selectAlbumImage() })
      HtmlToolChip({ label: 'PDF', enabledState: !this.loading, onTap: () => this.selectScannedPdf() })
      HtmlToolChip({ label: '最近', enabledState: !this.loading, onTap: () => this.setFilterNotice('最近') })
    }
    .width('100%')
  }

  @Builder
  private albumThumb(selected: boolean) {
    Button() {
      Stack() {
        Column({ space: 5 }) {
          Column().width('42%').height(5).backgroundColor(AppTheme.COLOR_PREVIEW_ACCENT_LINE).borderRadius(3)
          Column().width('82%').height(5).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
          Column().width('72%').height(5).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
          Row({ space: 3 }) {
            Column().layoutWeight(1).height(16).backgroundColor(AppTheme.COLOR_PREVIEW_TABLE_BG).borderRadius(3)
            Column().layoutWeight(1).height(16).backgroundColor(AppTheme.COLOR_PREVIEW_TABLE_BG).borderRadius(3)
          }
          .width('100%')
          Column().width('56%').height(5).backgroundColor(AppTheme.COLOR_PREVIEW_TEXT_LINE).borderRadius(3)
        }
        .width('70%')
        .height(66)
        .padding(10)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: selected ? AppTheme.COLOR_BRAND : AppTheme.COLOR_LINE_SOFT })
        .borderRadius(8)
        .rotate({ angle: selected ? -2 : 0 })

        if (selected) {
          Text('✓')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT_INVERSE)
            .width(22)
            .height(22)
            .textAlign(TextAlign.Center)
            .backgroundColor(AppTheme.COLOR_BRAND)
            .borderRadius(11)
            .position({ x: 64, y: 8 })
        }
      }
      .width('100%')
      .height('100%')
    }
    .layoutWeight(1)
    .height(92)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: selected ? AppTheme.COLOR_BRAND : AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
    .enabled(!this.loading)
    .onClick(() => this.selectAlbumImage())
  }

  @Builder
  private albumGrid(selected: boolean) {
    Column({ space: 8 }) {
      ForEach([0, 1, 2], (row: number) => {
        Row({ space: 8 }) {
          ForEach([0, 1, 2], (column: number) => {
            this.albumThumb(selected && row === 0 && column === 0)
          })
        }
        .width('100%')
      })
    }
    .width('100%')
  }

  @Builder
  private pdfFileCard() {
    Row({ space: 10 }) {
      HtmlFileMark({ label: 'DOC', tone: 'neutral' })

      Column({ space: 3 }) {
        Text('扫描型 PDF')
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
        Text(this.selectedPdfNotice.length > 0 ? this.selectedPdfNotice : '已选择的 PDF 文件')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .maxLines(2)
          .width('100%')
      }
      .layoutWeight(1)

      HtmlBadge({ label: this.pdfBadge(), tone: this.pdfBadgeTone() })
    }
    .width('100%')
    .height(72)
    .padding({ left: 13, right: 13, top: 12, bottom: 12 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CARD)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private skeletonRow() {
    Row({ space: 8 }) {
      Column().width(38).height(10).backgroundColor(AppTheme.COLOR_PAGE_DEEP).borderRadius(5)
      Column().layoutWeight(1).height(10).backgroundColor(AppTheme.COLOR_PAGE_DEEP).borderRadius(5)
      Column().width(56).height(10).backgroundColor(AppTheme.COLOR_PAGE_DEEP).borderRadius(5)
    }
    .width('100%')
    .height(24)
  }

  @Builder
  private emptySelectionStage() {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: '相册与文件导入', meta: 'emptySelection' })

      this.albumGrid(false)

      Row({ space: 8 }) {
        HtmlBadge({ label: '缩略图为占位骨架', tone: 'neutral' })
        HtmlBadge({ label: '系统授权后读取', tone: 'dark' })
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)

    TextActionButton({
      label: this.loading ? '相册选择中...' : '选择相册图片',
      primary: true,
      enabledState: !this.loading,
      onTap: () => this.selectAlbumImage()
    })

    TextActionButton({
      label: this.loading ? '文件图片选择中...' : '选择文件图片',
      enabledState: !this.loading,
      onTap: () => this.selectImageFile()
    })

    TextActionButton({
      label: this.loading ? 'PDF 选择中...' : '选择扫描型 PDF',
      enabledState: !this.loading,
      onTap: () => this.selectScannedPdf()
    })
  }

  @Builder
  private imageSelectedStage() {
    Column({ space: 12 }) {
      HtmlSectionHead({ title: '已选择图片', meta: 'imageSelected' })

      this.albumGrid(true)

      Row({ space: 8 }) {
        HtmlBadge({ label: '已选择 1 张', tone: 'ok' })
        HtmlBadge({ label: '进入预览链路', tone: 'dark' })
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
      onTap: () => this.continueImagePreview()
    })

    TextActionButton({
      label: '重新选择图片',
      enabledState: !this.loading,
      onTap: () => this.selectAlbumImage()
    })
  }

  @Builder
  private permissionStage() {
    this.statePanel(
      'permission',
      '需要相册访问权限',
      '请通过系统选择器授权访问本次图片或 PDF。授权只用于用户主动选择的文件，不会扫描相册中的其他内容。',
      'warning'
    )

    TextActionButton({
      label: this.loading ? '打开中...' : '重新打开相册选择器',
      primary: true,
      enabledState: !this.loading,
      onTap: () => this.selectAlbumImage()
    })

    TextActionButton({
      label: '返回首页',
      enabledState: !this.loading,
      onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.HOME)
    })
  }

  @Builder
  private pdfSelectedStage() {
    this.pdfFileCard()

    this.statePanel(
      'pdfSelected',
      '扫描型 PDF 已选择',
      '点击开始识别后才会上传 PDF 并请求后端逐页 OCR。页数、成功页和失败页以后端真实返回为准。',
      'info'
    )

    TextActionButton({
      label: this.loading ? '识别中...' : '开始识别 PDF',
      primary: true,
      enabledState: !this.loading && this.selectedPdf !== undefined,
      onTap: () => this.recognizeSelectedPdf()
    })

    TextActionButton({
      label: '重新选择 PDF',
      enabledState: !this.loading,
      onTap: () => this.selectScannedPdf()
    })
  }

  @Builder
  private pdfUploadingStage() {
    this.pdfFileCard()

    Column({ space: 10 }) {
      HtmlSectionHead({ title: '正在逐页识别 PDF', meta: 'pdfUploading' })
      Text('已开始真实上传和后端 OCR。逐页进度只以后端返回为准，本页不显示伪造百分比或占位文本。')
        .fontSize(AppTheme.FONT_META)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(AppTheme.LINE_META)
        .width('100%')
      this.skeletonRow()
      this.skeletonRow()
      this.skeletonRow()
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private pdfResultStage() {
    this.pdfFileCard()

    this.statePanel(
      this.stage,
      this.stage === 'pdfPartial' ? '部分页识别失败' : 'PDF 识别完成',
      this.stage === 'pdfPartial'
        ? '部分页面识别失败，成功页文本来自后端真实结果，失败页不会生成占位文本。'
        : 'PDF 已完成真实识别，结果来自后端 OCR 响应。',
      this.stage === 'pdfPartial' ? 'warning' : 'success'
    )

    TextActionButton({
      label: '查看识别结果',
      primary: true,
      enabledState: !this.loading,
      onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.OCR_RESULT)
    })

    TextActionButton({
      label: '重新选择 PDF',
      enabledState: !this.loading,
      onTap: () => this.selectScannedPdf()
    })
  }

  @Builder
  private pdfFailureStageView() {
    if (this.stage !== 'importFailure') {
      this.pdfFileCard()
    }

    this.statePanel(
      this.stage,
      this.statusTitle(),
      this.errorMessage.length > 0 ? this.errorMessage : '所选文件未完成识别，请重新选择后重试。',
      this.stage === 'pdfEncrypted' ? 'warning' : 'danger'
    )

    TextActionButton({
      label: '重新选择',
      primary: true,
      enabledState: !this.loading,
      onTap: () => this.selectScannedPdf()
    })

    TextActionButton({
      label: '选择图片',
      enabledState: !this.loading,
      onTap: () => this.selectAlbumImage()
    })
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: AppTheme.SECTION_GAP }) {
        HtmlAppBar({
          title: '从相册导入',
          subtitle: '选择图片或 PDF 进行识别',
          actionLabel: '···'
        })

        if (this.errorMessage.length > 0) {
          StatusBanner({
            label: '错误',
            title: '选择或识别失败',
            message: this.errorMessage,
            tone: 'danger'
          })
        }

        if (this.showFilters()) {
          this.filterTools()
        }

        if (this.stage === 'permission') {
          this.permissionStage()
        } else if (this.stage === 'imageSelected') {
          this.imageSelectedStage()
        } else if (this.stage === 'pdfSelected') {
          this.pdfSelectedStage()
        } else if (this.stage === 'pdfUploading') {
          this.pdfUploadingStage()
        } else if (this.stage === 'pdfRecognized' || this.stage === 'pdfPartial') {
          this.pdfResultStage()
        } else if (this.stage === 'pdfFailed' || this.stage === 'pdfEncrypted' || this.stage === 'pdfTooLarge' || this.stage === 'pdfTooManyPages' || this.stage === 'importFailure') {
          this.pdfFailureStageView()
        } else {
          this.emptySelectionStage()
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
