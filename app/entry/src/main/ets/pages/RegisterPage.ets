import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { AppTheme } from '../common/theme/AppTheme';
import {
  AuthCheckBox,
  AuthPageAppBar,
  AuthPrimaryButton,
  AuthTextButton
} from '../components/AuthLegalComponents';
import { HtmlBadge, HtmlStatusBar, StatusBanner } from '../components/BrandComponents';
import { Validators } from '../common/validation/Validators';
import { AuthService } from '../features/auth/AuthService';

/**
 * RegisterPage 负责创建账号入口，属于认证模块的注册表单页面。
 * 维护边界：复刻 HTML Register 页面结构，不改变密码规则、注册接口字段或敏感信息处理边界。
 */
@Entry
@Component
struct RegisterPage {
  @State username: string = '';
  @State password: string = '';
  @State nickname: string = '';
  @State passwordVisible: boolean = false;
  @State loading: boolean = false;
  @State errorMessage: string = '';
  @State successMessage: string = '';
  @State acceptedTerms: boolean = false;

  /**
   * 校验注册表单并调用注册接口。
   * 安全边界：密码只传给 AuthService，不写入日志、文档、截图说明或页面持久状态。
   */
  private async submitRegister(): Promise<void> {
    const usernameError = Validators.validateUsername(this.username);
    if (usernameError.length > 0) {
      this.errorMessage = usernameError;
      return;
    }
    const passwordError = Validators.validatePassword(this.password);
    if (passwordError.length > 0) {
      this.errorMessage = passwordError;
      return;
    }
    const nicknameError = Validators.validateNickname(this.nickname);
    if (nicknameError.length > 0) {
      this.errorMessage = nicknameError;
      return;
    }
    if (!this.acceptedTerms) {
      this.errorMessage = '请先阅读并同意用户协议和隐私政策。';
      return;
    }

    this.loading = true;
    this.errorMessage = '';
    this.successMessage = '';
    try {
      const trimmedUsername = this.username.trim();
      await AuthService.register({
        username: trimmedUsername,
        password: this.password,
        nickname: this.nickname.trim().length > 0 ? this.nickname.trim() : undefined
      });
      await AuthService.login({
        username: trimmedUsername,
        password: this.password,
        deviceName: 'HarmonyOS'
      });
      this.successMessage = '注册成功，已登录';
      AppNavigator.replace(this.getUIContext(), AppRoutes.LOGIN_SUCCESS);
    } catch (error) {
      this.errorMessage = this.toUserMessage(error);
    } finally {
      this.loading = false;
    }
  }

  /**
   * 将注册异常转换为可读提示。
   * 返回值仅用于 UI 展示，不包含密码、Token 或其他敏感输入。
   */
  private toUserMessage(error: Object): string {
    if (error instanceof ApiError && error.message.length > 0) {
      return error.message;
    }
    return '网络异常，请稍后重试';
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 16 }) {
        AuthPageAppBar({
          title: '创建账号',
          subtitle: '注册后可同步 OCR 记录与导出历史',
          rightIcon: 'shield',
          onRightTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AGREEMENT)
        })

        Column({ space: 14 }) {
          this.field('用户名', '设置登录用户名', 'username')
          this.field('密码', '至少 8 位', 'password')
          this.field('昵称（可选）', '用于显示在文档协作记录中', 'nickname')

          Text('密码建议至少 8 位，并包含字母与数字。请勿使用常见密码。')
            .fontSize(12)
            .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            .lineHeight(18)
            .width('100%')
            .padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(AppTheme.COLOR_SURFACE_SOFT)
            .borderRadius(AppTheme.RADIUS_CONTROL)

          Row({ space: 8 }) {
            AuthCheckBox({
              checked: this.acceptedTerms,
              onToggle: (checked: boolean) => {
                this.acceptedTerms = checked;
              }
            })

            Row({ space: 2 }) {
              Button('我已阅读并同意')
                .height(32)
                .type(ButtonType.Normal)
                .backgroundColor(AppTheme.COLOR_TRANSPARENT)
                .padding({ left: 0, right: 0 })
                .fontSize(12)
                .fontColor(AppTheme.COLOR_TEXT_MUTED)
                .onClick(() => {
                  this.acceptedTerms = !this.acceptedTerms;
                })
              AuthTextButton({ label: '《用户协议》', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AGREEMENT) })
              Text('和')
                .fontSize(12)
                .fontColor(AppTheme.COLOR_TEXT_MUTED)
              AuthTextButton({ label: '《隐私政策》', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY) })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.errorMessage.length > 0) {
            StatusBanner({ label: '错误', title: '注册未完成', message: this.errorMessage, tone: 'danger' })
          }

          if (this.successMessage.length > 0) {
            StatusBanner({ label: '完成', title: '注册成功', message: this.successMessage, tone: 'success' })
          }

          AuthPrimaryButton({
            label: this.loading ? '注册中...' : '注册并进入',
            primary: true,
            enabledState: !this.loading && this.acceptedTerms,
            onTap: () => this.submitRegister()
          })

          AuthPrimaryButton({
            label: '返回登录',
            primary: false,
            onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.LOGIN)
          })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)

        Row({ space: 8 }) {
          HtmlBadge({ label: 'BCrypt 加密', tone: 'ok' })
          HtmlBadge({ label: '云端同步', tone: 'ok' })
          HtmlBadge({ label: '不记录密码', tone: 'neutral' })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: AppTheme.STATUS_SAFE_CONTENT_GAP, bottom: AppTheme.PAGE_PADDING })
        }
        .width('100%')
        .constraintSize({ minHeight: '100%' })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.COLOR_PAGE)
  }

  @Builder
  private field(label: string, placeholder: string, kind: string) {
    Column({ space: 7 }) {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(16)
        .width('100%')
      Stack({ alignContent: Alignment.End }) {
        TextInput({ placeholder, text: kind === 'username' ? this.username : (kind === 'password' ? this.password : this.nickname) })
          .height(AppTheme.INPUT_HEIGHT)
          .width('100%')
          .type(kind === 'password' && !this.passwordVisible ? InputType.Password : InputType.Normal)
          .fontSize(15)
          .fontColor(AppTheme.COLOR_TEXT)
          .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .padding({ left: 12, right: kind === 'password' ? 58 : 12 })
          .onChange((value: string) => {
            // 中文说明：注册输入仅保留在页面状态，密码提交前不进入日志或持久化存储。
            if (kind === 'username') {
              this.username = value;
            } else if (kind === 'password') {
              this.password = value;
            } else {
              this.nickname = value;
            }
          })
        if (kind === 'password') {
          AuthTextButton({
            label: this.passwordVisible ? '隐藏' : '显示',
            onTap: () => {
              this.passwordVisible = !this.passwordVisible;
            }
          })
          .position({ x: 254, y: 8 })
        }
      }
      .width('100%')
      .height(AppTheme.INPUT_HEIGHT)
    }
    .width('100%')
  }
}
