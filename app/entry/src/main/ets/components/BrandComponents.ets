import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';

export type StatusTone = 'info' | 'success' | 'warning' | 'danger' | 'neutral';

/**
 * BrandHeader 提供 Harmony OCR 的统一品牌页头。
 * 维护边界：组件只展示固定文案和视觉符号，不读取账号、Token、图片 URI、OCR 全文或对象存储信息。
 */
@Component
export struct BrandHeader {
  title: string = '';
  subtitle: string = '';
  eyebrow: string = 'Harmony OCR';
  compact: boolean = false;
  @State private entered: boolean = false;

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: AppMotion.DURATION_APPBAR_ENTER, curve: Curve.EaseOut }, () => {
      this.entered = true;
    });
  }

  build() {
    Column({ space: this.compact ? 6 : 8 }) {
      Row({ space: 10 }) {
        Column()
          .width(16)
          .height(16)
          .border({ width: 2, color: AppTheme.COLOR_BRAND })
          .borderRadius(4)
          .backgroundColor(AppTheme.COLOR_TRANSPARENT)

        Text(this.eyebrow)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .layoutWeight(1)

        Text('文档工作流')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
      }
      .width('100%')

      Text(this.title)
        .fontSize(this.compact ? AppTheme.FONT_PAGE_TITLE : 26)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(this.compact ? AppTheme.LINE_PAGE_TITLE : 31)
        .width('100%')

      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(AppTheme.LINE_BODY)
          .width('100%')
      }
    }
    .width('100%')
    .padding({ top: this.compact ? 4 : 0, bottom: this.compact ? 4 : 8 })
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }
}

/**
 * StatusBanner 统一呈现流程状态、能力边界和错误提示。
 * 维护边界：调用方只传入脱敏文案，组件本身不拼接业务标识或敏感数据。
 */
@Component
export struct StatusBanner {
  @Prop label: string = 'STATE';
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop tone: StatusTone = 'info';
  @State private entered: boolean = false;

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, () => {
      this.entered = true;
    });
  }

  private toneColor(): string {
    if (this.tone === 'success') {
      return AppTheme.COLOR_SUCCESS;
    }
    if (this.tone === 'warning') {
      return AppTheme.COLOR_WARNING;
    }
    if (this.tone === 'danger') {
      return AppTheme.COLOR_DANGER;
    }
    if (this.tone === 'neutral') {
      return AppTheme.COLOR_TEXT_SUBTLE;
    }
    return AppTheme.COLOR_ACTION;
  }

  private toneBackground(): string {
    if (this.tone === 'success') {
      return AppTheme.COLOR_SUCCESS_BG;
    }
    if (this.tone === 'warning') {
      return AppTheme.COLOR_WARNING_BG;
    }
    if (this.tone === 'danger') {
      return AppTheme.COLOR_DANGER_BG;
    }
    if (this.tone === 'neutral') {
      return AppTheme.COLOR_NEUTRAL_BG;
    }
    return AppTheme.COLOR_INFO_BG;
  }

  private toneBorder(): string {
    if (this.tone === 'danger') {
      return AppTheme.COLOR_DANGER_LINE;
    }
    if (this.tone === 'warning') {
      return AppTheme.COLOR_WARNING_LINE;
    }
    return AppTheme.COLOR_LINE_SOFT;
  }

  private displayLabel(): string {
    const normalized = this.label.trim().toUpperCase();
    if (normalized === 'ERROR') {
      return '错误';
    }
    if (normalized === 'SYNC' || normalized === 'LOAD' || normalized === 'LOADING') {
      return '同步';
    }
    if (normalized === 'INFO' || normalized === 'NOTICE') {
      return '提示';
    }
    if (normalized === 'DONE') {
      return '完成';
    }
    if (normalized === 'EMPTY') {
      return '空';
    }
    if (normalized === 'DOWNLOAD') {
      return '下载';
    }
    if (normalized === 'OPEN') {
      return '打开';
    }
    if (normalized === 'DOWNGRADE') {
      return '降级';
    }
    return this.label;
  }

  build() {
    Row({ space: 12 }) {
      Column({ space: 8 }) {
        Row({ space: 10 }) {
        Text(this.displayLabel())
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.toneColor())
          .padding({ left: 0, right: 2, top: 1, bottom: 1 })

        Text(this.title)
          .fontSize(AppTheme.FONT_BODY)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.COLOR_TEXT)
          .layoutWeight(1)
        }
        .width('100%')

        if (this.message.length > 0) {
          Text(this.message)
            .fontSize(AppTheme.FONT_META)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
        }
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 11, bottom: 11 })
    .backgroundColor(this.toneBackground())
    .border({ width: AppTheme.HAIRLINE, color: this.tone === 'neutral' ? AppTheme.COLOR_LINE_SOFT : this.toneBorder() })
    .borderRadius(AppTheme.RADIUS_CARD)
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : AppMotion.SUBTLE_OFFSET_Y })
  }
}

