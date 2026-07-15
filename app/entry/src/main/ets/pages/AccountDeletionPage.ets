import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthCheckBox, AuthPrimaryButton } from '../components/AuthLegalComponents';
import { HtmlAppBar, HtmlBadge } from '../components/BrandComponents';
import { AuthService } from '../features/auth/AuthService';
import { HistoryState } from '../features/history/HistoryState';

type AccountDeletionStage = 'initial' | 'unchecked' | 'checked' | 'confirm' | 'processing' | 'success' | 'failure';

interface AccountStateBlockOptions {
  label: string;
  title: string;
  message: string;
  tone: string;
  icon: string;
  showSkeleton?: boolean;
  primaryLabel?: string;
  secondaryLabel?: string;
  dangerPrimary?: boolean;
  onPrimary?: () => void;
  onSecondary?: () => void;
}

/**
 * AccountDeletionPage 承载真实账号注销流程，属于账号与隐私安全模块。
 * 维护说明：本页只调用后端 DELETE /users/me，不展示 Token、密码、OCR 全文、objectKey 或本地文件路径。
 */
@Entry
@Component
struct AccountDeletionPage {
  @State private stage: AccountDeletionStage = 'initial';
  @State private accepted: boolean = false;
  @State private errorMessage: string = '';
  @State private sessionExpired: boolean = false;
  private verifierMode: boolean = false;

  private deletionItems: string[][] = [
    ['账号资料', '用户名、昵称与账号绑定信息'],
    ['Refresh Token / 登录状态', '当前设备和云端登录会话'],
    ['OCR 记录', '文档记录、处理状态和历史列表'],
    ['OCR 文本', '识别后的可编辑文本和校对痕迹'],
    ['文件对象引用', '上传文件与导出文件的对象引用'],
    ['历史导出记录', 'TXT、Markdown、PDF、可搜索 PDF、JSON 导出历史']
  ];

  aboutToAppear(): void {
    const verifierStage = HistoryState.getVerifierStage();
    if (this.isAccountDeletionStage(verifierStage)) {
      this.verifierMode = true;
      this.applyStage(verifierStage as AccountDeletionStage);
    }
  }

  /**
   * 注销当前账号。
   * 安全注意：真实删除只发生在用户勾选确认并通过危险弹层后；成功后 AuthService 会清理本地 Token。
   */
  private async deleteAccount(): Promise<void> {
    if (this.stage === 'processing') {
      return;
    }
    if (!this.accepted || this.stage !== 'confirm') {
      this.stage = 'unchecked';
      this.errorMessage = '请先勾选确认后再继续。';
      return;
    }
    this.sessionExpired = false;
    this.errorMessage = '';
    this.stage = 'processing';
    try {
      await AuthService.deleteAccount();
      this.stage = 'success';
      if (!this.verifierMode) {
        setTimeout(() => {
          AppNavigator.replaceRoot(this.getUIContext(), AppRoutes.WELCOME);
        }, 900);
      }
    } catch (error) {
      const apiError = error as ApiError;
      this.sessionExpired = apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED';
      this.errorMessage = this.toUserMessage(error as Error, '注销过程中发生错误，账号与数据保持原状。请稍后重试，或通过反馈入口联系我们处理。');
      this.stage = 'failure';
    }
  }

  private toUserMessage(error: Error, fallback: string): string {
    const apiError = error as ApiError;
    if (apiError.statusCode === 401 || apiError.code === 'UNAUTHORIZED' || apiError.code === 'AUTH_TOKEN_EXPIRED') {
      return '登录状态已失效，请重新登录后再发起账号注销。';
    }
    if (apiError.message && apiError.message.length > 0 && apiError.message.length < 100) {
      return apiError.message;
    }
    return fallback;
  }

  private isAccountDeletionStage(stage: string): boolean {
    return stage === 'initial' || stage === 'unchecked' || stage === 'checked' || stage === 'confirm' ||
      stage === 'processing' || stage === 'success' || stage === 'failure';
  }

  private applyStage(stage: AccountDeletionStage): void {
    this.stage = stage;
    this.accepted = stage === 'checked' || stage === 'confirm' || stage === 'processing' || stage === 'success';
    this.sessionExpired = false;
    this.errorMessage = stage === 'failure'
      ? '注销过程中发生错误，账号与数据保持原状。请稍后重试，或通过反馈入口联系我们处理。'
      : '';
  }

  private toggleAccepted(checked: boolean): void {
    this.accepted = checked;
    this.errorMessage = '';
    this.sessionExpired = false;
    this.stage = checked ? 'checked' : 'unchecked';
  }

  private requestConfirm(): void {
    if (!this.accepted) {
      this.stage = 'unchecked';
      this.errorMessage = '请先勾选确认后再继续。';
      return;
    }
    this.stage = 'confirm';
  }

  private cancelConfirm(): void {
    this.stage = this.accepted ? 'checked' : 'initial';
  }

