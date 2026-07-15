import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';

/**
 * AuthLegalComponents 承载登录前、账号与法务流程的原生 ArkUI 复刻组件。
 * 维护说明：组件只绘制固定 UI、脱敏提示和页面跳转，不读取或输出密码、Token、API Key、完整媒体 URI、objectKey 或 OCR 全文。
 */

export interface LegalArticleSection {
  title: string;
  body: string;
}

/**
 * AuthLogoLockup 绘制认证与法务页面的品牌锁定标识。
 * 维护边界：只展示固定品牌文案，不读取用户名、Token 或协议阅读状态。
 */
@Component
export struct AuthLogoLockup {
  compact: boolean = false;
  vertical: boolean = false;
  markSize: number = 0;

  build() {
    if (this.vertical) {
      Column({ space: 12 }) {
        AuthDocMark({ markSize: this.markSize > 0 ? this.markSize : 56, dark: true })
        Column({ space: 4 }) {
          Text('Harmony OCR')
            .fontSize(this.compact ? 24 : 28)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(this.compact ? 28 : 32)
            .maxLines(1)
            .textAlign(TextAlign.Center)
          Text('文档工作台')
            .fontSize(12)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(16)
            .maxLines(1)
            .textAlign(TextAlign.Center)
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    } else {
      Row({ space: 12 }) {
        AuthDocMark({ markSize: this.markSize > 0 ? this.markSize : (this.compact ? 40 : 44), dark: true })
        Column({ space: 4 }) {
          Text('Harmony OCR')
            .fontSize(this.compact ? 17 : 18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(22)
            .maxLines(1)
          Text('文档工作台')
            .fontSize(11)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(15)
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }
}

/**
 * AuthDocMark 绘制 Harmony OCR 文档标记。
 * 维护说明：组件只用几何形状表达品牌，不加载外部图片或用户文件。
 */
@Component
export struct AuthDocMark {
  markSize: number = 44;
  dark: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(this.markSize * 0.42)
        .height(this.markSize * 0.54)
        .border({ width: 1.6, color: this.dark ? AppTheme.COLOR_SURFACE : AppTheme.COLOR_BRAND })
        .borderRadius(4)
      Column()
        .width(this.markSize * 0.16)
        .height(this.markSize * 0.18)
        .backgroundColor(this.dark ? AppTheme.COLOR_DARK : AppTheme.COLOR_PAGE_DEEP)
        .border({ width: 1.1, color: this.dark ? AppTheme.COLOR_SURFACE : AppTheme.COLOR_BRAND })
        .position({ x: this.markSize * 0.56, y: this.markSize * 0.25 })
      Column()
        .width(this.markSize * 0.26)
        .height(1.4)
        .backgroundColor(this.dark ? AppTheme.COLOR_SURFACE : AppTheme.COLOR_BRAND)
        .position({ x: this.markSize * 0.36, y: this.markSize * 0.47 })
      Column()
        .width(this.markSize * 0.22)
        .height(1.4)
        .backgroundColor(this.dark ? AppTheme.COLOR_SURFACE : AppTheme.COLOR_BRAND)
        .position({ x: this.markSize * 0.36, y: this.markSize * 0.58 })
    }
    .width(this.markSize)
    .height(this.markSize)
    .backgroundColor(this.dark ? AppTheme.COLOR_DARK : AppTheme.COLOR_PAGE_DEEP)
    .border({ width: AppTheme.HAIRLINE, color: this.dark ? AppTheme.COLOR_DARK : AppTheme.COLOR_LINE })
    .borderRadius(Math.round(this.markSize * 0.32))
  }
}

/**
 * AuthDocumentVisual 绘制登录前文档识别示意图。
 * 安全边界：示意线条为静态 UI，不渲染真实 OCR 文本或用户图片。
 */
@Component
export struct AuthDocumentVisual {
  compact: boolean = false;
  @State private lineOne: number = 1;
  @State private lineTwo: number = 1;
  @State private lineThree: number = 1;
  @State private brandLine: number = 1;

  @Builder
  private line(widthValue: number, progress: number, brand: boolean = false) {
    Column()
      .width(widthValue * progress)
      .height(8)
      .backgroundColor(brand ? AppTheme.COLOR_BRAND : AppTheme.COLOR_PREVIEW_TEXT_LINE)
      .borderRadius(4)
      .opacity(progress > 0 ? 1 : 0)
  }

  build() {
    Stack() {
      Column()
        .width(this.compact ? 24 : 26)
        .height(this.compact ? 24 : 26)
        .border({ width: 2, color: AppTheme.COLOR_BRAND })
        .borderRadius({ topLeft: 10, topRight: 0, bottomLeft: 0, bottomRight: 0 })
        .position({ x: this.compact ? 18 : 24, y: this.compact ? 18 : 24 })
      Column()
        .width(this.compact ? 24 : 26)
        .height(this.compact ? 24 : 26)
        .border({ width: 2, color: AppTheme.COLOR_BRAND })
        .borderRadius({ topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 10 })
        .position({ x: this.compact ? 204 : 200, y: this.compact ? 178 : 188 })

      Column({ space: 12 }) {
        this.line(this.compact ? 74 : 76, this.lineOne)
        this.line(this.compact ? 100 : 102, this.lineTwo)
        this.line(this.compact ? 120 : 122, this.lineThree)
        this.line(this.compact ? 90 : 91, this.brandLine, true)
        Column().height(6)
        this.line(this.compact ? 100 : 102, this.lineTwo)
        this.line(this.compact ? 66 : 68, this.lineThree)
      }
      .width(this.compact ? 170 : 166)
      .height(this.compact ? 152 : 172)
      .padding({ left: 20, right: 20, top: 22, bottom: 18 })
      .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .position({ x: this.compact ? 40 : 42, y: this.compact ? 32 : 38 })
    }
    .width(this.compact ? 232 : 250)
    .height(this.compact ? 226 : 238)
    .backgroundColor(AppTheme.COLOR_PAGE_DEEP)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }
}

/**
 * AuthPageAppBar 提供认证、协议和隐私页面顶部栏。
 * 维护说明：只处理页面导航和右侧动作回调，不保存密码、Token 或正文输入。
 */
@Component
export struct AuthPageAppBar {
  title: string = '';
  subtitle: string = '';
  rightIcon: string = 'more';
  backToWelcome: boolean = true;
  onRightTap: () => void = () => {};
  @State private entered: boolean = false;
  @State private backPressed: boolean = false;
  @State private rightPressed: boolean = false;

  aboutToAppear(): void {
    // 中文说明：页面顶部栏使用短淡入位移，对齐 HTML page enter。
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.entered = true;
    });
  }

  build() {
    Row({ space: 12 }) {
      AuthIconButton({
        icon: 'back',
        pressed: this.backPressed,
        onPressChange: (value: boolean) => {
          this.backPressed = value;
        },
        onTap: () => {
          AppNavigator.back(this.getUIContext(), this.backToWelcome ? AppRoutes.WELCOME : AppRoutes.PROFILE);
        }
      })

      Column({ space: 3 }) {
        Text(this.title)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(25)
          .maxLines(1)
          .width('100%')
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(17)
            .maxLines(1)
            .width('100%')
        }
      }
      .layoutWeight(1)

      AuthIconButton({
        icon: this.rightIcon,
        pressed: this.rightPressed,
        onPressChange: (value: boolean) => {
          this.rightPressed = value;
        },
        onTap: () => this.onRightTap()
      })
    }
    .width('100%')
    .height(46)
    .alignItems(VerticalAlign.Center)
    .opacity(this.entered ? 1 : 0)
    .translate({ y: this.entered ? 0 : 10 })
  }
}

/**
 * AuthIconButton 绘制法务页面使用的轻量图标按钮。
 * 安全边界：回调只传点击动作，不携带用户输入、Token 或页面正文。
 */
@Component
export struct AuthIconButton {
  icon: string = 'more';
  pressed: boolean = false;
  onPressChange: (value: boolean) => void = () => {};
  onTap: () => void = () => {};