/**
 * OcrScanBadge 提供轻量 OCR 扫描视觉符号，用于增强产品识别度。
 * 维护边界：该组件只是装饰性工作台符号，不承诺 OCR 能力状态。
 */
@Component
export struct OcrScanBadge {
  label: string = 'SCAN';

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(AppTheme.COLOR_SCAN_BG)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })

      Column()
        .width('82%')
        .height(68)
        .border({ width: 2, color: AppTheme.COLOR_SCAN_LINE, style: BorderStyle.Dashed })
        .backgroundColor(AppTheme.COLOR_SCAN_OVERLAY)

      Column()
        .width('72%')
        .height(2)
        .backgroundColor(AppTheme.COLOR_SCAN_LINE)
        .opacity(0.82)

      Text(this.label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_BRAND)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .position({ x: 14, y: 14 })
    }
    .width('100%')
    .height(112)
  }
}

/**
 * StatusChip 提供统一的轻量标签，用于来源、状态、语言和时间等非敏感元信息。
 */
@Component
export struct StatusChip {
  label: string = '';
  tone: StatusTone = 'neutral';

  private toneColor(): string {
    if (this.tone === 'success') {
      return AppTheme.COLOR_SUCCESS;
    }
    if (this.tone === 'warning') {
      return AppTheme.COLOR_WARNING;
    }
    if (this.tone === 'danger') {
      return AppTheme.COLOR_DANGER;
    }
    if (this.tone === 'info') {
      return AppTheme.COLOR_ACTION;
    }
    return AppTheme.COLOR_TEXT_SUBTLE;
  }

  private toneBackground(): string {
    if (this.tone === 'success') {
      return AppTheme.COLOR_SUCCESS_BG;
    }
    if (this.tone === 'warning') {
      return AppTheme.COLOR_WARNING_BG;
    }
    if (this.tone === 'danger') {
      return AppTheme.COLOR_DANGER_BG;
    }
    if (this.tone === 'info') {
      return AppTheme.COLOR_INFO_BG;
    }
    return AppTheme.COLOR_NEUTRAL_BG;
  }

  build() {
    Text(this.label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.toneColor())
      .height(28)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.toneBackground())
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
  }
}

/**
 * SectionHeader 统一页面内分区标题。
 * 维护边界：只承载标题和辅助说明，不读取业务数据，避免各页面重复堆叠大标题和说明文本。
 */
@Component
export struct SectionHeader {
  title: string = '';
  description: string = '';

  build() {
    Column({ space: 6 }) {
      Text(this.title)
        .fontSize(AppTheme.FONT_SECTION_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(AppTheme.LINE_SECTION_TITLE)
        .width('100%')

      if (this.description.length > 0) {
        Text(this.description)
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
      }
    }
    .width('100%')
  }
}

/**
 * TextActionButton 提供克制的文本操作按钮样式。
 * 维护边界：按钮只负责视觉一致性，具体业务操作仍由调用页的 onClick 回调控制。
 */
@Component
export struct TextActionButton {
  @Prop label: string = '';
  primary: boolean = false;
  danger: boolean = false;
  @Prop enabledState: boolean = true;
  onTap: () => void = () => {};
  @State private pressed: boolean = false;

