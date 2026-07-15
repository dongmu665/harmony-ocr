import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AppMotion } from '../common/theme/AppMotion';
import { AppBottomNav } from '../components/AppBottomNav';
import { HtmlAppBar, HtmlBadge, HtmlListRow, HtmlSectionHead, HtmlStatusBar, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { HistoryState } from '../features/history/HistoryState';
import { AiActionResponse, AiActionType, AiProviderConfigResponse } from '../features/v2/V2Models';
import { V2Service } from '../features/v2/V2Service';

/**
 * AiWorkspacePage 提供已保存 OCR 记录的 AI 文本处理界面。
 * 维护边界：前端只提交记录 ID、动作和同意标记，不上传 OCR 全文、不展示 prompt、不记录 AI 响应全文到日志。
 */
@Entry
@Component
struct AiWorkspacePage {
  @State recordIdText: string = '';
  @State selectedAction: AiActionType = 'SUMMARY';
  @State targetLanguage: string = '中文';
  @State consentAccepted: boolean = false;
  @State loading: boolean = false;
  @State consentLoading: boolean = false;
  @State errorMessage: string = '';
  @State result?: AiActionResponse = undefined;
  @State providers: AiProviderConfigResponse[] = [];
  @State providerLoading: boolean = false;
  @State providerErrorMessage: string = '';
  @State showAiResult: boolean = true;
  @State providerEntered: boolean = false;
  @State scopeEntered: boolean = false;
  @State actionEntered: boolean = false;
  @State resultEntered: boolean = false;
  @State pressedResultMode: string = '';

  aboutToAppear(): void {
    this.triggerCardReveal();
    this.loadAiConsent();
    this.loadProviders();
    const selectedRecordId = HistoryState.getCurrentRecordId();
    if (this.recordIdText.length === 0 && selectedRecordId.length > 0) {
      this.recordIdText = selectedRecordId;
    }
  }

  /**
   * 加载后端真实 BYOK Provider 列表，避免 AI 工作区展示静态演示 Provider。
   * 安全边界：列表 DTO 已由后端脱敏，不包含 API Key、密文或 provider 原始响应。
   */
  private async loadProviders(): Promise<void> {
    this.providerLoading = true;
    this.providerErrorMessage = '';
    try {
      this.providers = await V2Service.listProviders();
    } catch (_) {
      this.providers = [];
      this.providerErrorMessage = '服务连接读取失败，请确认已登录且服务可用。';
    } finally {
      this.providerLoading = false;
    }
  }

  /**
   * 从后端加载 AI 运行时隐私同意状态。
   * 说明：只同步 consent marker，不读取 OCR 全文、prompt、provider request 或密钥。
   */
  private async loadAiConsent(): Promise<void> {
    try {
      const consent = await V2Service.getAiConsent();
      this.consentAccepted = consent.accepted;
    } catch (_) {
      this.errorMessage = '处理授权状态读取失败，请确认已登录。';
    }
  }

  /**
   * 保存用户对 AI OCR 文本外发处理的运行时同意。
   * 参数 accepted 只表达用户选择；取消同意后后端会重新拦截 AI action。
   */
  private async updateAiConsent(accepted: boolean): Promise<void> {
    this.consentLoading = true;
    this.errorMessage = '';
    try {
      const consent = await V2Service.updateAiConsent({ accepted: accepted });
      this.consentAccepted = consent.accepted;
    } catch (_) {
      this.consentAccepted = !accepted;
      this.errorMessage = '处理授权状态保存失败，请稍后重试。';
    } finally {
      this.consentLoading = false;
    }
  }

  /**
   * AI 工作区沿用 HTML motion-card 的 40ms stagger，只改变进入呈现。
   */
  private triggerCardReveal(): void {
    this.revealCard(() => this.providerEntered = true, 0);
    this.revealCard(() => this.scopeEntered = true, 1);
    this.revealCard(() => this.actionEntered = true, 2);
    this.revealCard(() => this.resultEntered = true, 3);
  }

  private revealCard(update: () => void, index: number): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: AppMotion.DURATION_NORMAL, curve: Curve.EaseOut }, update);
    }, index * AppMotion.STAGGER_CARD_MS);
  }

  private parsedRecordId(): number {
    const rawValue = this.recordIdText.trim().length > 0 ? this.recordIdText.trim() : HistoryState.getCurrentRecordId();
    const value = Number(rawValue);
    return Number.isNaN(value) ? 0 : value;
  }

  /**
   * AI 服务为空时不暴露可执行 AI 动作，避免前端按钮触发后端不可用路径。
   */
  private canRunAiAction(): boolean {
    return !this.loading &&
      !this.providerLoading &&
      this.providerErrorMessage.length === 0 &&
      this.enabledProviders().length > 0 &&
      this.consentAccepted &&
      this.parsedRecordId() > 0;
  }

  /**
   * 调用后端 AI action contract。
   * 参数 recordId 必须是当前用户记录；后端负责 ownership 校验和 provider fallback。
   */
  private async runAction(): Promise<void> {
    const recordId = this.parsedRecordId();
    if (recordId <= 0) {
      this.errorMessage = '请输入要处理的历史记录编号。';
      return;
    }
    if (!this.consentAccepted) {
      this.errorMessage = '请先保存处理授权，再开始文档处理。';
      return;
    }
    if (this.enabledProviders().length === 0) {
      this.errorMessage = '请先保存可用服务连接，再开始文档处理。';
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    try {
      this.result = await V2Service.runAiAction({
        recordId: recordId,
        action: this.selectedAction,
        targetLanguage: this.targetLanguage,
        consentAccepted: true
      });
      this.showAiResult = true;
    } catch (_) {
      this.errorMessage = '文档处理失败，请确认已登录、记录存在且服务连接可用。';
    } finally {
      this.loading = false;
    }
  }

  /**
   * AI 结果展示使用轻量切换，避免原文和 AI 输出同时抢占主视觉。
   * 说明：页面不拉取 OCR 全文，只显示后端返回的安全处理结果和输入长度摘要。
   */
  @Builder
  private providerRow(provider: AiProviderConfigResponse, index: number) {
    HtmlListRow({
      index: index,
      mark: 'AI',
      title: provider.providerName,
      meta: provider.modelName + ' · ' + provider.secureStorageStatus,
      badge: provider.enabled ? (provider.defaultProvider ? '默认' : '可用') : '停用',
      tone: provider.enabled ? 'ok' : 'neutral'
    })
  }

  private enabledProviders(): AiProviderConfigResponse[] {
    return this.providers.filter((provider: AiProviderConfigResponse) => provider.enabled);
  }

  private providerMeta(): string {
    const defaultProviders = this.providers.filter((provider: AiProviderConfigResponse) => provider.defaultProvider && provider.enabled);
    if (defaultProviders.length > 0) {
      return defaultProviders[0].providerName;
    }
    const enabledCount = this.enabledProviders().length;
    return enabledCount > 0 ? enabledCount.toString() + ' 个可用' : '无可用 Provider';
  }

  @Builder
  private actionRow(title: string, meta: string, action: AiActionType, index: number) {
    Button() {
      Column({ space: 6 }) {
        Text(title)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.selectedAction === action ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_TEXT)
          .width('100%')
        Text(meta)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.selectedAction === action ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_TEXT_SUBTLE)
          .maxLines(1)
          .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(76)
    .type(ButtonType.Normal)
    .padding({ left: 13, right: 13, top: 12, bottom: 12 })
    .backgroundColor(this.selectedAction === action ? AppTheme.COLOR_TEXT : AppTheme.COLOR_SURFACE_ELEVATED)
    .border({ width: AppTheme.HAIRLINE, color: this.selectedAction === action ? AppTheme.COLOR_TEXT : AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
    .enabled(this.canRunAiAction())
    .onClick(() => {
      index;
      this.selectedAction = action;
    })
  }

  @Builder
  private resultModeSwitch() {
    Row({ space: 4 }) {
      Button('AI 结果')
        .layoutWeight(1)
        .height(36)
        .type(ButtonType.Normal)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.showAiResult ? AppTheme.COLOR_TEXT : AppTheme.COLOR_TEXT_MUTED)
        .backgroundColor(this.showAiResult ? AppTheme.COLOR_SURFACE_ELEVATED : AppTheme.COLOR_TRANSPARENT)
        .border({ width: this.showAiResult ? AppTheme.HAIRLINE : 0, color: this.showAiResult ? AppTheme.COLOR_LINE_SOFT : AppTheme.COLOR_TRANSPARENT })
        .borderRadius(AppTheme.RADIUS_CONTROL)
        .scale({ x: this.pressedResultMode === 'ai' ? AppMotion.PRESS_SCALE : 1, y: this.pressedResultMode === 'ai' ? AppMotion.PRESS_SCALE : 1 })
        .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedResultMode = 'ai';
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedResultMode = '';
          }
        })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: AppMotion.DURATION_SWITCH, curve: Curve.EaseOut }, () => {
            this.showAiResult = true;
          });
        })

      Button('原文摘要')
        .layoutWeight(1)
        .height(36)
        .type(ButtonType.Normal)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(!this.showAiResult ? AppTheme.COLOR_TEXT : AppTheme.COLOR_TEXT_MUTED)
        .backgroundColor(!this.showAiResult ? AppTheme.COLOR_SURFACE_ELEVATED : AppTheme.COLOR_TRANSPARENT)
        .border({ width: !this.showAiResult ? AppTheme.HAIRLINE : 0, color: !this.showAiResult ? AppTheme.COLOR_LINE_SOFT : AppTheme.COLOR_TRANSPARENT })
        .borderRadius(AppTheme.RADIUS_CONTROL)
        .scale({ x: this.pressedResultMode === 'source' ? AppMotion.PRESS_SCALE : 1, y: this.pressedResultMode === 'source' ? AppMotion.PRESS_SCALE : 1 })
        .animation({ duration: AppMotion.DURATION_FAST, curve: Curve.EaseOut })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.pressedResultMode = 'source';
          }
          if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.pressedResultMode = '';
          }
        })
        .onClick(() => {
          this.getUIContext().animateTo({ duration: AppMotion.DURATION_SWITCH, curve: Curve.EaseOut }, () => {
            this.showAiResult = false;
          });
        })
    }
    .width('100%')
    .padding(4)
    .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
    .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CONTROL)
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
          HtmlAppBar({ title: 'AI 工作台', subtitle: '基于当前文档的智能处理', actionLabel: '⚿', actionIcon: 'key', onAction: () => AppNavigator.push(this.getUIContext(), AppRoutes.BYOK_PROVIDER) })

          Column({ space: 8 }) {
            HtmlSectionHead({ title: 'Provider 选择', meta: this.providerMeta() })
            if (this.providerLoading) {
              StatusBanner({ label: '读取中', title: '正在读取服务连接', message: '文档处理只显示账号内已保存的服务连接。', tone: 'neutral' })
            } else if (this.providerErrorMessage.length > 0) {
              StatusBanner({ label: '错误', title: '服务连接不可用', message: this.providerErrorMessage, tone: 'danger' })
            } else if (this.providers.length === 0) {
              StatusBanner({ label: '空', title: '尚未保存服务连接', message: '请先在 AI 服务连接页面保存可用服务，再开始文档处理。', tone: 'warning' })
            } else {
              List({ space: 0 }) {
                ForEach(this.providers, (provider: AiProviderConfigResponse, index?: number) => {
                  ListItem() {
                    this.providerRow(provider, index === undefined ? 0 : index)
                  }
                }, (provider: AiProviderConfigResponse) => provider.id.toString())
              }
              .width('100%')
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
              .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
              .borderRadius(AppTheme.RADIUS_PANEL)
              .divider({ strokeWidth: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT, startMargin: 50, endMargin: 0 })
            }
          }
          .width('100%')
          .opacity(this.providerEntered ? 1 : 0)
          .translate({ y: this.providerEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

          Column({ space: 10 }) {
            HtmlSectionHead({ title: '同意门禁', meta: this.consentAccepted ? '已确认' : '等待确认' })
            TextInput({ placeholder: '历史记录编号', text: this.recordIdText })
              .width('100%')
              .height(AppTheme.INPUT_HEIGHT)
              .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
              .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
              .borderRadius(AppTheme.RADIUS_CONTROL)
              .onChange((value: string) => this.recordIdText = value)

            TextInput({ placeholder: '目标语言，翻译时使用', text: this.targetLanguage })
              .width('100%')
              .height(AppTheme.INPUT_HEIGHT)
              .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
              .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
              .borderRadius(AppTheme.RADIUS_CONTROL)
              .onChange((value: string) => this.targetLanguage = value)

            Row({ space: 8 }) {
              Toggle({ type: ToggleType.Checkbox, isOn: this.consentAccepted })
                .enabled(!this.consentLoading && !this.loading)
                .onChange((value: boolean) => {
                  this.consentAccepted = value;
                  this.updateAiConsent(value);
                })
              Text(this.consentLoading ? '正在保存处理授权...' : '我已确认当前记录可发送给已配置 Provider 处理。')
                .fontSize(AppTheme.FONT_META)
                .fontColor(AppTheme.COLOR_TEXT_MUTED)
                .layoutWeight(1)
            }
            .width('100%')

            if (this.parsedRecordId() <= 0) {
              StatusBanner({ label: '文档', title: '未选择文档', message: '请从历史记录进入，或输入当前账号拥有的历史记录编号。', tone: 'warning' })
            }
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_PANEL)
          .opacity(this.scopeEntered ? 1 : 0)
          .translate({ y: this.scopeEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

        Column({ space: 10 }) {
          HtmlSectionHead({ title: '动作列表', meta: this.canRunAiAction() ? this.providerMeta() : '未满足门禁' })
          Grid() {
            GridItem() {
              this.actionRow('摘要', '长文档要点', 'SUMMARY', 0)
            }
            GridItem() {
              this.actionRow('纠错', '错别字 / 误识', 'CORRECTION', 1)
            }
            GridItem() {
              this.actionRow('字段提取', '结构化字段', 'FIELD_EXTRACTION', 2)
            }
            GridItem() {
              this.actionRow('翻译', '目标语言转换', 'TRANSLATION', 3)
            }
            GridItem() {
              this.actionRow('智能排版', '段落与列表', 'SMART_FORMAT', 4)
            }
            GridItem() {
              this.actionRow('转 Markdown', '知识库格式', 'MARKDOWN', 5)
            }
          }
          .columnsTemplate('1fr 1fr')
          .columnsGap(10)
          .rowsGap(10)
          .width('100%')

          TextActionButton({
            label: this.loading ? '处理中...' : (this.enabledProviders().length === 0 ? '请先保存 Provider' : '开始文档处理'),
            primary: true,
            enabledState: this.canRunAiAction(),
            onTap: () => this.runAction()
          })
        }
        .width('100%')
        .padding(AppTheme.CARD_PADDING)
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)
        .opacity(this.actionEntered ? 1 : 0)
        .translate({ y: this.actionEntered ? 0 : AppMotion.ENTER_OFFSET_Y })

        if (this.result !== undefined) {
          Column({ space: 10 }) {
            HtmlSectionHead({ title: '处理结果', meta: '结果预览' })
            this.resultModeSwitch()
            Row({ space: 8 }) {
              HtmlBadge({ label: this.result.providerName, tone: 'neutral' })
              HtmlBadge({ label: this.result.modelName, tone: 'neutral' })
              HtmlBadge({ label: this.result.degraded ? '降级' : '正常', tone: this.result.degraded ? 'warn' : 'ok' })
              HtmlBadge({ label: '输入 ' + this.result.inputLength.toString() + ' 字', tone: 'dark' })
            }
            if (this.showAiResult) {
              Text(this.result.outputText)
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.COLOR_TEXT)
                .lineHeight(AppTheme.LINE_BODY)
                .width('100%')
                .maxLines(8)
            } else {
              StatusBanner({
                label: '原文',
                title: '原文按记录安全读取',
                message: '前端只提交记录编号和用户同意标记，不在 AI 页面重复传输或展示 OCR 全文。',
                tone: 'neutral'
              })
            }
            if (this.result.degraded && this.result.degradationReason && this.result.degradationReason.length > 0) {
              StatusBanner({ label: '降级', title: '已降级处理', message: this.result.degradationReason, tone: 'warning' })
            }
          }
          .width('100%')
          .padding(AppTheme.CARD_PADDING)
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_PANEL)
          .opacity(this.resultEntered ? 1 : 0)
          .translate({ y: this.resultEntered ? 0 : AppMotion.ENTER_OFFSET_Y })
        }

        if (this.errorMessage.length > 0) {
          StatusBanner({ label: '错误', title: '文档处理未完成', message: this.errorMessage, tone: 'danger' })
        }

          StatusBanner({
            label: '隐私',
            title: '发送前确认',
            message: '文档处理可能把当前记录文本发送给已配置服务；页面不展示访问密钥，也不记录完整处理内容。',
            tone: 'warning'
          })

          TextActionButton({ label: '管理服务连接', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.BYOK_PROVIDER) })
          TextActionButton({ label: '返回历史', onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.HISTORY) })
        }
        .width('100%')
        .padding(AppTheme.PAGE_PADDING)
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(AppTheme.COLOR_PAGE)

      AppBottomNav({ activeTab: 'history' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }
}
