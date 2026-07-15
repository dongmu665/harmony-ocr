import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AppBottomNav } from '../components/AppBottomNav';
import {
  HtmlAppBar,
  HtmlBadge,
  HtmlBadgeTone,
  HtmlCompactActionButton,
  HtmlFileMark,
  HtmlListRow,
  HtmlSectionHead,
  HtmlStatusBar,
  HtmlToolChip,
  StatusBanner,
  StatusTone,
  TextActionButton
} from '../components/BrandComponents';
import { AiProviderConfigRequest, AiProviderConfigResponse, AiProviderTestResponse } from '../features/v2/V2Models';
import { V2Service } from '../features/v2/V2Service';

type ByokProviderStage =
  'noProvider' |
  'providerList' |
  'addForm' |
  'editing' |
  'testSuccess' |
  'testFailed' |
  'defaultSelected' |
  'deleteConfirm' |
  'backendError';

/**
 * ByokProviderPage 管理用户自带的 AI 服务连接配置。
 * 维护边界：API Key 仅在用户输入和提交请求时短暂存在，页面不回显明文、不写日志。
 */
@Entry
@Component
struct ByokProviderPage {
  @State providers: AiProviderConfigResponse[] = [];
  @State pageStage: ByokProviderStage = 'noProvider';
  @State selectedProviderId: number = 0;
  @State providerName: string = '';
  @State baseUrl: string = '';
  @State modelName: string = '';
  @State apiKey: string = '';
  @State formEnabled: boolean = true;
  @State formDefault: boolean = false;
  @State loading: boolean = false;
  @State saving: boolean = false;
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State lastTest?: AiProviderTestResponse = undefined;

  aboutToAppear(): void {
    this.loadProviders();
  }