  private textColor(): string {
    if (this.primary) {
      return AppTheme.COLOR_TEXT_INVERSE;
    }
    if (this.danger) {
      return AppTheme.COLOR_DANGER;
    }
    return AppTheme.COLOR_BRAND;
  }

  private actionBackgroundColor(): string {
    if (this.danger && this.primary) {
      return AppTheme.COLOR_DANGER;
    }
    if (this.primary) {
      return AppTheme.COLOR_BRAND;
    }
    if (this.danger) {
      return AppTheme.COLOR_DANGER_BG;
    }
    return AppTheme.COLOR_PAGE_DEEP;
  }

  private actionBorderColor(): string {
    if (this.danger && this.primary) {
      return AppTheme.COLOR_DANGER;
    }
    if (this.primary) {
      return AppTheme.COLOR_BRAND;
    }
    if (this.danger) {
      return AppTheme.COLOR_DANGER_LINE;
    }
    return AppTheme.COLOR_LINE_SOFT;
  }

  build() {
    Button(this.label)
      .width('100%')
      .height(this.primary ? AppTheme.BUTTON_HEIGHT : AppTheme.BUTTON_SECONDARY_HEIGHT)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_BUTTON)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.textColor())
      .backgroundColor(this.actionBackgroundColor())
      .border({ width: AppTheme.HAIRLINE, color: this.actionBorderColor() })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(this.enabledState)
      .scale({ x: this.pressed ? AppMotion.PRESS_SCALE : 1, y: this.pressed ? AppMotion.PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        if (!this.enabledState) {
          return;
        }
        if (event.type === TouchType.Down) {
          this.pressed = true;
        }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => this.onTap())
  }
}

/**
 * HtmlCompactActionButton 对齐 HTML 原型中列表行里的紧凑操作按钮。
 * 维护边界：组件只提供 34px 行内按钮视觉、按压动效和 enabled 状态，不读取记录内容、Token、文件路径或 OCR 全文。
 */
@Component
export struct HtmlCompactActionButton {
  @Prop label: string = '';
  primary: boolean = false;
  danger: boolean = false;
  @Prop enabledState: boolean = true;
  onTap: () => void = () => {};
  @State private pressed: boolean = false;

  private textColor(): string {
    if (this.primary) {
      return AppTheme.COLOR_TEXT_INVERSE;
    }
    if (this.danger) {
      return AppTheme.COLOR_DANGER;
    }
    return AppTheme.COLOR_BRAND;
  }

  private buttonBackground(): string {
    if (this.primary) {
      return AppTheme.COLOR_BRAND;
    }
    if (this.danger) {
      return AppTheme.COLOR_DANGER_BG;
    }
    return AppTheme.COLOR_TRANSPARENT;
  }

  private buttonBorder(): string {
    if (this.primary) {
      return AppTheme.COLOR_BRAND;
    }
    if (this.danger) {
      return AppTheme.COLOR_DANGER_LINE;
    }
    return AppTheme.COLOR_LINE_SOFT;
  }

  build() {
    Button(this.label)
      .width('100%')
      .height(34)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_META)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.textColor())
      .backgroundColor(this.buttonBackground())
      .border({ width: AppTheme.HAIRLINE, color: this.buttonBorder() })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(this.enabledState)
      .scale({ x: this.pressed ? AppMotion.PRESS_SCALE : 1, y: this.pressed ? AppMotion.PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        // 行内按钮使用轻量按压反馈，避免记录列表回到旧式静态小按钮。
        if (!this.enabledState) {
          return;
        }
        if (event.type === TouchType.Down) {
          this.pressed = true;
        }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => this.onTap())
  }
}