  build() {
    Button() {
      Stack({ alignContent: Alignment.Center }) {
        if (this.icon === 'back') {
          Column().width(12).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: -45 }).translate({ x: -2, y: -4 })
          Column().width(12).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: 45 }).translate({ x: -2, y: 4 })
        } else if (this.icon === 'shield') {
          Column().width(16).height(18).border({ width: 1.5, color: AppTheme.COLOR_TEXT }).borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 7, bottomRight: 7 })
          Column().width(6).height(1.5).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: 42 }).translate({ x: -3, y: 2 })
          Column().width(9).height(1.5).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: -42 }).translate({ x: 2, y: 1 })
        } else if (this.icon === 'check') {
          Column().width(8).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: 45 }).translate({ x: -4, y: 3 })
          Column().width(16).height(2).backgroundColor(AppTheme.COLOR_TEXT).rotate({ angle: -45 }).translate({ x: 3, y: -2 })
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
    .scale({ x: this.pressed ? AppMotion.PRESS_SCALE : 1, y: this.pressed ? AppMotion.PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      // 中文说明：按钮按压仅改变 scale，不记录点击参数或任何敏感输入。
      if (event.type === TouchType.Down) {
        this.onPressChange(true);
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.onPressChange(false);
      }
    })
    .onClick(() => this.onTap())
  }
}

/**
 * AuthPrimaryButton 统一认证和法务流程的主按钮样式。
 * 维护说明：组件只接收展示文案与点击回调，禁用态由业务页面负责判断。
 */
@Component
export struct AuthPrimaryButton {
  label: string = '';
  primary: boolean = true;
  danger: boolean = false;
  @Prop enabledState: boolean = true;
  onTap: () => void = () => {};
  @State private pressed: boolean = false;

