import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import {
  HtmlAppBar,
  HtmlBadge,
  HtmlBadgeTone,
  HtmlListRow,
  HtmlSectionHead,
  HtmlStatusBar,
  HtmlToolChip,
  StatusBanner
} from '../components/BrandComponents';
import {
  AdminAuditLogResponse,
  AdminCapabilityResponse,
  AdminFeedbackResponse,
  AdminRecordResponse,
  AdminUsageSummaryResponse,
  AdminUserResponse
} from '../features/v2/V2Models';
import { V2Service } from '../features/v2/V2Service';

/**
 * AdminDashboardPage 按 v3.3 canonical HTML 重塑移动端管理员后台。
 * 所属模块：Admin 管理入口。维护边界：只展示真实 Admin API 返回的脱敏聚合与列表数据，
 * 不展示 OCR 全文、objectKey、Token、API Key、一次性明文激活码，也不伪造任何运营写操作成功。
 */
@Entry
@Component
struct AdminDashboardPage {
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State summary?: AdminUsageSummaryResponse = undefined;
  @State users: AdminUserResponse[] = [];
  @State records: AdminRecordResponse[] = [];
  @State feedback: AdminFeedbackResponse[] = [];
  @State auditLogs: AdminAuditLogResponse[] = [];
  @State adminAllowed: boolean = false;
  @State capabilityChecked: boolean = false;
  @State activeStage: string = 'loaded';
  @State statsEntered: boolean = false;
  @State listEntered: boolean = false;
  @State pressedEntry: string = '';
  @State noticeTitle: string = '';
  @State noticeMessage: string = '';

  aboutToAppear(): void {
    this.triggerCardReveal();
    this.loadAdminData();
  }