/**
 * SettingActionRow 提供“我的/设置/法律/支持”类入口的统一行样式。
 * 维护边界：组件只渲染标题、说明和回调，不读取任何账号、Token、OCR 文本或图片信息。
 */
@Component
export struct SettingActionRow {
  title: string = '';
  description: string = '';
  danger: boolean = false;
  @Prop enabledState: boolean = true;
  onTap: () => void = () => {};
  @State private pressed: boolean = false;

  build() {
    Button() {
      Row({ space: 12 }) {
        Column()
          .width(38)
          .height(44)
          .backgroundColor(this.danger ? AppTheme.COLOR_DANGER_BG : AppTheme.COLOR_SURFACE_SOFT)
          .border({ width: AppTheme.HAIRLINE, color: this.danger ? AppTheme.COLOR_DANGER_LINE : AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_CONTROL)

        Column({ space: 3 }) {
          Text(this.title)
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.danger ? AppTheme.COLOR_DANGER : AppTheme.COLOR_TEXT)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')

          if (this.description.length > 0) {
            Text(this.description)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
              .lineHeight(AppTheme.LINE_CAPTION)
              .width('100%')
              .maxLines(1)
          }
        }
        .layoutWeight(1)

        Text('›')
          .fontSize(20)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(66)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_TRANSPARENT)
    .enabled(this.enabledState)
    .scale({ x: this.pressed ? AppMotion.PRESS_SCALE : 1, y: this.pressed ? AppMotion.PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (!this.enabledState) {
        return;
      }
      if (event.type === TouchType.Down) {
        this.pressed = true;
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.enabledState) {
        this.onTap();
      }
    })
  }
}

/**
 * FilterSummaryBar 汇总当前文档库筛选条件。
 * 维护边界：组件只展示调用方传入的脱敏摘要和清空回调，不读取 records、标签、OCR 文本或账号信息。
 */
@Component
export struct FilterSummaryBar {
  summary: string = '全部记录';
  active: boolean = false;
  onClear: () => void = () => {};
  @State private entered: boolean = false;

  aboutToAppear(): void {
    this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, () => {
      this.entered = true;
    });
  }

  build() {
    Row({ space: 10 }) {
      Column()
        .width(3)
        .height(32)
        .backgroundColor(this.active ? AppTheme.COLOR_ACCENT : AppTheme.COLOR_ACTION)
        .borderRadius(2)

      Column({ space: 2 }) {
        Text(this.active ? '当前筛选' : '文档库视图')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')

        Text(this.summary)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
          .maxLines(2)
      }
      .layoutWeight(1)

      if (this.active) {
        Button('清空')
          .height(34)
          .type(ButtonType.Normal)
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_BRAND)
          .backgroundColor(AppTheme.COLOR_TRANSPARENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .onClick(() => this.onClear())
      }
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 11, bottom: 11 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CARD)
    .alignItems(VerticalAlign.Center)
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : AppMotion.SUBTLE_OFFSET_Y })
  }
}

export type HtmlBadgeTone = 'neutral' | 'ok' | 'warn' | 'danger' | 'dark';

/**
 * HtmlStatusBar 保留前摄安全区高度，不绘制虚构时间、网络、电量或设备状态。
 * 维护边界：这里只做与页面背景同色的占位，避免页面内容顶到前摄区域。
 */
@Component
export struct HtmlStatusBar {
  build() {
    // 只保留前摄安全区占位，不绘制虚构系统状态。
    Column()
    .width('100%')
    .height(AppTheme.STATUS_SAFE_HEIGHT)
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}

/**
 * HtmlAppBar 对齐 HTML 原型的紧凑顶部栏。
 * 维护边界：只展示标题、副标题和固定操作符号，不读取账号、Token、OCR 全文或文件 URI。
 */
@Component
export struct HtmlAppBar {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop showBackButton: boolean = false;
  actionLabel: string = '...';
  actionIcon: string = '';
  onBack: () => void = () => {};
  onAction: () => void = () => {};
  @State private entered: boolean = false;
  @State private backPressed: boolean = false;
  @State private actionPressed: boolean = false;

