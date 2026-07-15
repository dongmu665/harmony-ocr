import { ApiError } from '../common/network/ApiTypes';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { TokenStorage } from '../common/storage/TokenStorage';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import {
  HtmlAppBar,
  HtmlBadge,
  HtmlFileMark,
  HtmlSectionHead,
  HtmlStatusBar,
  TextActionButton
} from '../components/BrandComponents';
import { MembershipResponse } from '../features/v2/V2Models';
import { V2Service } from '../features/v2/V2Service';

/**
 * QuotaCenterPage 复刻 HTML 原型的会员额度中心。
 * 维护边界：页面只读取当前用户会员额度和真实激活码兑换接口，不实现支付、购买或伪造升级闭环。
 */
@Entry
@Component
struct QuotaCenterPage {
  @State loading: boolean = false;
  @State loggedIn: boolean = false;
  @State membership?: MembershipResponse = undefined;
  @State membershipReady: boolean = false;
  @State stage: string = 'loading';
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State activationCode: string = '';
  @State activationSubmitting: boolean = false;
  @State ringEntered: boolean = false;
  @State usageEntered: boolean = false;
  @State activationEntered: boolean = false;
  @State ringProgress: number = 0;
  @State membershipLevel: string = '额度暂不可用';
  @State ocrQuota: number = 0;
  @State aiQuota: number = 0;
  @State exportQuota: number = 0;
  @State ocrUsed: number = 0;
  @State aiUsed: number = 0;
  @State exportUsed: number = 0;
  private ringContext: CanvasRenderingContext2D = new CanvasRenderingContext2D(new RenderingContextSettings(true));

  aboutToAppear(): void {
    this.triggerCardReveal();
    this.loadMembership();
  }