  private triggerCardReveal(): void {
    this.revealCard(() => this.statsEntered = true, 0);
    this.revealCard(() => this.listEntered = true, 1);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  /**
   * 先校验 Admin 权限，再读取管理数据；无权限时立即清空状态，避免泄露旧的管理列表。
   */
  private async loadAdminData(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    this.noticeTitle = '';
    this.noticeMessage = '';
    this.capabilityChecked = false;
    try {
      const capability: AdminCapabilityResponse = await V2Service.getAdminCapability();
      this.capabilityChecked = true;
      if (!capability.admin) {
        this.adminAllowed = false;
        this.clearAdminData();
        this.activeStage = 'permissionDenied';
        this.errorMessage = '当前账号没有 Admin 权限。如需访问管理后台，请联系系统管理员分配 Admin 角色。';
        return;
      }

      this.summary = await V2Service.getAdminSummary();
      this.users = await V2Service.listAdminUsers();
      this.records = await V2Service.listAdminRecords();
      this.feedback = await V2Service.listAdminFeedback();
      this.auditLogs = await V2Service.listAdminAuditLogs();
      this.adminAllowed = true;
      this.activeStage = this.totalAdminRows() === 0 ? 'emptyLists' : 'loaded';
    } catch (_) {
      this.clearAdminData();
      this.adminAllowed = false;
      this.capabilityChecked = true;
      this.activeStage = 'permissionDenied';
      this.errorMessage = '管理数据暂不可用。请确认当前账号已绑定管理员权限，并检查网络或后端服务状态。';
    } finally {
      this.loading = false;
    }
  }

  private clearAdminData(): void {
    this.summary = undefined;
    this.users = [];
    this.records = [];
    this.feedback = [];
    this.auditLogs = [];
  }

  private totalAdminRows(): number {
    return this.users.length + this.records.length + this.feedback.length + this.auditLogs.length;
  }

  private adminValue(value?: number): string {
    return value === undefined ? '-' : value.toString();
  }

  private activeChip(stage: string): boolean {
    return this.activeStage === stage;
  }

  private statusTone(status: string): HtmlBadgeTone {
    const normalized = status.toLowerCase();
    if (normalized.indexOf('active') >= 0 || normalized.indexOf('success') >= 0 ||
      normalized.indexOf('done') >= 0 || normalized.indexOf('normal') >= 0 ||
      normalized.indexOf('replied') >= 0) {
      return 'ok';
    }
    if (normalized.indexOf('pending') >= 0 || normalized.indexOf('open') >= 0 ||
      normalized.indexOf('todo') >= 0 || normalized.indexOf('wait') >= 0) {
      return 'warn';
    }
    if (normalized.indexOf('delete') >= 0 || normalized.indexOf('disabled') >= 0 ||
      normalized.indexOf('failed') >= 0 || normalized.indexOf('revoked') >= 0) {
      return 'danger';
    }
    return 'neutral';
  }

  private setStage(stage: string): void {
    this.activeStage = stage;
    this.noticeTitle = '';
    this.noticeMessage = '';
  }

  /**
   * 所有缺少移动端真实接线的运营动作统一进入 operationDisabled，不做本地成功态。
   */
  private showDisabledOperation(title: string, reason: string): void {
    this.activeStage = 'operationDisabled';
    this.noticeTitle = title;
    this.noticeMessage = reason;
  }

  private showMissingWrite(action: string): void {
    this.showDisabledOperation(action, '真实后端只允许会员调整和手工订单写入；移动端本页尚未提供二次确认、额度表单和审计复核，因此保持禁用，不伪造提交成功。');
  }

  @Builder
  private adminStat(value: string, label: string) {
    Column({ space: 3 }) {
      Text(value)
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .lineHeight(25)
        .maxLines(1)
        .width('100%')
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(AppTheme.LINE_CAPTION)
        .maxLines(1)
        .width('100%')
    }
    .width('100%')
    .height(73)
    .padding({ left: 12, right: 12, top: 11, bottom: 10 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private adminEntryIcon(kind: string, dark: boolean = false) {
    Stack({ alignContent: Alignment.Center }) {
      if (kind === 'user') {
        Column().width(7).height(7).border({ width: 1.45, color: dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK }).borderRadius(4).translate({ y: -6 })
        Column().width(15).height(9).border({ width: 1.45, color: dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK }).borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 4, bottomRight: 4 }).translate({ y: 6 })
      } else if (kind === 'record') {
        Column().width(12).height(16).border({ width: 1.45, color: dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK }).borderRadius(2)
        Column().width(6).height(1.45).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK).translate({ y: -2 })
      } else if (kind === 'quota') {
        Column().width(7).height(7).border({ width: 1.35, color: dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK }).borderRadius(4)
        Column().width(16).height(1.35).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK)
        Column().width(1.35).height(16).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK)
        Column().width(14).height(1.35).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK).rotate({ angle: 45 })
        Column().width(14).height(1.35).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK).rotate({ angle: -45 })
      } else if (kind === 'key') {
        Column().width(7).height(7).border({ width: 1.45, color: dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK }).borderRadius(4).translate({ x: -5 })
        Column().width(14).height(1.55).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK).translate({ x: 4 })
        Column().width(1.55).height(5).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK).translate({ x: 9, y: 3 })
      } else {
        Column().width(15).height(16).border({ width: 1.45, color: dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK }).borderRadius({ topLeft: 8, topRight: 8, bottomLeft: 7, bottomRight: 7 }).scale({ x: 0.92, y: 1 })
        Column().width(6).height(1.45).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK).rotate({ angle: 42 }).translate({ x: -3, y: 2 })
        Column().width(9).height(1.45).backgroundColor(dark ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND_DARK).rotate({ angle: -42 }).translate({ x: 2, y: 1 })
      }
    }
    .width(38)
    .height(44)
    .backgroundColor(dark ? AppTheme.COLOR_DARK : AppTheme.COLOR_SURFACE_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }

  @Builder
  private adminEntryRow(stage: string, icon: string, title: string, meta: string, badge: string, tone: HtmlBadgeTone) {
    Button() {
      Row({ space: 12 }) {
        this.adminEntryIcon(icon, false)
        Column({ space: 3 }) {
          Text(title)
            .fontSize(13.5)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(AppTheme.LINE_META)
            .maxLines(1)
            .width('100%')
          Text(meta)
            .fontSize(11.5)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(AppTheme.LINE_CAPTION)
            .maxLines(1)
            .width('100%')
        }
        .layoutWeight(1)
        HtmlBadge({ label: badge, tone: tone })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(66)
    .type(ButtonType.Normal)
    .backgroundColor(AppTheme.COLOR_TRANSPARENT)
    .padding({ left: 0, right: 0, top: 2, bottom: 2 })
    .scale({ x: this.pressedEntry === title ? AppMotion.PRESS_SCALE : 1, y: this.pressedEntry === title ? AppMotion.PRESS_SCALE : 1 })
    .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedEntry = title;
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressedEntry = '';
      }
    })
    .onClick(() => this.setStage(stage))
  }

  @Builder
  private adminEntries() {
    List({ space: 0 }) {
      ListItem() {
        this.adminEntryRow('userMgmt', 'user', '用户管理', '成员、角色、登录状态', 'Team', 'neutral')
      }
      ListItem() {
        this.adminEntryRow('recordMgmt', 'record', '文档 / 记录管理', '文档状态、删除申请、异常记录', 'Records', 'neutral')
      }
      ListItem() {
        this.adminEntryRow('feedback', 'record', '反馈管理', '识别错误、导出失败、功能建议', this.feedback.length.toString(), this.feedback.length > 0 ? 'warn' : 'neutral')
      }
      ListItem() {
        this.adminEntryRow('quotaMgmt', 'quota', '额度 / 成员管理', 'OCR quota、AI tokens、Batch concurrency', 'Plan', 'neutral')
      }
      ListItem() {
        this.adminEntryRow('auditLog', 'audit', '审计日志', '导出、删除、Provider 调用记录', 'Audit', 'dark')
      }
      ListItem() {
        this.adminEntryRow('activationEntry', 'key', '激活码管理', '生成 / 列表 / 撤销 · Web Admin Console', 'Web', 'neutral')
      }
    }
    .width('100%')
    .height(418)
    .scrollBar(BarState.Off)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    .opacity(this.listEntered ? 1 : 0)
    .translate({ y: this.listEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
  }

  @Builder
  private stageChips() {
    Scroll() {
      Row({ space: 8 }) {
        this.adminStageChip('概览', 'loaded')
        this.adminStageChip('用户', 'userMgmt')
        this.adminStageChip('记录', 'recordMgmt')
        this.adminStageChip('反馈', 'feedback')
        this.adminStageChip('额度', 'quotaMgmt')
        this.adminStageChip('审计', 'auditLog')
        this.adminStageChip('激活码', 'activationEntry')
      }
      .padding({ right: 2 })
    }
    .width('100%')
    .height(42)
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
  }

  @Builder
  private adminStageChip(label: string, stage: string) {
    Button(label)
      .height(38)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.activeChip(stage) ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_TEXT_MUTED)
      .backgroundColor(this.activeChip(stage) ? AppTheme.COLOR_BRAND_SOFT : AppTheme.COLOR_SURFACE_ELEVATED)
      .padding({ left: 12, right: 12 })
      .border({ width: AppTheme.HAIRLINE, color: this.activeChip(stage) ? AppTheme.COLOR_ACCENT_SOFT : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .onClick(() => this.setStage(stage))
  }

  @Builder
  private overview() {
    HtmlSectionHead({ title: '管理概览', meta: 'Admin 有权限时可见' })
    Grid() {
      GridItem() {
        this.adminStat(this.adminValue(this.summary?.totalUsers), '成员')
      }
      GridItem() {
        this.adminStat(this.adminValue(this.summary?.ocrUsed), '本月 OCR pages')
      }
      GridItem() {
        this.adminStat(this.adminValue(this.summary?.totalFeedback), '待处理反馈')
      }
      GridItem() {
        this.adminStat(this.adminValue(this.summary?.totalRecords), '记录')
      }
    }
    .columnsTemplate('1fr 1fr')
    .columnsGap(10)
    .rowsGap(10)
    .width('100%')
    .opacity(this.statsEntered ? 1 : 0)
    .translate({ y: this.statsEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

    HtmlSectionHead({ title: '管理入口', meta: 'Admin only' })
    this.adminEntries()
  }

  @Builder
  private emptyLists() {
    StatusBanner({
      label: '空列表',
      title: '暂无管理数据',
      message: '当前没有待处理的用户、记录、反馈或审计日志。新成员加入或用户提交反馈后，真实列表会出现在这里。',
      tone: 'neutral'
    })
    this.overview()
  }

  @Builder
  private disabledActionChip(label: string, onTap: () => void) {
    Button(label)
      .height(38)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(FontWeight.Bold)
      .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
      .backgroundColor(AppTheme.COLOR_NEUTRAL_BG)
      .padding({ left: 12, right: 12 })
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .opacity(0.72)
      .onClick(() => onTap())
  }

  @Builder
  private actionStrip(kind: string) {
    Row({ space: 8 }) {
      HtmlToolChip({ label: '返回概览', primary: false, onTap: () => this.setStage('loaded') })
      if (kind === 'user') {
        this.disabledActionChip('调整会员', () => this.showMissingWrite('调整会员'))
        this.disabledActionChip('手工订单', () => this.showMissingWrite('创建手工订单'))
        this.disabledActionChip('封禁用户', () => this.showDisabledOperation('封禁用户不可用', '真实 AdminController 没有封禁用户接口，移动端不会提交或伪造封禁成功。'))
      } else if (kind === 'record') {
        this.disabledActionChip('管理员删除', () => this.showDisabledOperation('管理员删除不可用', '真实 AdminController 只提供记录读取接口，没有管理员删除 OCR 记录接口。'))
        this.disabledActionChip('批量删除', () => this.showDisabledOperation('批量删除不可用', '真实后端没有 Admin 批量删除记录接口，本页只读展示记录元数据。'))
      } else if (kind === 'feedback') {
        this.disabledActionChip('回复反馈', () => this.showDisabledOperation('回复反馈不可用', '真实 AdminController 只提供反馈读取接口，没有回复反馈接口。'))
      } else if (kind === 'quota') {
        this.disabledActionChip('假支付/升级', () => this.showDisabledOperation('在线升级不可用', '后端没有支付或在线购买接口，会员升级只能走真实激活码兑换或管理员真实写接口。'))
      }
    }
    .width('100%')
  }

  @Builder
  private emptyCard(message: string) {
    Column({ space: 4 }) {
      Text(message)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT)
        .width('100%')
      Text('仅显示后端返回的真实脱敏数据，不补视觉占位行。')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .width('100%')
    }
    .width('100%')
    .height(74)
    .padding({ left: 12, right: 12 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private userPanel() {
    HtmlSectionHead({ title: '用户管理', meta: '成员、角色、登录状态' })
    if (this.users.length === 0) {
      this.emptyCard('暂无用户数据')
    } else {
      List({ space: 0 }) {
        ForEach(this.users.slice(0, 8), (user: AdminUserResponse, index?: number) => {
          ListItem() {
            HtmlListRow({
              index: index === undefined ? 0 : index,
              mark: 'ADM',
              title: user.username,
              meta: user.membershipLevel + ' · ' + user.status,
              badge: user.membershipLevel,
              tone: user.membershipLevel.toLowerCase().indexOf('admin') >= 0 ? 'dark' : this.statusTone(user.status),
              onTap: () => this.showMissingWrite('用户写操作')
            })
          }
        }, (user: AdminUserResponse) => user.id.toString())
      }
      .width('100%')
      .height(Math.min(this.users.length, 8) * 66 + 12)
      .scrollBar(BarState.Off)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)
      .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    }
    this.actionStrip('user')
  }

  @Builder
  private recordPanel() {
    HtmlSectionHead({ title: '记录管理', meta: '文档状态、删除申请' })
    if (this.records.length === 0) {
      this.emptyCard('暂无记录数据')
    } else {
      List({ space: 0 }) {
        ForEach(this.records.slice(0, 8), (record: AdminRecordResponse, index?: number) => {
          ListItem() {
            HtmlListRow({
              index: index === undefined ? 0 : index,
              mark: 'DOC',
              title: record.title,
              meta: record.sourceType + ' · 文本长度 ' + record.textLength.toString(),
              badge: record.sourceType,
              tone: 'neutral',
              onTap: () => this.showDisabledOperation('记录写操作不可用', '本页只展示 Admin 记录元数据；后端没有管理员删除 OCR 记录接口。')
            })
          }
        }, (record: AdminRecordResponse) => record.id.toString())
      }
      .width('100%')
      .height(Math.min(this.records.length, 8) * 66 + 12)
      .scrollBar(BarState.Off)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)
      .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    }
    this.actionStrip('record')
  }

  @Builder
  private feedbackPanel() {
    HtmlSectionHead({ title: '反馈管理', meta: '识别错误、导出失败、建议' })
    if (this.feedback.length === 0) {
      this.emptyCard('暂无反馈数据')
    } else {
      List({ space: 0 }) {
        ForEach(this.feedback.slice(0, 8), (item: AdminFeedbackResponse, index?: number) => {
          ListItem() {
            HtmlListRow({
              index: index === undefined ? 0 : index,
              mark: 'DOC',
              title: item.feedbackType,
              meta: (item.createdAt === undefined ? '反馈' : item.createdAt) + ' · ' + item.status,
              badge: item.status,
              tone: this.statusTone(item.status),
              onTap: () => this.showDisabledOperation('回复反馈不可用', '真实 AdminController 没有反馈回复接口，本页不会生成回复成功态。')
            })
          }
        }, (item: AdminFeedbackResponse) => item.id.toString())
      }
      .width('100%')
      .height(Math.min(this.feedback.length, 8) * 66 + 12)
      .scrollBar(BarState.Off)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)
      .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    }
    this.actionStrip('feedback')
  }

  @Builder
  private quotaPanel() {
    HtmlSectionHead({ title: '额度 / 成员管理', meta: 'OCR quota、AI tokens' })
    List({ space: 0 }) {
      ListItem() {
        HtmlListRow({ index: 0, mark: 'PRO', title: '团队 OCR quota', meta: '真实累计用量', badge: this.adminValue(this.summary?.ocrUsed), tone: 'neutral' })
      }
      ListItem() {
        HtmlListRow({ index: 1, mark: 'AI', title: '团队 AI tokens', meta: '真实累计用量', badge: this.adminValue(this.summary?.aiUsed), tone: 'neutral' })
      }
      ListItem() {
        HtmlListRow({ index: 2, mark: 'OUT', title: '导出用量', meta: '真实累计用量', badge: this.adminValue(this.summary?.exportUsed), tone: 'neutral' })
      }
    }
    .width('100%')
    .height(210)
    .scrollBar(BarState.Off)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    this.actionStrip('quota')
  }

  @Builder
  private auditPanel() {
    HtmlSectionHead({ title: '审计日志', meta: '导出、删除、Provider 调用' })
    if (this.auditLogs.length === 0) {
      this.emptyCard('暂无审计日志')
    } else {
      List({ space: 0 }) {
        ForEach(this.auditLogs.slice(0, 8), (log: AdminAuditLogResponse, index?: number) => {
          ListItem() {
            HtmlListRow({
              index: index === undefined ? 0 : index,
              mark: 'ADM',
              title: log.action,
              meta: log.targetType + (log.targetId === undefined ? '' : ' · #' + log.targetId.toString()),
              badge: 'Audit',
              tone: 'dark'
            })
          }
        }, (log: AdminAuditLogResponse) => log.id.toString())
      }
      .width('100%')
      .height(Math.min(this.auditLogs.length, 8) * 66 + 12)
      .scrollBar(BarState.Off)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)
      .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    }
    this.actionStrip('audit')
  }

  @Builder
  private activationPanel() {
    /**
     * 激活码生成接口会返回一次性明文 code；移动端本页不承载生成、明文展示或撤销，避免在手机界面泄露敏感凭据。
     */
    HtmlSectionHead({ title: '激活码管理', meta: 'Web Admin Console' })
    List({ space: 0 }) {
      ListItem() {
        HtmlListRow({
          index: 0,
          mark: 'AI',
          title: '在 Web 控制台管理激活码',
          meta: '生成、列表与撤销已降级为 Web Admin Console 能力',
          badge: 'Web',
          tone: 'neutral'
        })
      }
      ListItem() {
        HtmlListRow({
          index: 1,
          mark: 'PRO',
          title: '移动端不展示明文 code',
          meta: '不展示完整 code 或一次性生成结果',
          badge: 'Masked',
          tone: 'dark'
        })
      }
    }
    .width('100%')
    .height(144)
    .scrollBar(BarState.Off)
    .padding({ left: 12, right: 12, top: 6, bottom: 6 })
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
    .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
    StatusBanner({
      label: '移动端限制',
      title: '生成 / 撤销请在 Web Admin Console 操作',
      message: '本页只保留入口说明，不生成或展示一次性明文激活码。',
      tone: 'warning'
    })
    Row() {
      HtmlToolChip({
        label: '去会员额度页兑换',
        primary: true,
        onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.QUOTA_CENTER)
      })
    }
    .width('100%')
  }

  @Builder
  private operationDisabledPanel() {
    this.adminEntries()
    StatusBanner({
      label: '操作禁用',
      title: this.noticeTitle.length > 0 ? this.noticeTitle : '该操作当前不可用',
      message: this.noticeMessage.length > 0 ? this.noticeMessage : '删除、封禁、回复反馈、批量操作、假支付或假升级没有真实后端能力；会员调整和手工订单虽有真实接口，但本页未提供安全表单与二次确认，保持禁用。',
      tone: 'warning'
    })
  }

  @Builder
  private activeStageContent() {
    if (this.activeStage === 'emptyLists') {
      this.emptyLists()
    } else if (this.activeStage === 'userMgmt') {
      this.userPanel()
    } else if (this.activeStage === 'recordMgmt') {
      this.recordPanel()
    } else if (this.activeStage === 'feedback') {
      this.feedbackPanel()
    } else if (this.activeStage === 'quotaMgmt') {
      this.quotaPanel()
    } else if (this.activeStage === 'auditLog') {
      this.auditPanel()
    } else if (this.activeStage === 'activationEntry') {
      this.activationPanel()
    } else if (this.activeStage === 'operationDisabled') {
      this.operationDisabledPanel()
    } else {
      this.overview()
    }
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 12 }) {
            HtmlAppBar({
              title: 'Admin 后台',
              subtitle: 'AdminDashboardPage · 需要 Admin 角色',
              actionLabel: '刷新',
              actionIcon: 'shield',
              onAction: () => this.loadAdminData()
            })

            if (this.adminAllowed) {
              this.stageChips()
              this.activeStageContent()
            } else if (this.capabilityChecked && !this.loading) {
              StatusBanner({
                label: '权限不足',
                title: '无 Admin 权限',
                message: '你的账号没有管理员权限。如需访问管理后台，请联系系统管理员分配 Admin 角色。',
                tone: 'danger'
              })
              Row() {
                HtmlToolChip({
                  label: '返回我的',
                  primary: false,
                  onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.PROFILE)
                })
              }
              .width('100%')
            }

            if (this.loading) {
              StatusBanner({
                label: '同步',
                title: '正在读取管理数据',
                message: '先校验 Admin 权限，再加载聚合、用户、记录、反馈与审计日志。',
                tone: 'info'
              })
            }
            if (this.errorMessage.length > 0) {
              StatusBanner({
                label: '管理',
                title: '管理视图暂不可用',
                message: this.errorMessage,
                tone: this.adminAllowed ? 'warning' : 'danger'
              })
            }
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