  aboutToAppear(): void {
    // 顶部栏进入动效与 HTML 原型一致：短时淡入并从轻微 y 位移回到原位。
    this.getUIContext().animateTo({ duration: AppMotion.DURATION_APPBAR_ENTER, curve: Curve.EaseOut }, () => {
      this.entered = true;
    });
  }

  build() {
    Row({ space: 12 }) {
      if (this.showBackButton) {
        Button() {
          Stack({ alignContent: Alignment.Center }) {
            // 返回按钮只渲染轻量箭头，不承载任何页面状态，避免与右侧操作按钮混淆。
            Column().width(12).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: -45 }).translate({ x: -2, y: -4 })
            Column().width(12).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: 45 }).translate({ x: -2, y: 4 })
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
          .scale({ x: this.backPressed ? AppMotion.PRESS_SCALE : 1, y: this.backPressed ? AppMotion.PRESS_SCALE : 1 })
          .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.backPressed = true;
            }
            if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.backPressed = false;
            }
          })
          .onClick(() => this.onBack())
      }

      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(AppTheme.FONT_PAGE_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_PAGE_TITLE)
          .maxLines(1)
          .width('100%')

        Text(this.subtitle)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)

      Button() {
        Stack({ alignContent: Alignment.Center }) {
          if (this.actionIcon === 'shield') {
            // 顶部盾牌图标用于 Admin 审计入口，只绘制安全状态符号，不读取任何管理数据。
            Column()
              .width(15)
              .height(17)
              .border({ width: 1.4, color: AppTheme.COLOR_TEXT })
              .borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 7, bottomRight: 7 })
              .scale({ x: 0.9, y: 1 })
            Column()
              .width(5)
              .height(1.4)
              .backgroundColor(AppTheme.COLOR_TEXT)
              .rotate({ angle: 42 })
              .translate({ x: -3, y: 2 })
            Column()
              .width(8)
              .height(1.4)
              .backgroundColor(AppTheme.COLOR_TEXT)
              .rotate({ angle: -42 })
              .translate({ x: 2, y: 1 })
          } else if (this.actionIcon === 'sun') {
            // 额度页使用原生齿/日形图标贴近 HTML 顶部操作符号。
            Column()
              .width(7)
              .height(7)
              .border({ width: 1.4, color: AppTheme.COLOR_TEXT })
              .borderRadius(4)
            Column().width(1.6).height(16).backgroundColor(AppTheme.COLOR_TEXT)
            Column().width(16).height(1.6).backgroundColor(AppTheme.COLOR_TEXT)
            Column().width(1.6).height(16).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: 45 })
            Column().width(16).height(1.6).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: 45 })
          } else if (this.actionIcon === 'key') {
            // Provider 连接页使用钥匙形图标，避免继续显示不稳定的字符点号。
            Column()
              .width(7)
              .height(7)
              .border({ width: 1.4, color: AppTheme.COLOR_TEXT })
              .borderRadius(4)
              .translate({ x: -5 })
            Column()
              .width(13)
              .height(1.6)
              .backgroundColor(AppTheme.COLOR_TEXT)
              .translate({ x: 4 })
            Column()
              .width(1.6)
              .height(5)
              .backgroundColor(AppTheme.COLOR_TEXT)
              .translate({ x: 9, y: 3 })
          } else if (this.actionIcon === 'search') {
            // 搜索入口使用几何放大镜，避免设备字体把 HTML 原型符号渲染成不稳定 glyph。
            Column()
              .width(13)
              .height(13)
              .border({ width: 1.8, color: AppTheme.COLOR_TEXT })
              .borderRadius(7)
              .translate({ x: -2, y: -2 })
            Column()
              .width(8)
              .height(1.8)
              .backgroundColor(AppTheme.COLOR_TEXT)
              .borderRadius(1)
              .rotate({ angle: 45 })
              .translate({ x: 6, y: 6 })
          } else {
            Text(this.actionLabel)
              .fontSize(AppTheme.FONT_META)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.COLOR_TEXT)
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
        .scale({ x: this.actionPressed ? AppMotion.PRESS_SCALE : 1, y: this.actionPressed ? AppMotion.PRESS_SCALE : 1 })
        .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          // 顶部栏操作按钮使用原型一致的轻压缩反馈，不改变实际路由或业务行为。
          if (event.type === TouchType.Down) {
            this.actionPressed = true;
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.actionPressed = false;
          }
        })
        .onClick(() => this.onAction())
    }
    .width('100%')
    .height(46)
    .padding({ left: 2, right: 0, top: 1, bottom: 1 })
    .alignItems(VerticalAlign.Center)
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : AppMotion.SUBTLE_OFFSET_Y })
  }
}