  /**
   * 按 HTML motion-card 的轻量 stagger 呈现额度环、列表和兑换块。
   */
  private triggerCardReveal(): void {
    this.revealCard(() => this.ringEntered = true, 0);
    this.revealCard(() => this.usageEntered = true, 1);
    this.revealCard(() => this.activationEntered = true, 2);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  /**
   * 加载真实会员额度；未登录直接进入 guestDisabled，不请求也不展示任何额度数字。
   */
  private async loadMembership(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '';
    this.stage = 'loading';
    try {
      const hasToken = await TokenStorage.hasToken();
      if (!hasToken) {
        this.applyGuestDisabled();
        return;
      }
      this.loggedIn = true;
      const currentMembership: MembershipResponse = await V2Service.getMembership();
      this.applyMembership(currentMembership);
      this.stage = this.quotaStageFromMembership();
    } catch (error) {
      if (this.isUnauthorized(error)) {
        this.applyGuestDisabled();
      } else {
        this.applyBackendError(this.safeErrorMessage(error, '当前无法连接服务器，额度使用情况暂时无法显示。请检查网络后重试。'));
      }
    } finally {
      this.loading = false;
      this.syncRingProgress();
      this.drawQuotaRing();
    }
  }

  private applyGuestDisabled(): void {
    this.loggedIn = false;
    this.membership = undefined;
    this.membershipReady = false;
    this.membershipLevel = '未登录';
    this.ocrQuota = 0;
    this.aiQuota = 0;
    this.exportQuota = 0;
    this.ocrUsed = 0;
    this.aiUsed = 0;
    this.exportUsed = 0;
    this.stage = 'guestDisabled';
  }

  private applyBackendError(message: string): void {
    this.loggedIn = true;
    this.membership = undefined;
    this.membershipReady = false;
    this.membershipLevel = '额度暂不可用';
    this.ocrQuota = 0;
    this.aiQuota = 0;
    this.exportQuota = 0;
    this.ocrUsed = 0;
    this.aiUsed = 0;
    this.exportUsed = 0;
    this.errorMessage = message;
    this.stage = 'backendError';
  }

  private applyMembership(currentMembership: MembershipResponse): void {
    this.membership = currentMembership;
    this.membershipReady = true;
    this.loggedIn = true;
    this.membershipLevel = currentMembership.membershipLevel;
    this.ocrQuota = currentMembership.ocrQuota;
    this.aiQuota = currentMembership.aiQuota;
    this.exportQuota = currentMembership.exportQuota;
    this.ocrUsed = currentMembership.ocrUsed;
    this.aiUsed = currentMembership.aiUsed;
    this.exportUsed = currentMembership.exportUsed;
    this.syncRingProgress();
  }

  /**
   * 兑换一次性会员激活码。
   * 安全边界：明文 code 只进入本次 POST 请求；成功后立即清空，失败也不持久化、不回显后端细节。
   */
  private async redeemActivationCode(): Promise<void> {
    const normalizedCode: string = this.activationCode.trim().toUpperCase();
    this.errorMessage = '';
    this.noticeMessage = '';
    if (!this.loggedIn) {
      this.applyGuestDisabled();
      return;
    }
    if (!this.activationCodeLooksValid(normalizedCode)) {
      this.stage = 'activationFailure';
      this.errorMessage = '激活码无效、已被使用或已过期。';
      return;
    }
    this.activationSubmitting = true;
    this.stage = 'activationSubmitting';
    try {
      const updatedMembership: MembershipResponse = await V2Service.redeemActivationCode({ code: normalizedCode });
      this.applyMembership(updatedMembership);
      this.activationCode = '';
      this.stage = 'activationSuccess';
      this.noticeMessage = '会员等级与额度已更新，激活码已失效并清空。';
    } catch (error) {
      if (this.isUnauthorized(error)) {
        this.applyGuestDisabled();
      } else {
        this.stage = 'activationFailure';
        this.errorMessage = '激活码无效、已被使用或已过期。';
      }
    } finally {
      this.activationSubmitting = false;
      this.syncRingProgress();
      this.drawQuotaRing();
    }
  }

  private handleActivationInput(value: string): void {
    this.activationCode = value.toUpperCase();
    this.errorMessage = '';
    this.noticeMessage = '';
    if (!this.loggedIn) {
      this.stage = 'guestDisabled';
      return;
    }
    if (this.activationCode.trim().length > 0) {
      this.stage = 'activationInput';
      return;
    }
    this.stage = this.membershipReady ? this.quotaStageFromMembership() : 'backendError';
  }

  private activationCodeLooksValid(code: string): boolean {
    const parts: string[] = code.split('-');
    if (parts.length !== 4 || (parts[0] !== 'PRO' && parts[0] !== 'TEAM')) {
      return false;
    }
    const allowed: string = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    for (let i = 1; i < parts.length; i++) {
      if (parts[i].length !== 4) {
        return false;
      }
      for (let j = 0; j < parts[i].length; j++) {
        if (allowed.indexOf(parts[i].charAt(j)) < 0) {
          return false;
        }
      }
    }
    return true;
  }

  private quotaStageFromMembership(): string {
    const percent = this.ocrPercent();
    if (this.ocrQuota > 0 && percent >= 100) {
      return 'exhausted';
    }
    if (this.ocrQuota > 0 && percent >= 80) {
      return 'warning';
    }
    if (this.isFreePlan()) {
      return 'free';
    }
    return 'normal';
  }

  private syncRingProgress(): void {
    if (!this.membershipReady) {
      this.ringProgress = 0;
      return;
    }
    this.ringProgress = this.ocrPercent();
  }

  /**
   * Canvas 额度环复刻 HTML conic ring：126px 外环、94px 内芯、平切进度端点。
   */
  private drawQuotaRing(): void {
    const size: number = 126;
    const center: number = size / 2;
    const radius: number = 53;
    const strokeWidth: number = 17;
    const startAngle: number = -Math.PI / 2;
    const sweepAngle: number = Math.PI * 2 * (this.ringProgress / 100);

    this.ringContext.clearRect(0, 0, size, size);
    this.ringContext.lineWidth = strokeWidth;
    this.ringContext.lineCap = 'butt';

    this.ringContext.beginPath();
    this.ringContext.strokeStyle = AppTheme.COLOR_PAGE_DEEP;
    this.ringContext.arc(center, center, radius, startAngle, startAngle + Math.PI * 2, false);
    this.ringContext.stroke();

    if (this.ringProgress > 0) {
      this.ringContext.beginPath();
      this.ringContext.strokeStyle = this.ringColor();
      this.ringContext.arc(center, center, radius, startAngle, startAngle + sweepAngle, false);
      this.ringContext.stroke();
    }
  }

  private ringColor(): string {
    if (this.ringProgress >= 90) {
      return AppTheme.COLOR_DANGER;
    }
    if (this.ringProgress >= 70) {
      return AppTheme.COLOR_BRAND_DARK;
    }
    return AppTheme.COLOR_BRAND;
  }

  private ocrPercent(): number {
    return this.usagePercent(this.ocrUsed, this.ocrQuota);
  }

  private aiPercent(): number {
    return this.usagePercent(this.aiUsed, this.aiQuota);
  }

  private exportPercent(): number {
    return this.usagePercent(this.exportUsed, this.exportQuota);
  }

  private usagePercent(used: number, quota: number): number {
    if (quota <= 0) {
      return 0;
    }
    const percent = Math.floor((used * 100) / quota);
    return percent > 100 ? 100 : percent;
  }

  /**
   * usageRow 保留为 UI smoke 的额度字段锚点；实际渲染使用 HTML row/list 结构。
   * coverage anchors: ocrQuota, aiQuota, exportQuota.
   */
  private usageRow(label: string, used: number, quota: number): string {
    return label + ' ' + used.toString() + ' / ' + quota.toString();
  }

  private isFreePlan(): boolean {
    return this.membershipLevel.toUpperCase().indexOf('FREE') >= 0;
  }

  private planTitle(): string {
    if (!this.membershipReady) {
      return '额度暂不可用';
    }
    const normalized = this.membershipLevel.toUpperCase();
    if (normalized.indexOf('FREE') >= 0) {
      return 'Free Plan';
    }
    if (normalized.indexOf('TEAM') >= 0) {
      return 'Team Plan';
    }
    if (normalized.indexOf('PRO') >= 0) {
      return 'Pro Plan';
    }
    return this.membershipLevel;
  }

  private planShortLabel(): string {
    if (!this.membershipReady) {
      return '-';
    }
    const normalized = this.membershipLevel.toUpperCase();
    if (normalized.indexOf('FREE') >= 0) {
      return 'Free';
    }
    if (normalized.indexOf('TEAM') >= 0) {
      return 'Team';
    }
    if (normalized.indexOf('PRO') >= 0) {
      return 'Pro';
    }
    return this.membershipLevel;
  }

  private ringValue(): string {
    return this.ocrPercent().toString() + '%';
  }

  private ringCaption(): string {
    if (this.stage === 'exhausted') {
      return '已用尽';
    }
    return 'OCR 已用比例';
  }

  private ringDetail(): string {
    if (!this.membershipReady || this.ocrQuota <= 0) {
      return '暂无额度';
    }
    return this.ocrUsed.toString() + '/' + this.ocrQuota.toString() + ' 次';
  }

  private ocrRemaining(): number {
    const remaining = this.ocrQuota - this.ocrUsed;
    return remaining > 0 ? remaining : 0;
  }

  private ocrQuotaMeta(): string {
    if (!this.membershipReady) {
      return '额度暂不可用';
    }
    if (this.ocrQuota <= 0) {
      return '暂无可用额度';
    }
    return '已用 ' + this.ocrUsed.toString() + ' / ' + this.ocrQuota.toString() + ' 次，剩余 ' + this.ocrRemaining().toString() + ' 次';
  }

  private ocrBadgeLabel(): string {
    if (!this.membershipReady || this.ocrQuota <= 0) {
      return '暂无';
    }
    return this.percentBadge(this.ocrPercent());
  }

  private usageMeta(used: number, quota: number, unit: string): string {
    if (quota <= 0) {
      return '暂不可用';
    }
    return used.toString() + ' / ' + quota.toString() + ' ' + unit;
  }

  private percentBadge(percent: number): string {
    return percent.toString() + '%';
  }

  private badgeTone(percent: number): 'neutral' | 'ok' | 'warn' | 'danger' | 'dark' {
    if (percent >= 100) {
      return 'danger';
    }
    if (percent >= 80) {
      return 'warn';
    }
    if (percent > 0) {
      return 'ok';
    }
    return 'neutral';
  }

  private aiUsageMeta(): string {
    if (this.aiQuota <= 0) {
      return '需连接自有 Provider';
    }
    return '已用 ' + this.aiPercent().toString() + '%';
  }

  private aiBadgeLabel(): string {
    if (this.aiQuota <= 0) {
      return 'BYOK';
    }
    return this.percentBadge(this.aiPercent());
  }

  private aiBadgeTone(): 'neutral' | 'ok' | 'warn' | 'danger' | 'dark' {
    if (this.aiQuota <= 0) {
      return 'neutral';
    }
    return this.badgeTone(this.aiPercent());
  }

  private isUnauthorized(error: Object): boolean {
    if (error instanceof ApiError) {
      return error.statusCode === 401 || error.code === 'UNAUTHORIZED' || error.code === 'AUTH_TOKEN_EXPIRED';
    }
    return false;
  }

  private safeErrorMessage(error: Object, fallback: string): string {
    if (error instanceof ApiError && error.message.length > 0 && error.message.length < 120) {
      return error.message;
    }
    return fallback;
  }

  @Builder
  private quotaRingCard() {
    Column({ space: 10 }) {
      Stack({ alignContent: Alignment.Center }) {
        Canvas(this.ringContext)
          .width(126)
          .height(126)
          .onReady(() => this.drawQuotaRing())
          .onAreaChange(() => this.drawQuotaRing())
        Column()
          .width(94)
          .height(94)
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .borderRadius(47)
        Column({ space: 1 }) {
          Text(this.ringValue())
            .fontSize(23)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(27)
            .maxLines(1)
          Text(this.ringCaption())
            .fontSize(10.5)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(14)
            .maxLines(1)
          Text(this.ringDetail())
            .fontSize(10.5)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(14)
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Center)
      }
      .width('100%')
      .height(126)

      Row({ space: 0 }) {
        this.quotaStat('已用', this.ocrUsed.toString() + ' 次')
        this.quotaStatDivider()
        this.quotaStat('剩余', this.ocrRemaining().toString() + ' 次')
        this.quotaStatDivider()
        this.quotaStat('总额度', this.ocrQuota > 0 ? this.ocrQuota.toString() + ' 次' : '暂无')
      }
      .width('100%')
      .height(40)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height(188)
    .padding({ left: 12, right: 12, top: 12, bottom: 10 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(16)
    .opacity(this.ringEntered ? 1 : 0)
    .translate({ y: this.ringEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private quotaStat(label: string, value: string) {
    Column({ space: 2 }) {
      Text(value)
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(18)
        .maxLines(1)
      Text(label)
        .fontSize(10.5)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .lineHeight(14)
        .maxLines(1)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private quotaStatDivider() {
    Column()
      .width(AppTheme.HAIRLINE)
      .height(30)
      .backgroundColor(AppTheme.COLOR_LINE_SOFT)
  }

  @Builder
  private quotaListRow(mark: string, title: string, meta: string, badge: string, tone: 'neutral' | 'ok' | 'warn' | 'danger' | 'dark') {
    Row({ space: 10 }) {
      HtmlFileMark({ label: mark, tone: 'neutral' })
      Column({ space: 3 }) {
        Text(title)
          .fontSize(13.5)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(18)
          .maxLines(1)
          .width('100%')
        Text(meta)
          .fontSize(11.5)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(16)
          .maxLines(2)
          .width('100%')
      }
      .layoutWeight(1)
      HtmlBadge({ label: badge, tone: tone })
    }
    .width('100%')
    .height(70)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private quotaListCard() {
    Column({ space: 0 }) {
      if (this.stage === 'free') {
        this.quotaListRow('DOC', 'OCR quota', this.ocrQuotaMeta(), this.ocrBadgeLabel(), this.badgeTone(this.ocrPercent()))
        this.rowDivider()
        this.quotaListRow('AI', 'AI tokens', '需连接自有 Provider', 'BYOK', 'neutral')
      } else if (this.stage === 'warning') {
        this.quotaListRow('DOC', 'OCR quota', this.ocrQuotaMeta(), this.ocrBadgeLabel(), this.badgeTone(this.ocrPercent()))
        this.rowDivider()
        this.quotaListRow('AI', 'AI tokens', this.aiUsageMeta(), this.aiBadgeLabel(), this.aiBadgeTone())
      } else if (this.stage === 'activationSuccess') {
        this.quotaListRow('DOC', 'OCR quota', this.ocrQuotaMeta(), this.ocrBadgeLabel(), this.badgeTone(this.ocrPercent()))
        this.rowDivider()
        this.quotaListRow('AI', 'AI tokens', this.aiQuota > 0 ? this.usageMeta(this.aiUsed, this.aiQuota, '次') : '需连接自有 Provider', this.aiBadgeLabel(), this.aiBadgeTone())
      } else {
        this.quotaListRow('DOC', 'OCR quota', this.ocrQuotaMeta(), this.ocrBadgeLabel(), this.badgeTone(this.ocrPercent()))
        this.rowDivider()
        this.quotaListRow('AI', 'AI tokens', this.aiUsageMeta(), this.aiBadgeLabel(), this.aiBadgeTone())
        this.rowDivider()
        this.quotaListRow('PRO', 'Batch concurrency', '并发能力以服务端账户限制为准', '账户', 'neutral')
      }
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 2, bottom: 2 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(16)
    .opacity(this.usageEntered ? 1 : 0)
    .translate({ y: this.usageEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private rowDivider() {
    Column()
      .width('100%')
      .height(AppTheme.HAIRLINE)
      .backgroundColor(AppTheme.COLOR_LINE_SOFT)
      .margin({ left: 50 })
  }

  @Builder
  private activationRedeemBlock() {
    Column({ space: 9 }) {
      HtmlSectionHead({ title: '兑换激活码', meta: '升级会员' })
      Column({ space: 0 }) {
        Column({ space: 7 }) {
          Text('激活码')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .width('100%')
          TextInput({ placeholder: 'PRO-XXXX-XXXX-XXXX', text: this.activationCode })
            .width('100%')
            .height(42)
            .fontSize(15)
            .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
            .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
            .borderRadius(13)
            .onChange((value: string) => this.handleActivationInput(value))
        }
        .width('100%')
        .padding({ left: 13, right: 13, top: 13, bottom: 13 })

        this.rowDivider()

        Column() {
          TextActionButton({
            label: this.activationSubmitting ? '兑换中' : '兑换激活码',
            primary: true,
            enabledState: this.loggedIn && !this.activationSubmitting && this.activationCode.trim().length > 0,
            onTap: () => this.redeemActivationCode()
          })
        }
        .width('100%')
        .padding({ left: 13, right: 13, top: 13, bottom: 13 })

        Column() {
          this.emptyNote('激活码兑换后立即生效并更新会员等级。明文激活码仅用于本次兑换，不会被保存或再次显示。')
        }
        .width('100%')
        .padding({ left: 13, right: 13, top: 2, bottom: 13 })
      }
      .width('100%')
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(16)
    }
    .width('100%')
    .opacity(this.activationEntered ? 1 : 0)
    .translate({ y: this.activationEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private emptyNote(message: string) {
    Text(message)
      .width('100%')
      .padding({ left: 13, right: 13, top: 12, bottom: 12 })
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
      .lineHeight(18)
      .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE })
      .borderRadius(14)
  }

  @Builder
  private inlineNotice(tone: string, title: string, body: string) {
    Row({ space: 10 }) {
      this.noticeIcon(tone)
      Column({ space: 2 }) {
        Text(title)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.noticeColor(tone))
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
        Text(body)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.noticeColor(tone))
          .opacity(0.85)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(this.noticeBackground(tone))
    .border({ width: AppTheme.HAIRLINE, color: this.noticeBorder(tone) })
    .borderRadius(12)
  }

  @Builder
  private noticeIcon(tone: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (tone === 'success') {
        Column()
          .width(16)
          .height(16)
          .border({ width: 1.8, color: this.noticeColor(tone) })
          .borderRadius(8)
        Column()
          .width(6)
          .height(1.8)
          .backgroundColor(this.noticeColor(tone))
          .rotate({ angle: 42 })
          .translate({ x: -3, y: 2 })
        Column()
          .width(10)
          .height(1.8)
          .backgroundColor(this.noticeColor(tone))
          .rotate({ angle: -42 })
          .translate({ x: 2, y: 1 })
      } else {
        Column()
          .width(16)
          .height(16)
          .border({ width: 1.8, color: this.noticeColor(tone) })
          .borderRadius(8)
        Column()
          .width(1.8)
          .height(7)
          .backgroundColor(this.noticeColor(tone))
          .translate({ y: -2 })
        Column()
          .width(2)
          .height(2)
          .backgroundColor(this.noticeColor(tone))
          .borderRadius(1)
          .translate({ y: 6 })
      }
    }
    .width(18)
    .height(18)
    .margin({ top: 1 })
  }

  private noticeColor(tone: string): string {
    if (tone === 'success') {
      return AppTheme.COLOR_SUCCESS;
    }
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER;
    }
    return AppTheme.COLOR_WARNING;
  }

  private noticeBackground(tone: string): string {
    if (tone === 'success') {
      return AppTheme.COLOR_SUCCESS_BG;
    }
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER_BG;
    }
    return AppTheme.COLOR_WARNING_BG;
  }

  private noticeBorder(tone: string): string {
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER_LINE;
    }
    if (tone === 'success') {
      return AppTheme.COLOR_LINE_SOFT;
    }
    return AppTheme.COLOR_WARNING_LINE;
  }

  @Builder
  private stateBlock(tag: string, title: string, body: string, tone: string, actionMode: string) {
    Column({ space: 0 }) {
      this.stateIcon(tone)
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(20)
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })
        .width('100%')
      Text(body)
        .fontSize(12.5)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(19)
        .textAlign(TextAlign.Center)
        .margin({ top: 5 })
        .width(240)
      Text(tag)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.stateToneColor(tone))
        .padding({ left: 10, right: 10, top: 3, bottom: 3 })
        .border({ width: AppTheme.HAIRLINE, color: this.stateToneBorder(tone) })
        .borderRadius(AppTheme.RADIUS_BADGE)
        .margin({ top: 7 })

      this.stateActions(actionMode)
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 24, bottom: 20 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(16)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private stateIcon(tone: string) {
    Stack({ alignContent: Alignment.Center }) {
      if (tone === 'success') {
        Column()
          .width(24)
          .height(24)
          .border({ width: 1.8, color: this.stateToneColor(tone) })
          .borderRadius(12)
        Column()
          .width(8)
          .height(2)
          .backgroundColor(this.stateToneColor(tone))
          .rotate({ angle: 42 })
          .translate({ x: -4, y: 3 })
        Column()
          .width(14)
          .height(2)
          .backgroundColor(this.stateToneColor(tone))
          .rotate({ angle: -42 })
          .translate({ x: 3, y: 1 })
      } else {
        HtmlFileMark({ label: tone === 'danger' ? 'PRO' : 'DOC', tone: 'neutral' })
      }
    }
    .width(52)
    .height(52)
    .backgroundColor(this.stateToneBackground(tone))
    .borderRadius(16)
  }

  @Builder
  private stateActions(actionMode: string) {
    if (actionMode === 'submitting') {
      Column({ space: 10 }) {
        this.skeletonRow()
        this.skeletonRow()
      }
      .width('100%')
      .margin({ top: 18 })
    } else if (actionMode === 'login') {
      Row({ space: 9 }) {
        TextActionButton({ label: '去登录', primary: true, onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.LOGIN) })
          .layoutWeight(1)
        TextActionButton({ label: '注册新账号', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.REGISTER) })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    } else if (actionMode === 'retry') {
      Row({ space: 9 }) {
        TextActionButton({ label: '重试', primary: true, onTap: () => this.loadMembership() })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    } else if (actionMode === 'home') {
      Row({ space: 9 }) {
        TextActionButton({ label: '返回首页', onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.HOME) })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    } else if (actionMode === 'activation') {
      Row({ space: 9 }) {
        TextActionButton({ label: '去兑换激活码', primary: true, onTap: () => this.stage = 'activationInput' })
          .layoutWeight(1)
        TextActionButton({ label: '返回我的', onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.PROFILE) })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    } else if (actionMode === 'upgradeDisabled') {
      Row({ space: 9 }) {
        TextActionButton({ label: '在线升级暂未开放', enabledState: false, onTap: () => {} })
          .layoutWeight(1)
        TextActionButton({ label: '查看说明', onTap: () => this.stage = 'proUnavailable' })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    }
  }

  @Builder
  private skeletonRow() {
    Column()
      .width('100%')
      .height(62)
      .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(14)
  }

  private stateToneColor(tone: string): string {
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER;
    }
    if (tone === 'warnish') {
      return AppTheme.COLOR_WARNING;
    }
    if (tone === 'success') {
      return AppTheme.COLOR_SUCCESS;
    }
    return AppTheme.COLOR_TEXT_SUBTLE;
  }

  private stateToneBackground(tone: string): string {
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER_BG;
    }
    if (tone === 'warnish') {
      return AppTheme.COLOR_WARNING_BG;
    }
    if (tone === 'success') {
      return AppTheme.COLOR_SUCCESS_BG;
    }
    return AppTheme.COLOR_SURFACE_SOFT;
  }

  private stateToneBorder(tone: string): string {
    if (tone === 'danger') {
      return AppTheme.COLOR_DANGER_LINE;
    }
    if (tone === 'warnish') {
      return AppTheme.COLOR_WARNING_LINE;
    }
    return AppTheme.COLOR_LINE_SOFT;
  }

  @Builder
  private freeContent() {
    this.quotaRingCard()
    HtmlSectionHead({ title: 'Free Plan', meta: '基础额度' })
    this.quotaListCard()
    this.activationRedeemBlock()
    this.stateBlock('升级方式', '通过激活码升级到 Pro / Team', '当前为 Free Plan。可使用上方的激活码兑换升级；在线购买 / 支付开通暂未开放。', 'neutral', 'upgradeDisabled')
  }

  @Builder
  private normalContent() {
    this.quotaRingCard()
    HtmlSectionHead({ title: '本月额度', meta: this.planTitle() })
    this.quotaListCard()
    this.activationRedeemBlock()
  }

  @Builder
  private warningContent() {
    this.quotaRingCard()
    this.stateBlock('额度预警', 'OCR 额度即将用尽', '本月 OCR quota 已使用 ' + this.ocrPercent().toString() + '%。继续使用可能很快触及上限。可用激活码升级更高额度，或等待下月重置。在线支付升级暂未开放。', 'warnish', 'upgradeDisabled')
    this.activationRedeemBlock()
    this.quotaListCard()
  }

  @Builder
  private exhaustedContent() {
    this.quotaRingCard()
    this.stateBlock('额度耗尽', '本月额度已用尽', 'OCR quota 已达上限，新的识别任务将受限。可使用激活码升级立即恢复，或等待下月额度重置。在线支付升级暂未开放。', 'danger', 'home')
    this.quotaListCard()
    this.activationRedeemBlock()
  }

  @Builder
  private activationInputContent() {
    this.quotaRingCard()
    this.activationRedeemBlock()
    this.emptyNote('激活码格式形如 PRO-XXXX-XXXX-XXXX。若激活码无效、已被使用或已过期，将在兑换后提示，不会改变当前等级。')
  }

  @Builder
  private activationSubmittingContent() {
    this.quotaRingCard()
    this.stateBlock('兑换中', '正在兑换激活码', '正在校验并兑换激活码，请勿重复提交。校验通过后会员等级与额度将立即更新。', 'neutral', 'submitting')
  }

  @Builder
  private activationSuccessContent() {
    this.inlineNotice('success', '激活码兑换成功', '会员等级与额度已更新，激活码已失效并清空')
    this.quotaRingCard()
    HtmlSectionHead({ title: '会员已升级', meta: this.planTitle() })
    this.quotaListCard()
    this.emptyNote('明文激活码不再展示，也不会保存到任何界面。可在「本月额度」查看更新后的配额。')
  }

  @Builder
  private activationFailureContent() {
    this.inlineNotice('danger', '兑换失败', this.errorMessage.length > 0 ? this.errorMessage : '激活码无效、已被使用或已过期')
    this.quotaRingCard()
    this.activationRedeemBlock()
    this.emptyNote('当前会员等级保持不变。请核对激活码后重试；同一激活码只能被兑换一次。')
  }

  @Builder
  private proUnavailableContent() {
    this.stateBlock('在线升级暂未开放', '在线购买 / 支付升级暂未开放', '当前版本未开放在线支付购买会员。升级请通过管理员发放的激活码在「兑换激活码」中完成；Team 团队版能力将在后续开放。', 'warnish', 'activation')
  }

  @Builder
  private backendErrorContent() {
    this.stateBlock('后端不可用', '无法加载额度信息', this.errorMessage.length > 0 ? this.errorMessage : '当前无法连接服务器，额度使用情况暂时无法显示。请检查网络后重试。', 'danger', 'retry')
  }

  @Builder
  private guestDisabledContent() {
    this.stateBlock('游客 · 禁用', '会员额度需要登录', '登录后可查看账户会员等级、OCR quota、AI tokens 和激活码兑换状态。未登录状态不会展示任何额度数字。', 'neutral', 'login')
  }

  @Builder
  private quotaStageContent() {
    if (this.stage === 'loading') {
      this.stateBlock('同步', '正在读取额度', '只查询当前登录用户的套餐和用量数字，不读取 OCR 文本、文件路径或支付信息。', 'neutral', 'submitting')
    } else if (this.stage === 'guestDisabled') {
      this.guestDisabledContent()
    } else if (this.stage === 'backendError') {
      this.backendErrorContent()
    } else if (this.stage === 'proUnavailable') {
      this.proUnavailableContent()
    } else if (this.stage === 'activationSubmitting') {
      this.activationSubmittingContent()
    } else if (this.stage === 'activationSuccess') {
      this.activationSuccessContent()
    } else if (this.stage === 'activationFailure') {
      this.activationFailureContent()
    } else if (this.stage === 'activationInput') {
      this.activationInputContent()
    } else if (this.stage === 'warning') {
      this.warningContent()
    } else if (this.stage === 'exhausted') {
      this.exhaustedContent()
    } else if (this.stage === 'normal') {
      this.normalContent()
    } else {
      this.freeContent()
    }
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({
            title: '会员额度',
            subtitle: 'QuotaCenterPage · 使用量与升级建议',
            actionLabel: '···',
            actionIcon: 'sun',
            onAction: () => this.loadMembership()
          })

          this.quotaStageContent()

          if (this.noticeMessage.length > 0 && this.stage !== 'activationSuccess') {
            this.inlineNotice('success', '额度状态', this.noticeMessage)
          }
        }
        .width('100%')
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: 4, bottom: 84 })
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
