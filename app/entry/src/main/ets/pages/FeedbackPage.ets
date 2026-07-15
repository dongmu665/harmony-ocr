import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { AppTheme } from '../common/theme/AppTheme';
import { HtmlAppBar, HtmlBadge, HtmlSectionHead, SettingActionRow, StatusBanner, TextActionButton } from '../components/BrandComponents';
import { FeedbackService } from '../features/feedback/FeedbackService';
import { FeedbackType } from '../features/feedback/FeedbackModels';

/**
 * FeedbackPage 提供 V1.0 用户反馈提交表单，属于反馈模块。
 * 维护说明：反馈内容由用户主动填写，不自动附带 Token、OCR 全文、图片 URI 或对象存储 key。
 */
@Entry
@Component
struct FeedbackPage {
  @State feedbackType: FeedbackType = 'bug';
  @State content: string = '';
  @State contact: string = '';
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State successMessage: string = '';

  /**
   * 提交用户反馈。
   * 安全注意：仅提交类型、正文和可选联系方式；不在日志或页面中回显敏感凭据。
   */
  private async submitFeedback(): Promise<void> {
    if (this.loading) {
      return;
    }
    const normalizedContent = this.content.trim();
    if (normalizedContent.length < 5) {
      this.errorMessage = '请至少填写 5 个字符的反馈内容。';
      return;
    }
    if (normalizedContent.length > 1000) {
      this.errorMessage = '反馈内容不能超过 1000 个字符。';
      return;
    }
    this.loading = true;
    this.errorMessage = '';
    this.successMessage = '';
    try {
      await FeedbackService.submitFeedback({
        feedbackType: this.feedbackType,
        content: normalizedContent,
        contact: this.contact.trim().length > 0 ? this.contact.trim() : undefined,
        deviceInfo: 'HarmonyOS device',
        appVersion: 'V1.0'
      });
      this.content = '';
      this.contact = '';
      this.successMessage = '反馈已提交，感谢你的帮助。';
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '反馈提交失败，请稍后重试');
    } finally {
      this.loading = false;
    }
  }

  private toUserMessage(error: Error, fallback: string): string {
    const apiError = error as ApiError;
    if (apiError.message && apiError.message.length > 0 && apiError.message.length < 80) {
      return apiError.message;
    }
    return fallback;
  }

  build() {
    Scroll() {
      Stack({ alignContent: Alignment.TopStart }) {
        Column({ space: 16 }) {
        HtmlAppBar({
          title: '用户反馈',
          subtitle: '问题、建议与支持',
          actionLabel: '···'
        })

        Column({ space: 10 }) {
          HtmlSectionHead({ title: '反馈类型', meta: '分类' })
          Row({ space: 8 }) {
            this.typeButton('bug', '问题')
            this.typeButton('suggestion', '建议')
          }
          .width('100%')
          Row({ space: 8 }) {
            this.typeButton('complaint', '投诉')
            this.typeButton('other', '其他')
          }
          .width('100%')
        }
        .width('100%')
        .padding(AppTheme.CARD_PADDING)
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)

        Column({ space: 12 }) {
          HtmlSectionHead({ title: '反馈内容', meta: '不含敏感信息' })
          Row({ space: 8 }) {
            HtmlBadge({ label: '不填密码', tone: 'dark' })
            HtmlBadge({ label: '不附带识别全文', tone: 'neutral' })
          }
          .width('100%')

          TextArea({ placeholder: '请填写反馈内容', text: this.content })
            .width('100%')
            .height(180)
            .fontSize(AppTheme.FONT_BODY)
            .lineHeight(AppTheme.LINE_BODY)
            .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
            .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
            .borderRadius(AppTheme.RADIUS_CONTROL)
            .onChange((value: string) => {
              this.content = value;
            })

          TextInput({ placeholder: '联系方式（可选）', text: this.contact })
            .height(AppTheme.INPUT_HEIGHT)
            .width('100%')
            .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
            .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
            .borderRadius(AppTheme.RADIUS_CONTROL)
            .onChange((value: string) => {
              this.contact = value;
            })
        }
        .width('100%')
        .padding(AppTheme.CARD_PADDING)
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)

        if (this.errorMessage.length > 0) {
          StatusBanner({ label: '错误', title: '反馈未提交', message: this.errorMessage, tone: 'danger' })
        }

        if (this.successMessage.length > 0) {
          StatusBanner({ label: '完成', title: '反馈已提交', message: this.successMessage, tone: 'success' })
        }

        TextActionButton({
          label: this.loading ? '提交中...' : '提交反馈',
          primary: true,
          enabledState: !this.loading,
          onTap: () => this.submitFeedback()
        })

        SettingActionRow({
          title: '返回我的',
          description: '回到账号和支持入口',
          onTap: () => AppNavigator.back(this.getUIContext(), AppRoutes.PROFILE)
        })
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

  @Builder
  private typeButton(value: FeedbackType, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(42)
      .type(ButtonType.Normal)
      .fontSize(AppTheme.FONT_BUTTON)
      .fontColor(this.feedbackType === value ? AppTheme.COLOR_TEXT_INVERSE : AppTheme.COLOR_BRAND)
      .backgroundColor(this.feedbackType === value ? AppTheme.COLOR_BRAND : AppTheme.COLOR_SURFACE_ELEVATED)
      .border({ width: AppTheme.HAIRLINE, color: this.feedbackType === value ? AppTheme.COLOR_BRAND_DARK : AppTheme.COLOR_LINE_SOFT })
      .borderRadius(AppTheme.RADIUS_BADGE)
      .onClick(() => {
        this.feedbackType = value;
      })
  }
}