/**
 * HtmlSectionHead 复刻 HTML `.section-head` 的紧凑标题行。
 * 说明：右侧文本只承载脱敏状态或入口提示，避免把敏感业务值写进日志或截图说明。
 */
@Component
export struct HtmlSectionHead {
  @Prop title: string = '';
  @Prop meta: string = '';
  actionLabel: string = '';
  onAction: () => void = () => {};

  build() {
    Row({ space: 10 }) {
      Text(this.title)
        .fontSize(AppTheme.FONT_CARD_TITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .layoutWeight(1)
        .maxLines(1)

      if (this.actionLabel.length > 0) {
        Button(this.actionLabel)
          .height(30)
          .type(ButtonType.Normal)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_BRAND)
          .backgroundColor(AppTheme.COLOR_TRANSPARENT)
          .padding({ left: 8, right: 8 })
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_BADGE)
          .onClick(() => this.onAction())
      } else if (this.meta.length > 0) {
        Text(this.meta)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
      }
    }
    .width('100%')
    .margin({ top: 4, bottom: 0 })
    .alignItems(VerticalAlign.Center)
  }
}

/**
 * HtmlBadge 是 HTML `.badge` 的 ArkUI 等价组件，用于紧凑状态标签。
 */
@Component
export struct HtmlBadge {
  @Prop label: string = '';
  @Prop tone: HtmlBadgeTone = 'neutral';

  private color(): string {
    if (this.tone === 'ok') {
      return AppTheme.COLOR_SUCCESS;
    }
    if (this.tone === 'warn') {
      return AppTheme.COLOR_WARNING;
    }
    if (this.tone === 'danger') {
      return AppTheme.COLOR_DANGER;
    }
    if (this.tone === 'dark') {
      return AppTheme.COLOR_TEXT;
    }
    return AppTheme.COLOR_TEXT_SUBTLE;
  }

  private bg(): string {
    if (this.tone === 'ok') {
      return AppTheme.COLOR_SUCCESS_BG;
    }
    if (this.tone === 'warn') {
      return AppTheme.COLOR_WARNING_BG;
    }
    if (this.tone === 'danger') {
      return AppTheme.COLOR_DANGER_BG;
    }
    if (this.tone === 'dark') {
      return AppTheme.COLOR_TEXT;
    }
    return AppTheme.COLOR_NEUTRAL_BG;
  }

  build() {
    Text(this.label)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : this.color())
      .height(28)
      .padding({ left: 10, right: 10 })
      .backgroundColor(this.bg())
      .border({ width: AppTheme.HAIRLINE, color: this.tone === 'dark' ? AppTheme.COLOR_TEXT : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
  }
}

/**
 * HtmlToolChip 对齐 HTML `.tool-chip`，用于横向快捷动作。
 */
@Component
export struct HtmlToolChip {
  label: string = '';
  primary: boolean = false;
  @Prop enabledState: boolean = true;
  onTap: () => void = () => {};
  @State private pressed: boolean = false;

