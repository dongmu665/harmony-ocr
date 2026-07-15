import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { TokenStorage } from '../common/storage/TokenStorage';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import { HtmlAppBar, HtmlListRow, HtmlSectionHead, HtmlStatusBar, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { AuthService } from '../features/auth/AuthService';
import { CurrentUser } from '../features/auth/AuthModels';
import { MembershipResponse } from '../features/v2/V2Models';
import { V2Service } from '../features/v2/V2Service';

/**
 * ProfilePage 复刻 v3.3 canonical HTML 的紧凑账户概览页。
 * 本页只展示账户概览、服务入口和退出确认，不承载账号移除或数据清理的完整流程。
 */
@Entry
@Component
struct ProfilePage {
  @State isLoggedIn: boolean = false;
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State username: string = '';
  @State nickname: string = '';
  @State membership?: MembershipResponse = undefined;
  @State isAdmin: boolean = false;
  @State accountEntered: boolean = false;
  @State menuEntered: boolean = false;
  @State adminEntered: boolean = false;
  @State showLogoutConfirm: boolean = false;

  aboutToAppear(): void {
    this.refreshCurrentUser();
    this.triggerCardReveal();
  }

  /**
   * 卡片进入节奏对齐 HTML motion-card 的轻量 stagger，只影响视觉展示。
   */
  private triggerCardReveal(): void {
    this.revealCard(() => this.accountEntered = true, 0);
    this.revealCard(() => this.menuEntered = true, 1);
    this.revealCard(() => this.adminEntered = true, 2);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  /**
   * 刷新当前用户资料；Token 无效时回到 guest stage，不展示敏感会话信息。
   */
  private async refreshCurrentUser(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    const hasToken = await TokenStorage.hasToken();
    if (!hasToken) {
      this.setGuestState();
      this.loading = false;
      return;
    }

    try {
      const user: CurrentUser = await AuthService.getCurrentUser();
      this.isLoggedIn = true;
      this.username = user.username;
      this.nickname = user.nickname ?? '';
      await this.refreshAccountServices();
    } catch (error) {
      await TokenStorage.clearTokens();
      this.setGuestState();
      this.errorMessage = this.toUserMessage(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * 退出登录前必须先进入 logoutConfirm stage，避免普通态出现大号直接退出按钮。
   */
  private async logout(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      await AuthService.logout();
      this.setGuestState();
      AppNavigator.replace(this.getUIContext(), AppRoutes.LOGIN);
    } catch (error) {
      this.setGuestState();
      this.errorMessage = this.toUserMessage(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * 游客、Token 失效或退出后的统一 UI 复位。
   */
  private setGuestState(): void {
    this.isLoggedIn = false;
    this.username = '';
    this.nickname = '';
    this.membership = undefined;
    this.isAdmin = false;
    this.showLogoutConfirm = false;
  }

  /**
   * 读取额度和管理员能力；失败时降级为 backendPartial 的提示体验。
   */
  private async refreshAccountServices(): Promise<void> {
    let failed: boolean = false;
    try {
      this.membership = await V2Service.getMembership();
    } catch (_) {
      this.membership = undefined;
      failed = true;
    }
    try {
      const capability = await V2Service.getAdminCapability();
      this.isAdmin = capability.admin;
    } catch (error) {
      this.isAdmin = false;
      if (!(error instanceof ApiError && (error.statusCode === 403 || error.code === 'FORBIDDEN'))) {
        failed = true;
      }
    }
    if (failed) {
      this.errorMessage = '额度与 AI 服务连接状态暂时无法获取，其余设置仍可正常使用。请稍后重试加载。';
    }
  }

  /**
   * 将账号接口异常转换为用户可读提示，不包含 Token、密码或其他敏感信息。
   */
  private toUserMessage(error: Object): string {
    if (error instanceof ApiError && error.message.length > 0) {
      return error.message;
    }
    return '网络异常，请稍后重试';
  }

  private displayName(): string {
    if (!this.isLoggedIn) {
      return '未登录';
    }
    if (this.nickname.length > 0) {
      return this.nickname;
    }
    return this.username;
  }

  private planTitle(): string {
    if (!this.isLoggedIn) {
      return '请先登录';
    }
    if (this.isAdmin) {
      return '管理员账号';
    }
    if (this.membership === undefined) {
      return 'Free Plan';
    }
    if (this.membership.membershipLevel.toUpperCase().indexOf('PRO') >= 0) {
      return 'Pro Plan';
    }
    return 'Free Plan';
  }

  private planBadge(): string {
    if (!this.isLoggedIn) {
      return 'GUEST';
    }
    if (this.isAdmin) {
      return 'TEAM';
    }
    if (this.planTitle() === 'Pro Plan') {
      return 'PRO';
    }
    return 'FREE';
  }

  private planMeta(): string {
    if (!this.isLoggedIn) {
      return '登录后可查看账户信息、额度使用情况、AI 服务连接状态与导出历史。';
    }
    if (this.isAdmin) {
      return 'Admin 角色 · Pro Plan';
    }
    if (this.membership === undefined) {
      return '基础 OCR 额度，AI 功能需连接自有 Provider。具体数值以实际账户为准。';
    }
    if (this.planTitle() === 'Pro Plan') {
      return '更高 OCR quota 与 Batch concurrency。本月配额与 AI tokens 见「会员额度」。';
    }
    return '基础 OCR 额度，AI 功能需连接自有 Provider。具体数值以实际账户为准。';
  }

  private quotaMeta(): string {
    if (!this.isLoggedIn) {
      return '未同步额度';
    }
    if (this.membership === undefined) {
      return '额度暂不可用';
    }
    return 'OCR ' + this.membership.ocrUsed.toString() + '/' + this.membership.ocrQuota.toString() +
      ' · AI ' + this.membership.aiUsed.toString() + '/' + this.membership.aiQuota.toString() +
      ' · Export ' + this.membership.exportUsed.toString() + '/' + this.membership.exportQuota.toString();
  }

  @Builder
  private accountCard() {
    Column({ space: 13 }) {
      Text(this.planTitle())
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(27)
        .width('100%')

      Text(this.planMeta())
        .fontSize(14)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(20)
        .width('100%')
        .maxLines(2)

      Column({ space: 10 }) {
        TextActionButton({
          label: this.isLoggedIn ? '查看会员额度' : '去登录',
          primary: true,
          onTap: () => AppNavigator.push(this.getUIContext(), this.isLoggedIn ? AppRoutes.QUOTA_CENTER : AppRoutes.LOGIN)
        })
        if (!this.isLoggedIn) {
          TextActionButton({
            label: '注册新账号',
            onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.REGISTER)
          })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private guestStateBlock() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text('我')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
      }
      .width(52)
      .height(52)
      .borderRadius(16)
      .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)

      Text('请先登录')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(20)

      Text('未登录')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_BADGE)

      Text('登录后可查看账户信息、额度使用情况、AI 服务连接状态与导出历史。')
        .fontSize(12.5)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(19)
        .textAlign(TextAlign.Center)
        .width(220)

      Row({ space: 9 }) {
        TextActionButton({
          label: '去登录',
          primary: true,
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.LOGIN)
        })
        .layoutWeight(1)
        TextActionButton({
          label: '注册新账号',
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.REGISTER)
        })
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }

  @Builder
  private backendPartialBlock() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text('!')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_WARNING)
      }
      .width(52)
      .height(52)
      .borderRadius(16)
      .backgroundColor(AppTheme.COLOR_WARNING_BG)

      Text('部分账户信息加载失败')
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(20)

      Text('后端部分错误')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_WARNING)
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_WARNING_LINE })
        .borderRadius(AppTheme.RADIUS_BADGE)

      Text('额度与 AI 服务连接状态暂时无法获取，其余设置仍可正常使用。请稍后重试加载。')
        .fontSize(12.5)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(19)
        .textAlign(TextAlign.Center)
        .width(240)

      TextActionButton({
        label: '重试加载',
        onTap: () => this.refreshCurrentUser()
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_WARNING_LINE })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }

  @Builder
  private adminIdentityBlock() {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        Text(this.displayName().substring(0, 1).toUpperCase())
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_BRAND)
      }
      .width(38)
      .height(44)
      .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CONTROL)

      Column({ space: 3 }) {
        Text('管理员账号')
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
        Text('Admin 角色 · Pro Plan')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')
      }
      .layoutWeight(1)

      Text('Admin')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_TEXT_INVERSE)
        .height(28)
        .padding({ left: 10, right: 10 })
        .backgroundColor(AppTheme.COLOR_TEXT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_TEXT })
        .borderRadius(AppTheme.RADIUS_BADGE)
    }
    .width('100%')
    .height(66)
    .padding({ left: 13, right: 13, top: 11, bottom: 11 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private profileMenu() {
    List({ space: 0 }) {
      ListItem() {
        HtmlListRow({
          index: 0,
          mark: 'SET',
          title: '应用设置',
          meta: '外观、识别语言、默认导出与隐私',
          badge: 'General',
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.SETTINGS)
        })
      }
      ListItem() {
        HtmlListRow({
          index: 1,
          mark: 'AI',
          title: 'AI 服务连接',
          meta: 'Provider、访问密钥、Default model',
          badge: 'Model',
          enabledState: this.isLoggedIn,
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.BYOK_PROVIDER)
        })
      }
      ListItem() {
        HtmlListRow({
          index: 2,
          mark: 'OUT',
          title: '导出中心',
          meta: '查看导出队列、进度和历史',
          badge: 'Output',
          enabledState: this.isLoggedIn,
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.EXPORT_CENTER)
        })
      }
      ListItem() {
        HtmlListRow({
          index: 3,
          mark: 'PRO',
          title: '会员额度',
          meta: 'OCR quota、AI tokens、Batch concurrency',
          badge: 'Plan',
          enabledState: this.isLoggedIn,
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.QUOTA_CENTER)
        })
      }
      ListItem() {
        HtmlListRow({
          index: 4,
          mark: 'DOC',
          title: '反馈与帮助',
          meta: '识别错误、导出失败与功能建议',
          badge: 'Help',
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.FEEDBACK)
        })
      }
      ListItem() {
        HtmlListRow({
          index: 5,
          mark: 'ACC',
          title: '账号与数据删除',
          meta: '注销账号、删除 OCR 记录与导出历史',
          badge: '注销',
          tone: 'danger',
          onTap: () => AppNavigator.push(this.getUIContext(), this.isLoggedIn ? AppRoutes.ACCOUNT_DELETION : AppRoutes.LOGIN)
        })
      }
    }
    .width('100%')
    .height(396)
    .scrollBar(BarState.Off)
  }

  @Builder
  private adminMenu() {
    List({ space: 0 }) {
      ListItem() {
        HtmlListRow({
          index: 0,
          mark: 'ADM',
          title: '进入 Admin 后台',
          meta: '用户、文档、反馈、额度与审计',
          badge: 'Admin',
          tone: 'dark',
          onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.ADMIN_DASHBOARD)
        })
      }
    }
    .width('100%')
    .height(66)
    .scrollBar(BarState.Off)
  }

  @Builder
  private logoutConfirmPanel() {
    Column({ space: 12 }) {
      Text('退出当前账号？')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .width('100%')

      Text('退出后需重新登录才能查看记录、额度与 AI 服务连接。本地草稿不会被删除。')
        .fontSize(AppTheme.FONT_META)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(AppTheme.LINE_META)
        .width('100%')

      Row({ space: 10 }) {
        TextActionButton({
          label: '取消',
          enabledState: !this.loading,
          onTap: () => this.showLogoutConfirm = false
        })
        .layoutWeight(1)
        TextActionButton({
          label: '退出登录',
          danger: true,
          primary: true,
          enabledState: !this.loading,
          onTap: () => this.logout()
        })
        .layoutWeight(1)
      }
      .width('100%')
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_DANGER_LINE })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({
            title: '我的',
            subtitle: 'ProfilePage · 账户、额度与服务连接',
            showBackButton: true,
            actionLabel: '···',
            actionIcon: 'sun',
            onBack: () => AppNavigator.replace(this.getUIContext(), AppRoutes.HOME),
            onAction: () => {
              if (this.isLoggedIn) {
                this.showLogoutConfirm = true;
              } else {
                AppNavigator.push(this.getUIContext(), AppRoutes.LOGIN);
              }
            }
          })

          if (this.loading) {
            StatusBanner({ label: '同步', title: '正在刷新账户状态', message: '页面不会展示登录凭据或安全令牌。', tone: 'info' })
          }

          if (!this.isLoggedIn && this.errorMessage.length > 0) {
            StatusBanner({ label: '后端部分错误', title: '部分账户信息加载失败', message: this.errorMessage, tone: 'warning' })
          }

          if (!this.isLoggedIn) {
            Column() {
              this.guestStateBlock()
            }
            .width('100%')
            .opacity(this.accountEntered ? 1 : 0)
            .translate({ y: this.accountEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
          } else {
            if (this.showLogoutConfirm) {
              Column() {
                this.accountCard()
              }
              .width('100%')
              .opacity(this.accountEntered ? 1 : 0)
              .translate({ y: this.accountEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

              this.logoutConfirmPanel()
            } else {
              if (this.errorMessage.length > 0) {
                Column() {
                  this.backendPartialBlock()
                }
                .width('100%')
                .opacity(this.accountEntered ? 1 : 0)
                .translate({ y: this.accountEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
              } else if (this.isAdmin) {
                Column() {
                  this.adminIdentityBlock()
                }
                .width('100%')
                .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
                .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
                .borderRadius(AppTheme.RADIUS_PANEL)
                .opacity(this.accountEntered ? 1 : 0)
                .translate({ y: this.accountEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
              } else {
                Column() {
                  this.accountCard()
                }
                .width('100%')
                .opacity(this.accountEntered ? 1 : 0)
                .translate({ y: this.accountEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
              }

              Column({ space: 8 }) {
                HtmlSectionHead({ title: '设置', meta: '账户服务' })
                Column() {
                  this.profileMenu()
                }
                .width('100%')
                .padding(AppTheme.CARD_PADDING)
                .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
                .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
                .borderRadius(AppTheme.RADIUS_PANEL)
              }
              .width('100%')
              .opacity(this.menuEntered ? 1 : 0)
              .translate({ y: this.menuEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

              if (this.isAdmin && this.errorMessage.length === 0) {
                Column({ space: 8 }) {
                  HtmlSectionHead({ title: '管理员', meta: '仅 Admin 可见' })
                  Column() {
                    this.adminMenu()
                  }
                  .width('100%')
                  .padding(AppTheme.CARD_PADDING)
                  .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
                  .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
                  .borderRadius(AppTheme.RADIUS_PANEL)
                }
                .width('100%')
                .opacity(this.adminEntered ? 1 : 0)
                .translate({ y: this.adminEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
              }
            }
          }

          Column()
            .height(4)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 4, bottom: AppTheme.PAGE_PADDING })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .backgroundColor(AppTheme.COLOR_PAGE)

      AppBottomNav({ activeTab: 'profile' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
