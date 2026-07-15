import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthPageAppBar, AuthPrimaryButton } from '../components/AuthLegalComponents';
import { HtmlStatusBar } from '../components/BrandComponents';

/**
 * PrivacyPage 复刻 HTML 隐私政策阅读页。
 * 维护说明：本页说明数据处理边界，不展示真实用户隐私、Token、API Key、完整 objectKey 或 OCR 全文。
 */
@Entry
@Component
struct PrivacyPage {
  private sections: string[][] = [
    ['我们收集的信息', '我们仅收集提供 OCR、账号同步、导出历史和安全风控所需的信息，例如账号标识、设备状态、文档处理状态和用户主动提交的内容。'],
    ['图片与 OCR 文本处理', '图片内容和 OCR 全文不应写入日志。文档内容仅用于完成识别、校对、导出和用户主动触发的处理任务。'],
    ['AI 服务与第三方服务', '当你使用 AI 摘要、纠错、翻译、字段提取等功能时，系统应明确提示可能将相关文本发送给你选择的第三方 AI 服务。'],
    ['BYOK 密钥说明', '访问密钥不应明文展示。界面仅显示掩码、指纹或尾号，密钥用于调用你选择的 AI 服务。'],
    ['数据保存与删除', '用户可以删除记录和注销账号。你可以删除 OCR 记录、OCR 文本、文件对象引用和历史导出记录。'],
    ['账号注销', '你可以申请注销账号。注销后将删除账号资料、登录状态和可识别的文档记录，必要安全审计记录可能按法规保留。'],
    ['权限使用说明', '相机、相册、文件和网络权限仅用于拍摄、导入、识别、同步和导出文档。'],
    ['联系方式', '如需访问、更正、删除数据或咨询隐私事项，可通过应用内反馈入口联系我们。']
  ];

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 12 }) {
          AuthPageAppBar({
            title: '隐私政策',
            subtitle: '清晰说明数据处理方式',
            rightIcon: 'more',
            onRightTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AGREEMENT)
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
