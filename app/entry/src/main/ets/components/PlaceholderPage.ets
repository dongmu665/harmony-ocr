import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { BrandHeader, StatusBanner } from './BrandComponents';

/**
 * PlaceholderPage 提供未开放功能的统一占位页，属于 components 模块。
 *
 * 维护说明：该组件只展示静态说明和安全的应用内跳转，不读取 Token、OCR 文本、图片 URI 或对象存储 key。
 */
@Component
export struct PlaceholderPage {
  title: string = '';
  description: string = '';
  primaryRoute: string = '';
  primaryText: string = '';

  /**
   * 构建占位页 UI。
   *
   * 安全边界：primaryRoute 应来自 AppRoutes 常量；组件本身不拼接外部 URL，也不展示用户输入路径。
   */
  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 18 }) {
        BrandHeader({
          title: this.title,
          subtitle: this.description,
          eyebrow: '文档工作台',
          compact: true
        })

        StatusBanner({
          label: '提示',
          title: '服务暂未开放',
          message: '当前入口保留在文档流程中，相关服务开放后再提供完整操作。',
          tone: 'neutral'
        })

        if (this.primaryRoute.length > 0 && this.primaryText.length > 0) {
          Button(this.primaryText)
            .width('100%')
            .height(AppTheme.BUTTON_HEIGHT)
            .fontColor(AppTheme.COLOR_TEXT_INVERSE)
            .backgroundColor(AppTheme.COLOR_BRAND)
            .onClick(() => {
              AppNavigator.push(this.getUIContext(), this.primaryRoute);
            })
        }
      }
      .width('100%')
      .padding(AppTheme.PAGE_PADDING)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
