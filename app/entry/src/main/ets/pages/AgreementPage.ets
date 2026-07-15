import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthPageAppBar, AuthPrimaryButton } from '../components/AuthLegalComponents';
import { HtmlStatusBar } from '../components/BrandComponents';

/**
 * AgreementPage 复刻 HTML 用户协议阅读页。
 * 维护说明：本页只展示协议草案内容与 sticky action，不包含密钥、Token、密码、完整媒体 URI 或 OCR 全文。
 */
@Entry
@Component
struct AgreementPage {
  private sections: string[][] = [
    ['服务说明', 'Harmony OCR 提供拍照、文件导入、OCR 识别、文本校对、历史管理、AI 文档处理和导出服务。'],
    ['用户账号', '你应妥善保管账号信息，不得将账号用于违法、侵权或破坏服务稳定性的行为。'],
    ['OCR 与文档处理', '你上传或导入的图片、PDF 与 OCR 文本应由你合法持有或有权处理。'],
    ['AI 功能说明', 'AI 生成内容仅供辅助参考。涉及合同、财务、法律等重要场景时，请自行核对原文证据。'],
    ['用户行为规范', '不得上传违法内容，不得尝试攻击、逆向、滥用接口或干扰其他用户。'],
    ['服务变更', '我们可能根据产品迭代调整功能、额度、支持格式或服务策略，并在合理范围内提示用户。'],
    ['免责声明', '因用户操作、第三方 AI 服务、网络环境或不可抗力造成的损失，服务方在法律允许范围内不承担超出合理边界的责任。']
  ];

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 12 }) {
          AuthPageAppBar({
            title: '用户协议',
            subtitle: '使用 Harmony OCR 前请阅读',
            rightIcon: 'more',
            onRightTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY)
          })

          Column({ space: 0 }) {
            ForEach(this.sections, (item: string[], index: number) => {
              this.articleSection(item[0], item[1], index)
            }, (item: string[], index: number) => `${index}-${item[0]}`)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 6, bottom: 6 })
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_PANEL)

          Column().height(82)
        }
        .width('100%')
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: AppTheme.STATUS_SAFE_CONTENT_GAP, bottom: AppTheme.PAGE_PADDING })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .height('100%')

      Column() {
        AuthPrimaryButton({
          label: '我已阅读并同意',
          primary: true,
          onTap: () => AppNavigator.back(this.getUIContext(), AppRoutes.WELCOME)
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 16 })
      .backgroundColor(AppTheme.COLOR_PAGE)
      .border({ width: { top: AppTheme.HAIRLINE }, color: AppTheme.COLOR_LINE_SOFT })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }

  @Builder
  private articleSection(title: string, body: string, index: number) {
    Column({ space: 7 }) {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(22)
        .width('100%')
      Text(body)
        .fontSize(14)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(23)
        .width('100%')
    }
    .width('100%')
    .padding({ top: 13, bottom: 13 })
    .border({ width: { bottom: index === this.sections.length - 1 ? 0 : AppTheme.HAIRLINE }, color: AppTheme.COLOR_LINE_SOFT })
  }
}