  private goAfterSuccess(): void {
    AppNavigator.replaceRoot(this.getUIContext(), AppRoutes.WELCOME);
  }

  private handleFailurePrimaryAction(): void {
    if (this.sessionExpired) {
      AppNavigator.replaceRoot(this.getUIContext(), AppRoutes.LOGIN);
      return;
    }
    if (!this.accepted) {
      this.stage = 'unchecked';
      this.errorMessage = '请先勾选确认后再继续。';
      return;
    }
    this.stage = 'confirm';
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 14 }) {
        HtmlAppBar({
          title: '账号与数据删除',
          subtitle: '注销前请仔细确认',
          showBackButton: true,
          actionIcon: 'shield',
          onBack: () => AppNavigator.replace(this.getUIContext(), AppRoutes.SETTINGS),
          onAction: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY)
        })

        if (this.stage === 'processing') {
          this.processingState()
        } else if (this.stage === 'success') {
          this.successState()
        } else if (this.stage === 'failure') {
          this.failureState()
        } else {
          this.confirmationContent()
        }
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
  private confirmationContent() {
    Column({ space: 8 }) {
      Text('注销账号后不可恢复')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(27)
        .width('100%')
      Text('注销申请确认后，我们将删除或解除关联你的账号资料和可识别文档数据。必要的安全审计记录或匿名统计信息可能按法规或安全要求保留。')
        .fontSize(15)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(24)
        .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)

    Text('将被删除')
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.COLOR_TEXT)
      .lineHeight(22)
      .width('100%')
      .margin({ top: 6 })

    Column({ space: 0 }) {
      ForEach(this.deletionItems, (item: string[], index: number) => {
        this.deletionRow(item[0], item[1], index)
      }, (item: string[], index: number) => `${index}-${item[0]}`)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 4, bottom: 4 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_DANGER_LINE })
    .borderRadius(AppTheme.RADIUS_PANEL)

    Column({ space: 6 }) {
      Text('可能保留')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(20)
        .width('100%')
      Text('必要的安全审计记录、反滥用日志或匿名统计信息。这些信息不用于恢复你的个人文档内容。')
        .fontSize(15)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(24)
        .width('100%')
    }
    .width('100%')
    .padding(AppTheme.ITEM_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)

    Row({ space: 10 }) {
      AuthCheckBox({
        checked: this.accepted,
        onToggle: (checked: boolean) => this.toggleAccepted(checked)
      })
      Text('我已了解注销不可恢复，并确认继续')
        .fontSize(15)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(22)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ top: 2 })

    if (this.stage === 'unchecked' || this.errorMessage.length > 0) {
      Text(this.errorMessage.length > 0 ? this.errorMessage : '请先勾选确认后再继续。')
        .fontSize(12)
        .fontColor(AppTheme.COLOR_DANGER)
        .lineHeight(18)
        .width('100%')
    }

    AuthPrimaryButton({
      label: '申请注销账号',
      primary: true,
      danger: true,
      enabledState: this.accepted,
      onTap: () => this.requestConfirm()
    })

    if (this.stage === 'confirm') {
      this.dangerConfirmZone()
    }
  }

  @Builder
  private processingState() {
    this.accountStateBlock({
      label: '处理中',
      title: '正在注销账号',
      message: '正在删除或解除关联你的账号资料与可识别文档数据，请稍候。该过程不可中断。',
      tone: 'danger',
      icon: 'trash',
      showSkeleton: true
    })
  }

  @Builder
  private successState() {
    this.accountStateBlock({
      label: '操作成功',
      title: '账号已注销',
      message: '你的账号资料、登录状态与可识别文档数据已删除。必要的安全审计记录可能按法规保留。',
      tone: 'success',
      icon: 'check',
      primaryLabel: '返回欢迎页',
      onPrimary: () => this.goAfterSuccess()
    })
  }

  @Builder
  private failureState() {
    this.accountStateBlock({
      label: '操作失败',
      title: '注销失败',
      message: this.errorMessage.length > 0 ? this.errorMessage : '注销过程中发生错误，账号与数据保持原状。请稍后重试，或通过反馈入口联系我们处理。',
      tone: 'danger',
      icon: 'trash',
      primaryLabel: this.sessionExpired ? '返回登录' : '重试注销',
      secondaryLabel: '联系反馈',
      dangerPrimary: !this.sessionExpired,
      onPrimary: () => this.handleFailurePrimaryAction(),
      onSecondary: () => AppNavigator.push(this.getUIContext(), AppRoutes.FEEDBACK)
    })
  }

  @Builder
  private skeletonLine(widthValue: string) {
    Column()
      .width(widthValue)
      .height(12)
      .backgroundColor(AppTheme.COLOR_NEUTRAL_BG)
      .borderRadius(6)
  }

  @Builder
  private dangerConfirmZone() {
    Column({ space: 12 }) {
      Text('确认申请注销账号？')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(22)
        .width('100%')
      Text('账号资料、登录状态、OCR 记录、OCR 文本、文件对象引用和历史导出记录将被删除。请确认你已完成必要备份。')
        .fontSize(13)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(20)
        .width('100%')

      Row({ space: 10 }) {
        AuthPrimaryButton({
          label: '取消',
          primary: false,
          onTap: () => this.cancelConfirm()
        })
          .layoutWeight(1)
        AuthPrimaryButton({
          label: '确认申请注销',
          primary: true,
          danger: true,
          onTap: () => this.deleteAccount()
        })
          .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(AppTheme.COLOR_DANGER_BG)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_DANGER_LINE })
    .borderRadius(AppTheme.RADIUS_CARD)
  }

  @Builder
  private accountStateBlock(options: AccountStateBlockOptions) {
    Column({ space: 0 }) {
      this.stateIcon(options.tone, options.icon)
      Text(options.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })

      Text(options.label)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.stateToneColor(options.tone))
        .lineHeight(16)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .border({ width: AppTheme.HAIRLINE, color: this.stateToneLine(options.tone) })
        .borderRadius(AppTheme.RADIUS_BADGE)
        .margin({ top: 7 })

      Text(options.message)
        .fontSize(13)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .width(220)
        .margin({ top: 5 })

      if (options.showSkeleton) {
        Column({ space: 10 }) {
          this.skeletonLine('100%')
          this.skeletonLine('100%')
        }
        .width('100%')
        .margin({ top: 18 })
      }

      if (options.primaryLabel && options.primaryLabel.length > 0) {
        Row({ space: 9 }) {
          AuthPrimaryButton({
            label: options.primaryLabel,
            primary: true,
            danger: options.dangerPrimary === true,
            onTap: options.onPrimary ? options.onPrimary : () => {}
          })
            .layoutWeight(1)

          if (options.secondaryLabel && options.secondaryLabel.length > 0) {
            AuthPrimaryButton({
              label: options.secondaryLabel,
              primary: false,
              onTap: options.onSecondary ? options.onSecondary : () => {}
            })
              .layoutWeight(1)
          }
        }
        .width('100%')
        .margin({ top: 18 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: this.stateBlockLine(options.tone) })
    .borderRadius(AppTheme.RADIUS_CARD)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private stateIcon(tone: string, icon: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (icon === 'check') {
        Column()
          .width(15)
          .height(3)
          .backgroundColor(this.stateToneColor(tone))
          .borderRadius(2)
          .rotate({ angle: -45 })
          .translate({ x: 4, y: -1 })
        Column()
          .width(8)
          .height(3)
          .backgroundColor(this.stateToneColor(tone))
          .borderRadius(2)
          .rotate({ angle: 45 })
          .translate({ x: -5, y: 3 })
      } else {
        Column()
          .width(17)
          .height(19)
          .border({ width: 1.7, color: this.stateToneColor(tone) })
          .borderRadius({ topLeft: 5, topRight: 5, bottomLeft: 4, bottomRight: 4 })
        Column()
          .width(19)
          .height(2)
          .backgroundColor(this.stateToneColor(tone))
          .translate({ y: -8 })
        Column()
          .width(11)
          .height(2)
          .backgroundColor(this.stateToneColor(tone))
          .rotate({ angle: 90 })
      }
    }
    .width(52)
    .height(52)
    .backgroundColor(this.stateToneBackground(tone))
    .borderRadius(16)
  }

  private stateToneColor(tone: string): string {
    if (tone === 'success') {
      return AppTheme.COLOR_SUCCESS;
    }
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER;
    }
    return AppTheme.COLOR_TEXT_SUBTLE;
  }

  private stateToneBackground(tone: string): string {
    if (tone === 'success') {
      return AppTheme.COLOR_SUCCESS_BG;
    }
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER_BG;
    }
    return AppTheme.COLOR_NEUTRAL_BG;
  }

  private stateToneLine(tone: string): string {
    if (tone === 'success') {
      return AppTheme.COLOR_LINE_SOFT;
    }
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER_LINE;
    }
    return AppTheme.COLOR_LINE_SOFT;
  }

  private stateBlockLine(tone: string): string {
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER_LINE;
    }
    return AppTheme.COLOR_LINE_SOFT;
  }

  @Builder
  private deletionRow(title: string, body: string, index: number) {
    Row({ space: 10 }) {
      Text(`${index + 1}`)
        .width(26)
        .height(26)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_DANGER)
        .textAlign(TextAlign.Center)
        .backgroundColor(AppTheme.COLOR_DANGER_BG)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_DANGER_LINE })
        .borderRadius(AppTheme.RADIUS_CONTROL)
      Column({ space: 3 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(19)
          .width('100%')
        Text(body)
          .fontSize(12)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(17)
          .width('100%')
          .maxLines(1)
      }
      .layoutWeight(1)
      HtmlBadge({ label: '删除', tone: 'danger' })
    }
    .width('100%')
    .height(62)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: index === this.deletionItems.length - 1 ? 0 : AppTheme.HAIRLINE }, color: AppTheme.COLOR_LINE_SOFT })
  }
}
