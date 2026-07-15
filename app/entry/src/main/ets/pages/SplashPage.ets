import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { TokenStorage } from '../common/storage/TokenStorage';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthDocumentVisual, AuthLogoLockup, AuthTextButton } from '../components/AuthLegalComponents';

/**
 * SplashPage 负责启动时的登录态分流。
 * 维护说明：页面复刻 HTML Splash / Launch 视觉和动效，不输出 Token、密码或其他敏感凭据。
 */
@Entry
@Component
struct SplashPage {
  @State progress: number = 0;

  aboutToAppear(): void {
    this.startLaunchMotion();
  }

  /**
   * 启动页进度条使用 420ms tween。这里只决定视觉过渡，不读取或展示会话 Token。
   */
  private startLaunchMotion(): void {
    this.getUIContext().animateTo({ duration: 420, curve: Curve.EaseOut }, () => {
      this.progress = 1;
    });
  }

  /**
   * 根据本地会话决定继续进入首页或登录前 Welcome。
   * 安全边界：只判断是否存在 Token，不显示 Token 内容。
   */
  private async enterNext(): Promise<void> {
    const hasToken = await TokenStorage.hasToken();
    AppNavigator.replace(this.getUIContext(), hasToken ? AppRoutes.HOME : AppRoutes.WELCOME);
  }

  build() {
    Column({ space: 18 }) {
        AuthLogoLockup({ compact: false, vertical: true, markSize: 58 })
          .width('100%')

        Text('智能识别、整理与管理你的 OCR 文档')
          .fontSize(15)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(23)
          .textAlign(TextAlign.Center)
          .width('100%')

        AuthDocumentVisual()
          .margin({ top: 8 })

        Column() {
          Column()
            .width(`${Math.round(this.progress * 100)}%`)
            .height(5)
            .backgroundColor(AppTheme.COLOR_BRAND)
            .borderRadius(3)
        }
        .width(210)
        .height(5)
        .backgroundColor(AppTheme.COLOR_LINE_SOFT)
        .borderRadius(3)
        .margin({ top: 2 })

        AuthTextButton({
          label: '进入应用',
          onTap: () => this.enterNext()
        })
        .margin({ top: 14 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 24, right: 24, top: 22, bottom: 34 })
    .backgroundColor(AppTheme.COLOR_PAGE)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }
}