  /** 加载 AI 服务列表，后端响应只包含脱敏密钥元数据。 */
  private async loadProviders(nextStage?: ByokProviderStage): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    try {
      this.providers = await V2Service.listProviders();
      if (nextStage !== undefined) {
        this.pageStage = nextStage;
      } else {
        this.pageStage = this.providers.length === 0 ? 'noProvider' : 'providerList';
      }
      if (this.selectedProviderId === 0 && this.providers.length > 0) {
        this.selectedProviderId = this.providers[0].id;
      }
    } catch (_) {
      this.providers = [];
      this.pageStage = 'backendError';
      this.errorMessage = '当前无法连接 AI 服务后端，Provider 配置暂时无法加载或保存。请检查网络后重试。';
    } finally {
      this.loading = false;
    }
  }

  private clearMessages(): void {
    this.errorMessage = '';
    this.noticeMessage = '';
  }

  private preferredProvider(): AiProviderConfigResponse | undefined {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].defaultProvider) {
        return this.providers[i];
      }
    }
    if (this.providers.length > 0) {
      return this.providers[0];
    }
    return undefined;
  }

  private selectedProvider(): AiProviderConfigResponse | undefined {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === this.selectedProviderId) {
        return this.providers[i];
      }
    }
    return this.preferredProvider();
  }

  private providerById(id: number): AiProviderConfigResponse | undefined {
    for (let i = 0; i < this.providers.length; i++) {
      if (this.providers[i].id === id) {
        return this.providers[i];
      }
    }
    return undefined;
  }

  /** 新增表单默认启用，首个 Provider 自动建议为默认项。 */
  private startAdd(): void {
    this.clearMessages();
    this.lastTest = undefined;
    this.selectedProviderId = 0;
    this.providerName = '';
    this.baseUrl = '';
    this.modelName = '';
    this.apiKey = '';
    this.formEnabled = true;
    this.formDefault = this.providers.length === 0;
    this.pageStage = 'addForm';
  }

  /** 编辑表单只展示脱敏密钥摘要，不把掩码写入 apiKey 输入值。 */
  private startEdit(provider?: AiProviderConfigResponse): void {
    const target = provider !== undefined ? provider : this.selectedProvider();
    if (target === undefined) {
      this.startAdd();
      return;
    }
    this.clearMessages();
    this.lastTest = undefined;
    this.selectedProviderId = target.id;
    this.providerName = target.providerName;
    this.baseUrl = target.baseUrl;
    this.modelName = target.modelName;
    this.apiKey = '';
    this.formEnabled = target.enabled;
    this.formDefault = target.defaultProvider;
    this.pageStage = 'editing';
  }

  /** 识别常见掩码值，避免把展示用的脱敏 key 当作真实密钥提交。 */
  private looksLikeMaskedKey(value: string): boolean {
    const normalized = value.trim();
    return normalized.indexOf('****') >= 0 ||
      normalized.indexOf('***') >= 0 ||
      normalized.indexOf('••••') >= 0 ||
      normalized.indexOf('sk-****') >= 0;
  }

  private validateForm(editing: boolean): boolean {
    if (this.providerName.trim().length === 0 || this.baseUrl.trim().length === 0 || this.modelName.trim().length === 0) {
      this.errorMessage = '请填写 Provider 名称、API Base URL 和模型名称。';
      return false;
    }
    if (!editing && this.apiKey.trim().length === 0) {
      this.errorMessage = '新增 Provider 必须输入真实访问密钥。';
      return false;
    }
    if (this.apiKey.trim().length > 0 && this.looksLikeMaskedKey(this.apiKey.trim())) {
      this.errorMessage = '脱敏展示值不能作为访问密钥提交，请输入真实 API Key 或在编辑时留空沿用原密钥。';
      return false;
    }
    return true;
  }

  /** 提交 Provider 配置；选择测试时会调用真实后端测试接口，不伪造结果。 */
  private async submitProvider(testAfterSave: boolean): Promise<void> {
    const editing = this.pageStage === 'editing' && this.selectedProviderId > 0;
    this.clearMessages();
    if (!this.validateForm(editing)) {
      return;
    }

    const request: AiProviderConfigRequest = {
      providerName: this.providerName.trim(),
      baseUrl: this.baseUrl.trim(),
      modelName: this.modelName.trim(),
      enabled: this.formEnabled,
      defaultProvider: this.formDefault
    };
    const trimmedKey = this.apiKey.trim();
    if (trimmedKey.length > 0) {
      request.apiKey = trimmedKey;
    }

    this.saving = true;
    try {
      const saved = editing ?
        await V2Service.updateProvider(this.selectedProviderId, request) :
        await V2Service.createProvider(request);
      this.apiKey = '';
      this.selectedProviderId = saved.id;
      this.noticeMessage = editing ? 'Provider 配置已更新，页面仍只展示脱敏访问凭据。' : 'Provider 已保存，页面仅展示掩码、尾号与指纹。';
      await this.loadProviders(testAfterSave ? 'providerList' : 'providerList');
      const refreshed = this.providerById(saved.id);
      if (testAfterSave) {
        await this.testProvider(refreshed !== undefined ? refreshed : saved);
      }
    } catch (_) {
      this.pageStage = 'backendError';
      this.errorMessage = editing ? 'Provider 更新失败，请检查配置项和服务状态。' : 'Provider 保存失败，请检查配置项和服务状态。';
    } finally {
      this.saving = false;
    }
  }

  /** 将选中的 AI 服务设为默认配置，后端负责当前用户归属校验。 */
  private async setDefault(provider: AiProviderConfigResponse): Promise<void> {
    this.loading = true;
    this.clearMessages();
    try {
      const request: AiProviderConfigRequest = { defaultProvider: true, enabled: true };
      await V2Service.updateProvider(provider.id, request);
      this.selectedProviderId = provider.id;
      this.noticeMessage = provider.providerName + ' 已设为默认 Provider。';
      await this.loadProviders('defaultSelected');
    } catch (_) {
      this.pageStage = 'backendError';
      this.errorMessage = '默认 Provider 更新失败，请稍后重试。';
    } finally {
      this.loading = false;
    }
  }

  /** 执行后端连接测试，不展示密钥或第三方原始错误正文。 */
  private async testProvider(provider: AiProviderConfigResponse): Promise<void> {
    this.loading = true;
    this.clearMessages();
    try {
      this.lastTest = await V2Service.testProvider(provider.id);
      this.selectedProviderId = provider.id;
      if (!this.lastTest.degraded && this.lastTest.status === 'REAL_SUCCESS') {
        this.pageStage = 'testSuccess';
        this.noticeMessage = 'Provider 连接测试通过。';
      } else {
        this.pageStage = 'testFailed';
        this.errorMessage = '连接测试未通过，请检查访问密钥、Base URL、模型名称或网络状态。';
      }
    } catch (_) {
      this.selectedProviderId = provider.id;
      this.pageStage = 'testFailed';
      this.errorMessage = '服务连接测试失败，页面仅展示脱敏错误信息。';
    } finally {
      this.loading = false;
    }
  }

  /** 调用后端重加密接口，结果仍只展示脱敏元数据。 */
  private async reencryptProvider(provider: AiProviderConfigResponse): Promise<void> {
    this.loading = true;
    this.clearMessages();
    try {
      await V2Service.reencryptProvider(provider.id);
      this.selectedProviderId = provider.id;
      this.noticeMessage = '访问密钥已使用当前运行时密钥重新加密。';
      await this.loadProviders('providerList');
    } catch (_) {
      this.pageStage = 'backendError';
      this.errorMessage = '访问密钥重加密失败，请确认服务端密钥配置可用。';
    } finally {
      this.loading = false;
    }
  }

  /** 删除 Provider 前进入独立危险确认态，避免误删密钥配置。 */
  private requestDelete(provider?: AiProviderConfigResponse): void {
    const target = provider !== undefined ? provider : this.selectedProvider();
    if (target === undefined) {
      return;
    }
    this.clearMessages();
    this.selectedProviderId = target.id;
    this.pageStage = 'deleteConfirm';
  }

  private cancelDelete(): void {
    this.clearMessages();
    this.pageStage = this.providers.length === 0 ? 'noProvider' : 'providerList';
  }

  private async confirmDeleteProvider(): Promise<void> {
    const target = this.selectedProvider();
    if (target === undefined) {
      this.pageStage = 'noProvider';
      return;
    }
    this.loading = true;
    this.clearMessages();
    try {
      await V2Service.deleteProvider(target.id);
      this.selectedProviderId = 0;
      this.noticeMessage = 'Provider 已删除，访问密钥不会保留。';
      await this.loadProviders();
    } catch (_) {
      this.pageStage = 'backendError';
      this.errorMessage = 'Provider 删除失败，请稍后重试。';
    } finally {
      this.loading = false;
    }
  }

  private providerConnectionLabel(provider: AiProviderConfigResponse): string {
    if (!provider.enabled) {
      return '已停用';
    }
    if (!provider.apiKeyConfigured) {
      return '缺少密钥';
    }
    return provider.defaultProvider ? '默认' : '可用';
  }

  private providerConnectionTone(provider: AiProviderConfigResponse): HtmlBadgeTone {
    if (!provider.enabled || !provider.apiKeyConfigured) {
      return 'warn';
    }
    return provider.defaultProvider ? 'ok' : 'neutral';
  }

  private selectedProviderName(): string {
    const target = this.selectedProvider();
    return target !== undefined ? target.providerName : '当前 Provider';
  }

  private selectedProviderHasKey(): boolean {
    const target = this.selectedProvider();
    return target !== undefined && target.apiKeyConfigured;
  }

  private maskedKeyLabel(provider?: AiProviderConfigResponse): string {
    if (provider === undefined) {
      return '保存后显示掩码';
    }
    if (provider.apiKeyMasked !== undefined && provider.apiKeyMasked.length > 0) {
      return provider.apiKeyMasked;
    }
    return provider.apiKeyConfigured ? '已保存访问密钥' : '未保存访问密钥';
  }

  private testMessage(): string {
    if (this.lastTest !== undefined && this.lastTest.message.length > 0) {
      return this.lastTest.message;
    }
    if (this.pageStage === 'testSuccess') {
      return '已通过后端真实连接测试，AI 摘要、纠错、翻译与字段提取功能可使用该 Provider。';
    }
    return '连接测试未通过，请检查访问密钥是否有效、网络是否可达，或稍后重试。密钥不会因失败被记录。';
  }

  @Builder
  private demoZone(note: string) {
    Column({ space: 10 }) {
      StatusBanner({ label: '说明', title: 'BYOK 安全边界', message: note, tone: 'neutral' })
    }
    .width('100%')
  }

  @Builder
  private stateBlock(
    tag: string,
    title: string,
    body: string,
    tone: StatusTone,
    mark: string,
    primaryLabel: string,
    primaryTap: () => void,
    secondaryLabel: string,
    secondaryTap: () => void
  ) {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        HtmlFileMark({ label: mark, tone: tone === 'danger' ? 'danger' : (tone === 'success' ? 'ok' : 'neutral') })
        Column({ space: 7 }) {
          HtmlBadge({ label: tag, tone: tone === 'danger' ? 'danger' : (tone === 'success' ? 'ok' : (tone === 'warning' ? 'warn' : 'neutral')) })
          Text(title)
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(28)
            .width('100%')
          Text(body)
            .fontSize(AppTheme.FONT_META)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(AppTheme.LINE_META)
            .width('100%')
            .maxLines(5)
        }
        .layoutWeight(1)
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      if (primaryLabel.length > 0) {
        TextActionButton({ label: primaryLabel, primary: true, enabledState: !this.loading && !this.saving, onTap: primaryTap })
      }
      if (secondaryLabel.length > 0) {
        TextActionButton({ label: secondaryLabel, enabledState: !this.loading && !this.saving, onTap: secondaryTap })
      }
    }
    .width('100%')
    .padding(AppTheme.CARD_PADDING)
    .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
    .border({ width: AppTheme.HAIRLINE, color: tone === 'danger' ? AppTheme.COLOR_DANGER_LINE : AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_PANEL)
  }

  @Builder
  private providerCard(provider: AiProviderConfigResponse, index: number) {
    Column({ space: 9 }) {
      HtmlListRow({
        title: provider.providerName,
        meta: provider.modelName + ' · ' + provider.secureStorageStatus,
        mark: 'AI',
        badge: this.providerConnectionLabel(provider),
        tone: this.providerConnectionTone(provider),
        index: index,
        onTap: () => {
          this.selectedProviderId = provider.id;
        }
      })
      Row({ space: 8 }) {
        HtmlBadge({
          label: this.maskedKeyLabel(provider),
          tone: provider.apiKeyConfigured ? 'ok' : 'warn'
        })
        HtmlBadge({
          label: provider.apiKeyFingerprint !== undefined && provider.apiKeyFingerprint.length > 0 ? '指纹已记录' : '指纹待确认',
          tone: 'neutral'
        })
      }
      .width('100%')
      .padding({ left: 50, right: 0 })

      Row({ space: 8 }) {
        HtmlCompactActionButton({ label: '编辑', enabledState: !this.loading && !this.saving, onTap: () => this.startEdit(provider) })
          .layoutWeight(1)
        HtmlCompactActionButton({ label: '测试连接', primary: true, enabledState: !this.loading && !this.saving, onTap: () => this.testProvider(provider) })
          .layoutWeight(1)
        HtmlCompactActionButton({ label: provider.defaultProvider ? '已默认' : '设为默认', enabledState: !provider.defaultProvider && !this.loading && !this.saving, onTap: () => this.setDefault(provider) })
          .layoutWeight(1)
        HtmlCompactActionButton({ label: '删除', danger: true, enabledState: !this.loading && !this.saving, onTap: () => this.requestDelete(provider) })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 50, right: 0 })
    }
    .width('100%')
    .padding({ top: 4, bottom: 8 })
  }

  @Builder
  private providerListBlock(note: string) {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '已配置 Provider', meta: this.providers.length > 0 ? '连接状态：按真实测试结果' : '暂无配置' })
      Column({ space: 0 }) {
        if (this.providers.length === 0) {
          StatusBanner({ label: '无 Provider', title: '尚未配置 AI 服务连接', message: '请添加 Provider 并完成真实连接测试。', tone: 'warning' })
        } else {
          ForEach(this.providers, (provider: AiProviderConfigResponse, index?: number) => {
            this.providerCard(provider, index === undefined ? 0 : index)
          }, (provider: AiProviderConfigResponse) => provider.id.toString())
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)

      this.demoZone(note)
    }
    .width('100%')
  }

  @Builder
  private actionScopeBlock() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: 'AI 动作范围', meta: '用于文档处理' })
      Column({ space: 0 }) {
        HtmlListRow({
          title: '摘要 / 纠错 / 翻译',
          meta: '在首页、记录和 OCR 结果页可用',
          mark: 'AI',
          badge: this.providers.length > 0 ? '开启' : '禁用',
          tone: this.providers.length > 0 ? 'ok' : 'warn',
          enabledState: false
        })
        HtmlListRow({
          title: '字段提取 / 智能排版',
          meta: '用于结构化导出与可读性优化',
          mark: 'DOC',
          badge: this.providers.length > 0 ? '开启' : '禁用',
          tone: this.providers.length > 0 ? 'ok' : 'warn',
          enabledState: false
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)

      Row({ space: 8 }) {
        HtmlToolChip({ label: '添加 Provider', primary: true, enabledState: !this.loading && !this.saving, onTap: () => this.startAdd() })
        HtmlToolChip({ label: '编辑', enabledState: this.providers.length > 0 && !this.loading && !this.saving, onTap: () => this.startEdit() })
        HtmlToolChip({ label: '重加密', enabledState: this.selectedProviderHasKey() && !this.loading && !this.saving, onTap: () => {
          const target = this.selectedProvider();
          if (target !== undefined) {
            this.reencryptProvider(target);
          }
        } })
        HtmlToolChip({ label: '删除', enabledState: this.providers.length > 0 && !this.loading && !this.saving, onTap: () => this.requestDelete() })
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private inputField(label: string, placeholder: string, value: string, password: boolean, onChange: (value: string) => void) {
    Column({ space: 6 }) {
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .width('100%')
      TextInput({ placeholder: placeholder, text: value })
        .width('100%')
        .height(AppTheme.INPUT_HEIGHT)
        .type(password ? InputType.Password : InputType.Normal)
        .showPasswordIcon(false)
        .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_CONTROL)
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.COLOR_TEXT)
        .placeholderColor(AppTheme.COLOR_TEXT_SUBTLE)
        .onChange((next: string) => onChange(next))
    }
    .width('100%')
  }

  @Builder
  private toggleRow(label: string, description: string, value: boolean, onChange: (value: boolean) => void) {
    Row({ space: 10 }) {
      Toggle({ type: ToggleType.Switch, isOn: value })
        .enabled(!this.loading && !this.saving)
        .onChange((next: boolean) => onChange(next))
      Column({ space: 2 }) {
        Text(label)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .width('100%')
        Text(description)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 2, right: 2, top: 2, bottom: 2 })
  }

  @Builder
  private providerForm() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: this.pageStage === 'editing' ? '编辑 Provider' : '添加 Provider', meta: this.pageStage === 'editing' ? this.selectedProviderName() : '填写名称、密钥与默认模型' })
      Column({ space: 12 }) {
        this.inputField('Provider 名称', 'Provider A', this.providerName, false, (value: string) => this.providerName = value)
        this.inputField('API Base URL', 'https://api.example.com/v1', this.baseUrl, false, (value: string) => this.baseUrl = value)
        this.inputField('Default model', 'default-model', this.modelName, false, (value: string) => this.modelName = value)
        if (this.pageStage === 'editing') {
          Row({ space: 8 }) {
            HtmlBadge({ label: '当前密钥', tone: 'neutral' })
            Text(this.maskedKeyLabel(this.selectedProvider()))
              .fontSize(AppTheme.FONT_META)
              .fontColor(AppTheme.COLOR_TEXT_MUTED)
              .layoutWeight(1)
              .maxLines(1)
          }
          .width('100%')
        }
        this.inputField(this.pageStage === 'editing' ? '新访问密钥（留空沿用原密钥）' : '访问密钥', this.pageStage === 'editing' ? '留空则继续使用已保存密钥' : '仅提交时使用，保存后不明文展示', this.apiKey, true, (value: string) => this.apiKey = value)
        this.toggleRow('启用 Provider', '停用后不会作为 AI 工作台候选连接。', this.formEnabled, (value: boolean) => this.formEnabled = value)
        this.toggleRow('设为默认 Provider', '后续 AI 操作将优先使用该 Provider。', this.formDefault, (value: boolean) => this.formDefault = value)
        TextActionButton({ label: this.saving ? '保存中...' : '保存并测试连接', primary: true, enabledState: !this.saving && !this.loading, onTap: () => this.submitProvider(true) })
        TextActionButton({ label: '仅保存', enabledState: !this.saving && !this.loading, onTap: () => this.submitProvider(false) })
      }
      .width('100%')
      .padding(AppTheme.CARD_PADDING)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_PANEL)
      Text('API Key 仅显示掩码 / 尾号，不展示明文，不写入日志。')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
        .lineHeight(AppTheme.LINE_CAPTION)
        .width('100%')
        .padding({ left: 4, right: 4 })
    }
    .width('100%')
  }

  @Builder
  private dangerZone() {
    Column({ space: 13 }) {
      HtmlSectionHead({ title: this.selectedProvider() !== undefined ? '删除 ' + this.selectedProviderName() + '？' : '删除 Provider？', meta: '危险操作' })
      Column({ space: 12 }) {
        StatusBanner({
          label: '危险',
          title: '删除后将解绑访问密钥',
          message: '依赖它的 AI 功能将不可用，直到你重新配置。密钥不会保留，也不会在页面中回显。',
          tone: 'danger'
        })
        Row({ space: 8 }) {
          TextActionButton({ label: this.loading ? '删除中...' : '确认删除', primary: true, danger: true, enabledState: !this.loading && !this.saving, onTap: () => this.confirmDeleteProvider() })
            .layoutWeight(1)
          TextActionButton({ label: '保留', enabledState: !this.loading && !this.saving, onTap: () => this.cancelDelete() })
            .layoutWeight(1)
        }
        .width('100%')
      }
      .width('100%')
      .padding(AppTheme.CARD_PADDING)
      .backgroundColor(AppTheme.COLOR_DANGER_BG)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_DANGER_LINE })
      .borderRadius(AppTheme.RADIUS_PANEL)
    }
    .width('100%')
  }

  @Builder
  private stageContent() {
    if (this.pageStage === 'noProvider') {
      this.stateBlock(
        '无 Provider',
        '尚未配置 AI 服务连接',
        '连接 Provider 后可在文档识别结果页使用摘要、纠错、翻译与字段提取等 AI 功能。API Key 仅显示掩码，不会明文展示。',
        'neutral',
        'AI',
        '添加 Provider',
        () => this.startAdd(),
        '',
        () => {}
      )
    } else if (this.pageStage === 'providerList') {
      this.providerListBlock('API Key 界面仅显示掩码 / 尾号，不展示明文。')
      this.actionScopeBlock()
    } else if (this.pageStage === 'addForm') {
      this.providerForm()
      this.demoZone('新增表单会短暂持有用户输入的真实 API Key；保存后清空输入，仅保留后端返回的脱敏元数据。')
    } else if (this.pageStage === 'editing') {
      this.providerForm()
      this.demoZone('编辑态密钥保持掩码展示；不输入新密钥时沿用后端已加密保存的旧密钥。')
    } else if (this.pageStage === 'testSuccess') {
      this.stateBlock(
        '连接测试成功',
        this.selectedProviderName() + ' 连接正常',
        this.testMessage(),
        'success',
        'AI',
        '设为默认',
        () => {
          const target = this.selectedProvider();
          if (target !== undefined) {
            this.setDefault(target);
          }
        },
        '返回列表',
        () => this.loadProviders('providerList')
      )
    } else if (this.pageStage === 'testFailed') {
      this.stateBlock(
        '连接测试失败',
        '无法连接 Provider',
        this.testMessage(),
        'danger',
        'AI',
        '检查密钥',
        () => this.startEdit(),
        '重试连接',
        () => {
          const target = this.selectedProvider();
          if (target !== undefined) {
            this.testProvider(target);
          }
        }
      )
    } else if (this.pageStage === 'defaultSelected') {
      this.providerListBlock(this.selectedProviderName() + ' 已设为默认。')
      this.stateBlock(
        '已设为默认',
        this.selectedProviderName() + ' 已设为默认',
        '后续 AI 操作将默认使用该 Provider，你可以随时在列表中切换默认项。',
        'success',
        'AI',
        '',
        () => {},
        '返回列表',
        () => this.pageStage = 'providerList'
      )
    } else if (this.pageStage === 'deleteConfirm') {
      this.providerListBlock('待删除 Provider 预览。')
      this.dangerZone()
    } else {
      this.stateBlock(
        '后端不可用',
        'AI 服务暂时不可用',
        this.errorMessage.length > 0 ? this.errorMessage : '当前无法连接 AI 服务后端，Provider 配置暂时无法加载或保存。请检查网络后重试。',
        'danger',
        'AI',
        '重试连接',
        () => this.loadProviders(),
        '',
        () => {}
      )
    }
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: AppTheme.SECTION_GAP }) {
            HtmlAppBar({
              title: 'AI 服务连接',
              subtitle: 'ByokProviderPage · 配置 Provider 与访问密钥',
              actionLabel: '刷新',
              actionIcon: 'key',
              onAction: () => this.loadProviders()
            })

            if (this.noticeMessage.length > 0 && this.pageStage !== 'testSuccess' && this.pageStage !== 'defaultSelected') {
              StatusBanner({ label: '完成', title: '服务连接状态', message: this.noticeMessage, tone: 'success' })
            }
            if (this.errorMessage.length > 0 && this.pageStage !== 'backendError' && this.pageStage !== 'testFailed') {
              StatusBanner({ label: '错误', title: '服务连接操作失败', message: this.errorMessage, tone: 'danger' })
            }

            this.stageContent()

            TextActionButton({ label: '返回我的', enabledState: !this.loading && !this.saving, onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.PROFILE) })
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
