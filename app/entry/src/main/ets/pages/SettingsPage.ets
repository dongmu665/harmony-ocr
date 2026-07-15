import { common } from '@kit.AbilityKit';
import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { HtmlAppBar, HtmlBadge, HtmlFileMark, HtmlListRow, HtmlSectionHead, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { CacheCleanupService } from '../features/settings/CacheCleanupService';
import { RecognitionLanguage, UserPreferenceService, UserPreferences } from '../features/settings/UserPreferenceService';

/**
 * SettingsPage 提供 V1.1 的本地体验设置入口。
 * 维护说明：仅保存非敏感偏好，不触碰 Token、账号、云端历史或 OCR 全文。
 */
@Entry
@Component
struct SettingsPage {
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State noticeMessage: string = '';
  @State preferences: UserPreferences = UserPreferenceService.defaultPreferences();
  @State cacheSummary: string = '暂未整理本地缓存';

  aboutToAppear(): void {
    this.loadPreferences();
  }

  /**
   * 读取本地体验偏好。
   * 失败时回退到默认值，避免影响 OCR 主链路。
   */
  private async loadPreferences(): Promise<void> {
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '';
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.preferences = await UserPreferenceService.load(context);
    } catch (_) {
      this.preferences = UserPreferenceService.defaultPreferences();
      this.errorMessage = '设置读取失败，已回退到默认值。';
    } finally {
      this.loading = false;
    }
  }

  private async updateLanguage(language: RecognitionLanguage): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '';
    try {
      this.preferences = await UserPreferenceService.saveRecognitionLanguage(context, language);
      this.noticeMessage = `默认识别语言已保存为：${UserPreferenceService.languageLabel(language)}`;
    } catch (_) {
      this.errorMessage = '默认识别语言保存失败，请稍后重试。';
    } finally {
      this.loading = false;
    }
  }

  private async updateAutoClean(enabled: boolean): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '';
    try {
      this.preferences = await UserPreferenceService.saveAutoCleanFormat(context, enabled);
      this.noticeMessage = enabled ? '文本自动整理已开启。' : '文本自动整理已关闭。';
    } catch (_) {
      this.errorMessage = '文本整理偏好保存失败，请稍后重试。';
    } finally {
      this.loading = false;
    }
  }

  private async clearLocalCache(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.loading = true;
    this.errorMessage = '';
    this.noticeMessage = '';
    try {
      const result = await CacheCleanupService.clearNonCriticalCache(context);
      this.cacheSummary = `已整理 ${result.deletedCount} 个缓存文件，未完成 ${result.failedCount} 个。`;
      this.noticeMessage = this.cacheSummary;
    } catch (_) {
      this.errorMessage = '本地缓存清理失败，请稍后重试。';
    } finally {
      this.loading = false;
    }
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 16 }) {
          HtmlAppBar({
            title: '设置',
            subtitle: '识别偏好 · 文本整理 · 本地存储',
            actionLabel: '···'
          })

          if (this.loading) {
            StatusBanner({ label: '本机', title: '正在保存本地偏好', message: '偏好读取和写入只影响本机体验，不会改动云端历史。', tone: 'info' })
          }

          this.languageSection()

          this.autoCleanSection()

          this.storageSection()

          if (this.errorMessage.length > 0 || this.noticeMessage.length > 0) {
            this.localNotice()
          }

          this.privacySupportSection()

          this.aboutSection()
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
        .padding(AppTheme.PAGE_PADDING)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }

  @Builder
  private languageSection() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '默认识别语言', meta: '识别偏好' })
      Column({ space: 8 }) {
        this.preferenceSummaryRow('DOC', '识别语言', '自动 / 中文 / 英文 / 中英混合', UserPreferenceService.languageLabel(this.preferences.recognitionLanguage))
        Row({ space: 8 }) {
          this.optionChip('自动', this.preferences.recognitionLanguage === 'auto', () => this.updateLanguage('auto'))
          this.optionChip('中文', this.preferences.recognitionLanguage === 'zh', () => this.updateLanguage('zh'))
          this.optionChip('英文', this.preferences.recognitionLanguage === 'en', () => this.updateLanguage('en'))
        }
        .width('100%')
        Row({ space: 8 }) {
          this.optionChip('中英混合', this.preferences.recognitionLanguage === 'zh_en', () => this.updateLanguage('zh_en'))
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 13, right: 13, top: 0, bottom: 12 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CARD)
    }
    .width('100%')
  }

  @Builder
  private autoCleanSection() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '文本整理', meta: '编辑偏好' })
      Column() {
        Row({ space: 10 }) {
          HtmlFileMark({ label: 'AI' })
          Column({ space: 3 }) {
            Text('自动整理')
              .fontSize(AppTheme.FONT_META)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.COLOR_TEXT)
              .lineHeight(AppTheme.LINE_META)
              .width('100%')
            Text('识别后自动清理排版')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
              .lineHeight(AppTheme.LINE_CAPTION)
              .maxLines(1)
              .width('100%')
          }
          .layoutWeight(1)
          HtmlBadge({
            label: this.preferences.autoCleanFormat ? '已开启' : '已关闭',
            tone: this.preferences.autoCleanFormat ? 'ok' : 'neutral'
          })
          Toggle({ type: ToggleType.Switch, isOn: this.preferences.autoCleanFormat })
            .enabled(!this.loading)
            .onChange((value: boolean) => {
              this.updateAutoClean(value);
            })
        }
        .width('100%')
        .height(66)
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .padding({ left: 13, right: 13, top: 0, bottom: 0 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CARD)
    }
    .width('100%')
  }

  @Builder
  private storageSection() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '本地存储', meta: '安全整理' })
      Column({ space: 10 }) {
        Text('可整理本地裁剪缓存和文本导出缓存，不会删除登录状态、账号信息、云端历史或必要偏好。')
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_MUTED)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
        TextActionButton({
          label: '整理本地缓存',
          danger: true,
          enabledState: !this.loading,
          onTap: () => this.clearLocalCache()
        })
        Text(this.cacheSummary)
          .fontSize(AppTheme.FONT_META)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
      }
      .width('100%')
      .padding({ left: 14, right: 14, top: 14, bottom: 14 })
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CARD)
    }
    .width('100%')
  }

  @Builder
  private privacySupportSection() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '隐私与支持', meta: '数据' })
      List({ space: 0 }) {
        ListItem() {
          HtmlListRow({
            index: 0,
            mark: 'ADM',
            title: '隐私政策',
            meta: '数据处理方式',
            badge: 'Legal',
            onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY)
          })
        }
        ListItem() {
          HtmlListRow({
            index: 1,
            mark: 'DOC',
            title: '反馈与帮助',
            meta: '识别错误、导出失败、建议',
            badge: 'Help',
            onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.FEEDBACK)
          })
        }
      }
      .width('100%')
      .height(132)
      .scrollBar(BarState.Off)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CARD)
    }
    .width('100%')
  }

  @Builder
  private aboutSection() {
    Column({ space: 10 }) {
      HtmlSectionHead({ title: '关于', meta: '版本' })
      List({ space: 0 }) {
        ListItem() {
          HtmlListRow({
            index: 0,
            mark: 'DOC',
            title: 'Harmony OCR',
            meta: 'Document Workspace',
            badge: 'v2.0'
          })
        }
      }
      .width('100%')
      .height(66)
      .scrollBar(BarState.Off)
      .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
      .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_CARD)
    }
    .width('100%')
  }

  @Builder
  private preferenceSummaryRow(mark: string, title: string, meta: string, badge: string) {
    Row({ space: 10 }) {
      HtmlFileMark({ label: mark })
      Column({ space: 3 }) {
        Text(title)
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_META)
          .maxLines(1)
          .width('100%')
        Text(meta)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .maxLines(1)
          .width('100%')
      }
      .layoutWeight(1)
      HtmlBadge({ label: badge, tone: 'neutral' })
    }
    .width('100%')
    .height(66)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private localNotice() {
    Row({ space: 10 }) {
      Text(this.errorMessage.length > 0 ? '!' : '✓')
        .width(24)
        .height(24)
        .fontSize(AppTheme.FONT_META)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.errorMessage.length > 0 ? AppTheme.COLOR_DANGER : AppTheme.COLOR_SUCCESS)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.errorMessage.length > 0 ? AppTheme.COLOR_DANGER_BG : AppTheme.COLOR_SUCCESS_BG)
        .border({ width: AppTheme.HAIRLINE, color: this.errorMessage.length > 0 ? AppTheme.COLOR_DANGER_LINE : AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_BADGE)
      Column({ space: 3 }) {
        Text(this.errorMessage.length > 0 ? '设置读取失败，已回退到默认值' : '设置已更新')
          .fontSize(AppTheme.FONT_META)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.COLOR_TEXT)
          .lineHeight(AppTheme.LINE_META)
          .width('100%')
        Text(this.errorMessage.length > 0 ? this.errorMessage : this.noticeMessage)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
          .lineHeight(AppTheme.LINE_CAPTION)
          .width('100%')
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 11, bottom: 11 })
    .backgroundColor(this.errorMessage.length > 0 ? AppTheme.COLOR_WARNING_BG : AppTheme.COLOR_SUCCESS_BG)
    .border({ width: AppTheme.HAIRLINE, color: this.errorMessage.length > 0 ? AppTheme.COLOR_WARNING_LINE : AppTheme.COLOR_LINE_SOFT })
    .borderRadius(AppTheme.RADIUS_CARD)
  }

  @Builder
  private optionChip(label: string, active: boolean, onTap: () => void) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontWeight(FontWeight.Bold)
      .fontColor(active ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_TEXT_MUTED)
      .backgroundColor(active ? AppTheme.COLOR_BRAND_SOFT : AppTheme.COLOR_SURFACE_ELEVATED)
      .border({ width: AppTheme.HAIRLINE, color: active ? AppTheme.COLOR_ACCENT_SOFT : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .enabled(!this.loading)
      .onClick(() => onTap())
  }
}