  build() {
    Button(this.label)
      .height(38)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.enabledState ? (this.primary ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_TEXT_MUTED) : AppTheme.COLOR_TEXT_SUBTLE)
      .backgroundColor(this.enabledState ? (this.primary ? AppTheme.COLOR_BRAND_SOFT : AppTheme.COLOR_SURFACE_ELEVATED) : AppTheme.COLOR_NEUTRAL_BG)
      .padding({ left: 12, right: 12 })
      .border({ width: AppTheme.HAIRLINE, color: this.enabledState ? (this.primary ? AppTheme.COLOR_ACCENT_SOFT : AppTheme.COLOR_LINE_SOFT) : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .scale({ x: this.enabledState && this.pressed ? AppMotion.PRESS_SCALE : 1, y: this.enabledState && this.pressed ? AppMotion.PRESS_SCALE : 1 })
      .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
      .onTouch((event: TouchEvent) => {
        if (!this.enabledState) {
          this.pressed = false;
          return;
        }
        if (event.type === TouchType.Down) {
          this.pressed = true;
        }
        if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressed = false;
        }
      })
      .onClick(() => this.onTap())
      .enabled(this.enabledState)
  }
}

/**
 * HtmlFileMark 复刻 HTML 列表中的固定文件标识位。
 * 说明：label 只决定装饰性原生几何图形，不读取或推断任何真实文件、密钥或账号数据。
 */
@Component
export struct HtmlFileMark {
  label: string = 'DOC';
  tone: HtmlBadgeTone = 'neutral';

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.label === 'AI') {
        // AI Provider 行使用钥匙符号，和 HTML Mine / BYOK 入口的服务连接含义保持一致。
        Column()
          .width(7)
          .height(7)
          .border({ width: 1.5, color: this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND })
          .borderRadius(4)
          .translate({ x: -5 })
        Column()
          .width(14)
          .height(1.6)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .translate({ x: 4 })
        Column()
          .width(1.6)
          .height(5)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .translate({ x: 9, y: 3 })
      } else if (this.label === '导出' || this.label === 'OUT') {
        // 导出中心使用托盘上箭头，避免旧版三字母缩写带来的工程占位感。
        Column()
          .width(16)
          .height(8)
          .border({ width: 1.5, color: this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND })
          .borderRadius({ topLeft: 1, topRight: 1, bottomLeft: 3, bottomRight: 3 })
          .translate({ y: 5 })
        Column()
          .width(1.6)
          .height(15)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .translate({ y: -2 })
        Column()
          .width(8)
          .height(1.6)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .rotate({ angle: 45 })
          .translate({ x: -3, y: -7 })
        Column()
          .width(8)
          .height(1.6)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .rotate({ angle: -45 })
          .translate({ x: 3, y: -7 })
      } else if (this.label === 'PRO') {
        // 会员额度行使用票据/额度单符号，贴近 HTML 参考图中的 plan 入口。
        Column()
          .width(13)
          .height(17)
          .border({ width: 1.5, color: this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND })
          .borderRadius(2)
        Column()
          .width(7)
          .height(1.5)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .translate({ y: -3 })
        Column()
          .width(7)
          .height(1.5)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .translate({ y: 2 })
      } else if (this.label === 'ADM') {
        // Admin 入口使用盾牌，表达管理员入口但不暴露任何权限或账号状态。
        Column()
          .width(17)
          .height(18)
          .border({ width: 1.5, color: this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND })
          .borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 7, bottomRight: 7 })
          .scale({ x: 0.92, y: 1 })
        Column()
          .width(6)
          .height(1.5)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .rotate({ angle: 42 })
          .translate({ x: -3, y: 2 })
        Column()
          .width(9)
          .height(1.5)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .rotate({ angle: -42 })
          .translate({ x: 2, y: 1 })
      } else {
        // 默认行首标记使用文档线稿而不是 PDF/IMG 文本，贴近 HTML 参考图并避免工程标签感。
        Column()
          .width(12)
          .height(16)
          .border({ width: 1.5, color: this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND })
          .borderRadius(2)
        Column()
          .width(4)
          .height(5)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_DARK : AppTheme.COLOR_PAGE_DEEP)
          .border({ width: 1, color: this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND })
          .position({ x: 24, y: 10 })
        // 中文说明：用两条短线模拟 HTML file SVG 的文档内容线，避免行首图标只剩空白纸张轮廓。
        Column()
          .width(6)
          .height(1.2)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .position({ x: 16, y: 19 })
        Column()
          .width(5)
          .height(1.2)
          .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
          .position({ x: 16, y: 23 })
      }
    }
    .width(38)
    .height(44)
    .backgroundColor(this.tone === 'dark' ? AppTheme.COLOR_DARK : AppTheme.COLOR_SURFACE_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }
}

