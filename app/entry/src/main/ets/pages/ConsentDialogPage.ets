import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthConsentFlowState } from '../features/auth/AuthConsentFlowState';
import { AuthConsentSheet, AuthPageAppBar } from '../components/AuthLegalComponents';
import { HtmlStatusBar } from '../components/BrandComponents';

/**
 * ConsentDialogPage 用于设备截图验证和首次启动/登录/注册前的协议确认展示。
 * 维护说明：页面只展示固定协议说明和 bottom sheet，不读取或记录密码、Token、API Key 或文档内容。
 */
@Entry
@Component
struct ConsentDialogPage {
  @State private showConsent: boolean = true;

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 16 }) {
        AuthPageAppBar({
          title: '协议确认',
          subtitle: '首次启动 / 登录 / 注册前确认',
          rightIcon: 'shield',
          onRightTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AGREEMENT)
        })

        Column({ space: 10 }) {
          Text('用户协议与隐私政策')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(28)
            .width('100%')
          Text('该确认用于首次启动、首次登录或首次注册。用户协议与隐私政策页面用于详细阅读。')
            .fontSize(15)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(24)
            .width('100%')
        }
        .width('100%')
        .padding(18)
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: AppTheme.STATUS_SAFE_CONTENT_GAP, bottom: AppTheme.PAGE_PADDING })
      .backgroundColor(AppTheme.COLOR_PAGE)

      AuthConsentSheet({
        visible: this.showConsent,
        title: '用户协议与隐私政策',
        body: '请先阅读并同意《用户协议》和《隐私政策》，以继续使用 Harmony OCR。',
        cancelLabel: '不同意',
        okLabel: '同意并继续',
        onCancel: () => {
          // 中文说明：拒绝协议不能停留在独立确认路由，必须回到 Welcome，避免用户被留在无后续动作的 sheet 页面。
          this.showConsent = false;
          AppNavigator.replace(this.getUIContext(), AppRoutes.WELCOME);
        },
        onOk: () => AppNavigator.replace(this.getUIContext(), AuthConsentFlowState.consumeTarget())
      })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
