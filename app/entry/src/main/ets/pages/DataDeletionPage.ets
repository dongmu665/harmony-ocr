import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthPrimaryButton } from '../components/AuthLegalComponents';
import { HtmlAppBar } from '../components/BrandComponents';

/**
 * DataDeletionPage 展示“仅删除数据、保留账号”能力边界，属于账号与隐私安全模块。
 * 维护说明：真实后端没有仅删数据保号接口，本页不触发 DELETE /users/me，避免把账号注销误导成局部删除。
 */
@Entry
@Component
struct DataDeletionPage {
  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 14 }) {
        HtmlAppBar({
          title: '数据删除',
          subtitle: 'DataDeletionPage · 仅删数据保号暂未开放',
          showBackButton: true,
          actionIcon: 'shield',
          onBack: () => AppNavigator.replace(this.getUIContext(), AppRoutes.SETTINGS),
          onAction: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY)
        })

        this.notAvailableStateBlock()

        Text('真实后端仅提供全量账号注销接口（DELETE /users/me），没有「仅删数据保号」的独立接口，因此本页不提供任何直接删除按钮，避免误导为可保留账号。')
          .fontSize(12)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(18)
          .width('100%')
          .padding({ left: 2, right: 2 })
      }
      .width('100%')
      .padding(AppTheme.PAGE_PADDING)
      .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }

  @Builder
  private notAvailableStateBlock() {
    Column({ space: 0 }) {
      this.warningShieldIcon()

      Text('仅删除数据、保留账号 暂未开放')
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })

      Text('暂未开放')
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_WARNING)
        .lineHeight(16)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_WARNING_LINE })
        .borderRadius(AppTheme.RADIUS_BADGE)
        .margin({ top: 7 })

      Text('当前不支持「只删除识别数据但保留账号」。系统仅提供整体账号注销（会一并删除账号资料、OCR 记录、文本与导出历史）。如需删除数据，请前往账号注销；如只想清理个别记录，可在记录详情中单条删除。')
        .fontSize(13)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .width(220)
        .margin({ top: 5 })

      Row({ space: 9 }) {
        AuthPrimaryButton({
          label: '前往账号注销',
          primary: true,
          onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.ACCOUNT_DELETION)
        })
          .layoutWeight(1)

        AuthPrimaryButton({
          label: '返回设置',
          primary: false,
          onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.SETTINGS)
        })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CARD)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private warningShieldIcon() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(18)
        .height(20)
        .border({ width: 1.7, color: AppTheme.COLOR_WARNING })
        .borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 7, bottomRight: 7 })
        .scale({ x: 0.9, y: 1 })
      Text('!')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_WARNING)
        .translate({ y: 1 })
    }
    .width(52)
    .height(52)
    .backgroundColor(AppTheme.COLOR_WARNING_BG)
    .borderRadius(16)
  }
}