/**
 * HtmlListRow 对齐 HTML `.row`：文件标识、主文本、元信息和右侧 badge。
 */
@Component
export struct HtmlListRow {
  title: string = '';
  meta: string = '';
  mark: string = 'DOC';
  badge: string = '';
  tone: HtmlBadgeTone = 'neutral';
  index: number = 0;
  onTap: () => void = () => {};
  @Prop enabledState: boolean = true;
  @State private entered: boolean = false;
  @State private pressed: boolean = false;

  aboutToAppear(): void {
    // 行式信息采用短延迟 stagger，模拟 HTML row reveal，但只影响展示层。
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, () => {
        this.entered = true;
      });
    }, this.index * AppMotion.STAGGER_ROW_MS);
  }

  build() {
    Button() {
      Row({ space: 10 }) {
        HtmlFileMark({ label: this.mark, tone: 'neutral' })

        Column({ space: 3 }) {
          Text(this.title)
            .fontSize(AppTheme.FONT_META)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(AppTheme.LINE_META)
            .maxLines(1)
            .width('100%')
          Text(this.meta)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .maxLines(1)
            .width('100%')
        }
        .layoutWeight(1)

        if (this.badge.length > 0) {
          HtmlBadge({ label: this.badge, tone: this.tone })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(66)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_TRANSPARENT)
    .padding({ left: 0, right: 0, top: 2, bottom: 2 })
    .enabled(this.enabledState)
    .opacity(this.enabledState ? (this.entered ? 1 : 0) : 0.52)
    .translate({ y: this.entered ? 0 : AppMotion.SUBTLE_OFFSET_Y })
    .scale({ x: this.enabledState && this.pressed ? AppMotion.PRESS_SCALE : 1, y: this.enabledState && this.pressed ? AppMotion.PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      // 列表行保持 HTML 原型的轻量按压反馈，避免旧 UI 的静态卡片感。
      if (event.type === TouchType.Down) {
        this.pressed = true;
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      if (this.enabledState) {
        this.onTap();
      }
    })
  }
}

/**
 * HtmlToast 对齐 HTML 原型底部 toast：深色单层 surface、轻微 y 位移和 opacity 过渡。
 * 维护边界：调用方只传入脱敏短消息；组件不读取 OCR 全文、Token、API Key、文件路径或 objectKey。
 */
@Component
export struct HtmlToast {
  message: string = '';
  visible: boolean = false;

  build() {
    if (this.visible && this.message.length > 0) {
      Text(this.message)
        .width('100%')
        .height(44)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_SURFACE)
        .lineHeight(AppTheme.LINE_META)
        .padding({ left: 14, right: 14, top: 12, bottom: 12 })
        .backgroundColor(AppTheme.COLOR_DARK)
        .borderRadius(AppTheme.RADIUS_CONTROL)
        .opacity(this.visible ? 1 : 0)
        .translate({ y: this.visible ? 0 : 14 })
        .animation({ duration: AppMotion.DURATION_TOAST, curve: Curve.EaseOut })
    }
  }
}
