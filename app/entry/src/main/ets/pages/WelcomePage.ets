import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthConsentFlowState } from '../features/auth/AuthConsentFlowState';
import { AuthLogoLockup, AuthTextButton } from '../components/AuthLegalComponents';
import { HtmlStatusBar } from '../components/BrandComponents';

/**
 * WelcomePage 展示登录前首页和协议入口。
 * 维护说明：页面只展示固定介绍、协议入口和路由，不读取或记录账号、密码、Token、API Key 或文档内容。
 */
@Entry
@Component
struct WelcomePage {
  /**
   * 登录/注册前先进入协议确认页。
   * 安全边界：target 只允许应用内路由常量，不拼接用户输入。
   */
  private openConsent(target: string): void {
    AuthConsentFlowState.setTarget(target);
    AppNavigator.push(this.getUIContext(), AppRoutes.CONSENT_DIALOG);
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 12 }) {
        AuthLogoLockup({ compact: true, markSize: 54 })
          .margin({ top: 18 })

        Text('把扫描件变成可编辑、可管理的文档')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(32)
          .width('100%')
          .margin({ top: 10 })

        Text('从拍照、导入、OCR 校对，到 AI 摘要与导出，Harmony OCR 为移动端文档处理提供清晰工作流。')
          .fontSize(14)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(22)
          .width('100%')
          .margin({ top: -2, bottom: 6 })

        this.point('scan', '拍照 / 导入图片与 PDF', '自动裁切、透视校正，适合合同、发票、纪要与资料。')
        this.point('doc', 'OCR 识别、校对与历史管理', '保留记录、文本和导出状态，方便持续编辑。')
        this.point('ai', 'AI 摘要、纠错、翻译与导出', '基于文档上下文生成草稿，不喧宾夺主。')

        Button('登录')
          .width('100%')
          .height(AppTheme.BUTTON_HEIGHT)
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT_INVERSE)
          .backgroundColor(AppTheme.COLOR_BRAND)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_BRAND_DARK })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .margin({ top: 0 })
          .onClick(() => this.openConsent(AppRoutes.LOGIN))

        Button('创建账号')
          .width('100%')
          .height(AppTheme.BUTTON_HEIGHT)
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_BRAND)
          .backgroundColor(AppTheme.COLOR_PAGE_DEEP)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .onClick(() => this.openConsent(AppRoutes.REGISTER))

        Row({ space: 2 }) {
          Text('继续使用即表示你已阅读并同意')
            .fontSize(12)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          AuthTextButton({
            label: '《用户协议》',
            onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AGREEMENT)
          })
          AuthTextButton({
            label: '《隐私政策》',
            onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY)
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 18, right: 18, top: AppTheme.STATUS_SAFE_CONTENT_GAP, bottom: 22 })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }

  @Builder
  private point(mark: string, title: string, body: string) {
    Row({ space: 11 }) {
      this.mini(mark)
      Column({ space: 4 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(20)
          .width('100%')
        Text(body)
          .fontSize(12)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(18)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private mini(mark: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (mark === 'scan') {
        Column().width(18).height(2).backgroundColor(AppTheme.COLOR_BRAND)
        Column().width(12).height(2).backgroundColor(AppTheme.COLOR_BRAND).translate({ y: 7 })
        Column().width(22).height(22).border({ width: 1.4, color: AppTheme.COLOR_BRAND, style: BorderStyle.Dashed }).borderRadius(6)
      } else if (mark === 'ai') {
        Column().width(14).height(14).border({ width: 1.5, color: AppTheme.COLOR_BRAND }).rotate({ angle: 45 })
        Column().width(5).height(5).backgroundColor(AppTheme.COLOR_BRAND).borderRadius(3).translate({ x: 10, y: -10 })
      } else {
        Column().width(15).height(19).border({ width: 1.5, color: AppTheme.COLOR_BRAND }).borderRadius(3)
        Column().width(8).height(1.3).backgroundColor(AppTheme.COLOR_BRAND).translate({ y: -2 })
        Column().width(6).height(1.3).backgroundColor(AppTheme.COLOR_BRAND).translate({ y: 4 })
      }
    }
    .width(32)
    .height(32)
    .backgroundColor(AppTheme.COLOR_BRAND_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }
}
