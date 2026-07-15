import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthDocMark, AuthPrimaryButton } from '../components/AuthLegalComponents';

/**
 * LoginSuccessPage 复刻 HTML Login Success 过渡页。
 * 维护说明：页面只展示登录后过渡状态，不输出 Token、账号详情、导出路径或 AI Provider 信息。
 */
@Entry
@Component
struct LoginSuccessPage {
  @State private entered: boolean = false;
  @State private progress: number = 0;

  aboutToAppear(): void {
    this.startMotion();
  }

  /**
   * 成功图标和进度条采用 300-500ms tween；完成后仍由用户或脚本进入首页，便于截图验证过渡页。
   */
  private startMotion(): void {
    this.getUIContext().animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
      this.entered = true;
    });
    this.getUIContext().animateTo({ duration: 460, curve: Curve.EaseOut }, () => {
      this.progress = 1;
    });
  }

  build() {
    Column({ space: 16 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(232)
          .height(232)
          .backgroundColor(AppTheme.COLOR_BRAND_SOFT)
          .borderRadius(116)
          .opacity(0.55)
        Column({ space: 12 }) {
          AuthDocMark({ markSize: 48, dark: true })
            .opacity(this.entered ? 1 : 0)
            .scale({ x: this.entered ? 1 : 0.94, y: this.entered ? 1 : 0.94 })

          Text('登录成功')
            .fontSize(21)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(26)
          Text('正在进入你的文档首页')
            .fontSize(15)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(22)

          Column() {
            Column()
              .width(`${Math.round(this.progress * 100)}%`)
              .height(5)
              .backgroundColor(AppTheme.COLOR_BRAND)
              .borderRadius(3)
          }
          .width(178)
          .height(5)
          .backgroundColor(AppTheme.COLOR_LINE_SOFT)
          .borderRadius(3)
          .margin({ top: 2 })
        }
        .width(210)
        .height(210)
        .padding(18)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)
      }
      .width('100%')
      .height(330)

      Column({ space: 6 }) {
        Text('准备同步')
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(20)
          .width('100%')
        Text('最近 OCR 记录、导出队列与 AI 服务连接状态将按账号配置加载。')
          .fontSize(15)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(24)
          .width('100%')
      }
      .width('100%')
      .padding(15)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)

      AuthPrimaryButton({
        label: '进入首页',
        primary: true,
        onTap: () => AppNavigator.replaceRoot(this.getUIContext(), AppRoutes.HOME)
      })
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 64, bottom: 24 })
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
