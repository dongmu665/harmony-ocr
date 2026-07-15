import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { AppTheme } from '../common/theme/AppTheme';
import { AuthPageAppBar, AuthPrimaryButton, AuthTextButton } from '../components/AuthLegalComponents';
import { HtmlStatusBar, StatusBanner } from '../components/BrandComponents';
import { Validators } from '../common/validation/Validators';

/**
 * ResetPasswordPage 复刻 HTML Reset Password 账号验证页面。
 * 维护说明：当前后端未暴露重置密码接口，本页只做前端验证预留与安全提示，不伪造真实重置成功。
 */
@Entry
@Component
struct ResetPasswordPage {
  @State username: string = '';
  @State newPassword: string = '';
  @State confirmPassword: string = '';
  @State passwordVisible: boolean = false;
  @State notice: string = '';
  @State errorMessage: string = '';

  /**
   * 校验重置密码表单并给出能力边界提示。
   * 安全边界：不调用不存在的后端接口，不记录新密码，不把预留流程写成真实 PASS。
   */
  private submitReset(): void {
    const usernameError = Validators.validateUsername(this.username);
    if (usernameError.length > 0) {
      this.errorMessage = usernameError;
      return;
    }
    const passwordError = Validators.validatePassword(this.newPassword);
    if (passwordError.length > 0) {
      this.errorMessage = passwordError;
      return;
    }
    if (this.newPassword !== this.confirmPassword) {
      this.errorMessage = '两次输入的新密码不一致。';
      return;
    }
    this.errorMessage = '';
    this.notice = '当前页面已完成账号信息校验；账号恢复服务尚未开放，暂不会修改密码。';
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 13 }) {
        AuthPageAppBar({
          title: '验证账号后重置密码',
          subtitle: '安全验证完成后设置新密码',
          rightIcon: 'shield',
          onRightTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY)
        })

        Column({ space: 8 }) {
          Text('找回你的账号访问权限')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.COLOR_TEXT)
            .lineHeight(26)
            .width('100%')
          Text('账号恢复服务开放后，可在完成安全验证后设置新密码。请不要在任何地方泄露验证码或密码。')
            .fontSize(15)
            .fontColor(AppTheme.COLOR_TEXT_MUTED)
            .lineHeight(24)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 13, bottom: 14 })
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)

        Column({ space: 12 }) {
          this.field('用户名', '请输入需要重置的用户名', 'username')
          this.field('新密码', '至少 8 位', 'new')
          this.field('确认新密码', '再次输入新密码', 'confirm')

          if (this.errorMessage.length > 0) {
            StatusBanner({ label: '错误', title: '无法重置', message: this.errorMessage, tone: 'danger' })
          }

          if (this.notice.length > 0) {
            StatusBanner({ label: '提示', title: '账号恢复待开放', message: this.notice, tone: 'warning' })
          }

          AuthPrimaryButton({ label: '验证信息', primary: true, onTap: () => this.submitReset() })
          AuthPrimaryButton({ label: '返回登录', primary: false, onTap: () => AppNavigator.replace(this.getUIContext(), AppRoutes.LOGIN) })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 14 })
        .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
        .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
        .borderRadius(AppTheme.RADIUS_PANEL)
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
        TextInput({ placeholder, text: kind === 'username' ? this.username : (kind === 'new' ? this.newPassword : this.confirmPassword) })
          .height(AppTheme.INPUT_HEIGHT)
          .width('100%')
          .type(kind === 'username' || this.passwordVisible ? InputType.Normal : InputType.Password)
          .fontSize(15)
          .fontColor(AppTheme.COLOR_TEXT)
          .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .padding({ left: 12, right: kind === 'username' ? 12 : 58 })
          .onChange((value: string) => {
            // 中文说明：重置密码输入只保留在内存状态，不写入日志或本地存储。
            if (kind === 'username') {
              this.username = value;
            } else if (kind === 'new') {
              this.newPassword = value;
            } else {
              this.confirmPassword = value;
            }
          })
        if (kind !== 'username') {
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