  build() {
    Button(this.label)
      .width('100%')
      .height(AppTheme.BUTTON_HEIGHT)
      .type(ButtonType.Normal)
      .fontSize(14)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.primary ? AppTheme.COLOR_TEXT_INVERSE : (this.danger ? AppTheme.COLOR_DANGER : AppTheme.COLOR_BRAND))
      .backgroundColor(this.primary ? (this.danger ? AppTheme.COLOR_DANGER : AppTheme.COLOR_BRAND) : AppTheme.COLOR_PAGE_DEEP)
      .border({ width: AppTheme.HAIRLINE, color: this.primary ? (this.danger ? AppTheme.COLOR_DANGER : AppTheme.COLOR_BRAND_DARK) : AppTheme.COLOR_LINE })
      .borderRadius(AppTheme.RADIUS_CONTROL)
      .enabled(this.enabledState)
      .opacity(this.enabledState ? 1 : 0.48)
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
 * AuthTextButton 统一认证流程中的文本按钮。
 * 安全边界：只触发页面回调，不读取输入框内容或会话凭证。
 */
@Component
export struct AuthTextButton {
  @Prop label: string = '';
  onTap: () => void = () => {};

  build() {
    Button(this.label)
      .height(32)
      .type(ButtonType.Normal)
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(AppTheme.COLOR_BRAND)
      .padding({ left: 2, right: 2 })
      .backgroundColor(AppTheme.COLOR_TRANSPARENT)
      .onClick(() => this.onTap())
  }
}

/**
 * AuthCheckBox 绘制协议勾选控件。
 * 维护说明：只回传布尔状态，协议同意的持久化或接口提交由业务页面完成。
 */
@Component
export struct AuthCheckBox {
  @Prop checked: boolean = false;
  onToggle: (checked: boolean) => void = () => {};

  build() {
    Button() {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(9)
          .height(2)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
          .borderRadius(1)
          .rotate({ angle: 45 })
          .translate({ x: -3, y: 3 })
          .opacity(this.checked ? 1 : 0)
        Column()
          .width(15)
          .height(2)
          .backgroundColor(AppTheme.COLOR_TEXT_INVERSE)
          .borderRadius(1)
          .rotate({ angle: -45 })
          .translate({ x: 4, y: -1 })
          .opacity(this.checked ? 1 : 0)
      }
      .width(22)
      .height(22)
      .backgroundColor(this.checked ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_ELEVATED)
      .border({ width: AppTheme.HAIRLINE, color: this.checked ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(7)
      .scale({ x: this.checked ? 1.02 : 1, y: this.checked ? 1.02 : 1 })
      .animation({ duration: 180, curve: Curve.EaseOut })
    }
    .width(44)
    .height(44)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_TRANSPARENT)
    .padding(0)
    .onClick(() => {
      // 中文说明：保留 44px 触控区，视觉盒子按 HTML 参考稿收敛为 22px 暖纸面 checkbox。
      this.onToggle(!this.checked);
    })
  }
}

/**
 * AuthConsentSheet 展示协议与隐私确认弹层。
 * 安全边界：弹层只承载固定提示和回调，不保存用户凭据、OCR 文本或第三方服务配置。
 */
@Component
export struct AuthConsentSheet {
  @Prop visible: boolean = false;
  title: string = '用户协议与隐私政策';
  body: string = '请先阅读并同意《用户协议》和《隐私政策》，以继续使用 Harmony OCR。';
  okLabel: string = '同意并继续';
  cancelLabel: string = '不同意';
  danger: boolean = false;
  onCancel: () => void = () => {};
  onOk: () => void = () => {};

  build() {
    if (this.visible) {
      Stack({ alignContent: Alignment.Bottom }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(23, 20, 17, 0.42)')
          .opacity(this.visible ? 1 : 0)
          .animation({ duration: 180, curve: Curve.EaseOut })
          .onClick(() => this.onCancel())

        Column({ space: 14 }) {
          Text(this.title)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(25)
            .width('100%')
          Text(this.body)
            .fontSize(14)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(22)
            .width('100%')

          Row({ space: 10 }) {
            AuthPrimaryButton({ label: this.cancelLabel, primary: false, onTap: () => this.onCancel() })
              .layoutWeight(1)
            AuthPrimaryButton({ label: this.okLabel, primary: true, danger: this.danger, onTap: () => this.onOk() })
              .layoutWeight(1)
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 18, right: 18, top: 18, bottom: 18 })
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)
        .margin({ left: 18, right: 18, bottom: 18 })
        .translate({ y: this.visible ? 0 : 16 })
        .scale({ x: this.visible ? 1 : 0.98, y: this.visible ? 1 : 0.98 })
        .animation({ duration: 220, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .zIndex(20)
    }
  }
}
