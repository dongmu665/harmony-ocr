import { AppRoutes } from '../common/routes/AppRoutes';
import { AppNavigator } from '../common/routes/AppNavigator';
import { ApiError } from '../common/network/ApiTypes';
import { AppTheme } from '../common/theme/AppTheme';
import {
  AuthLogoLockup,
  AuthPageAppBar,
  AuthPrimaryButton,
  AuthTextButton
} from '../components/AuthLegalComponents';
import { HtmlStatusBar, StatusBanner } from '../components/BrandComponents';
import { Validators } from '../common/validation/Validators';
import { AuthService } from '../features/auth/AuthService';

/**
 * LoginPage 负责用户登录入口和会话进入，不展示或记录密码、Token 等敏感信息。
 * 维护边界：本次 UI 升级只调整布局、色彩、状态呈现和按钮层级，不改变登录校验、TokenStorage 写入或路由跳转。
 */
@Entry
@Component
struct LoginPage {
  @State username: string = '';
  @State password: string = '';
  @State passwordVisible: boolean = false;
  @State loading: boolean = false;
  @State errorMessage: string = '';

  /**
   * 校验登录表单并调用后端登录接口。
   * 失败行为：仅显示脱敏错误提示；成功后沿用原有 AuthService 和首页跳转流程。
   */
  private async submitLogin(): Promise<void> {
    const usernameError = Validators.validateUsername(this.username);
    if (usernameError.length > 0) {
      this.errorMessage = usernameError;
      return;
    }
    const passwordError = Validators.validateLoginPassword(this.password);
    if (passwordError.length > 0) {
      this.errorMessage = passwordError;
      return;
    }

    this.loading = true;
    this.errorMessage = '';
    try {
      await AuthService.login({
        username: this.username.trim(),
        password: this.password,
        deviceName: 'HarmonyOS'
      });
      AppNavigator.replace(this.getUIContext(), AppRoutes.LOGIN_SUCCESS);
    } catch (error) {
      this.errorMessage = this.toUserMessage(error, '登录失败，请稍后重试');
    } finally {
      this.loading = false;
    }
  }

  /**
   * 将网络层异常转换为页面提示。
   * 安全边界：返回文案不包含密码、Token、Authorization 或后端敏感字段。
   */
  private toUserMessage(error: Object, fallback: string): string {
    if (error instanceof ApiError && error.message.length > 0) {
      return error.message;
    }
    return fallback;
  }

  build() {
    Column({ space: 0 }) {
      HtmlStatusBar()
      Scroll() {
        Stack({ alignContent: Alignment.TopStart }) {
          Column({ space: 13 }) {
          AuthPageAppBar({
            title: '欢迎回来',
            subtitle: '继续处理你的 OCR 文档',
            rightIcon: 'more',
            onRightTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.WELCOME)
          })

          AuthLogoLockup({ compact: true })
            .padding({ top: 0 })

          Column({ space: 12 }) {
            this.field('用户名', '请输入用户名', false)
            this.field('密码', '请输入密码', true)

            Row() {
              AuthTextButton({
                label: '忘记密码',
                onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.RESET_PASSWORD)
              })
              .layoutWeight(1)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            if (this.errorMessage.length > 0) {
              StatusBanner({ label: '错误', title: '登录未完成', message: this.errorMessage, tone: 'danger' })
            }

            AuthPrimaryButton({
              label: this.loading ? '登录中...' : '登录',
              primary: true,
              enabledState: !this.loading,
              onTap: () => this.submitLogin()
            })

            AuthPrimaryButton({
              label: '创建新账号',
              primary: false,
              onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.REGISTER)
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 14 })
          .backgroundColor(AppTheme.COLOR_SURFACE_DOCUMENT)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_PANEL)

          Row({ space: 2 }) {
            Text('登录即表示你同意')
              .fontSize(12)
              .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            AuthTextButton({ label: '《用户协议》', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.AGREEMENT) })
            Text('与')
              .fontSize(12)
              .fontColor(AppTheme.COLOR_TEXT_SUBTLE)
            AuthTextButton({ label: '《隐私政策》', onTap: () => AppNavigator.push(this.getUIContext(), AppRoutes.PRIVACY) })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: AppTheme.PAGE_PADDING, right: AppTheme.PAGE_PADDING, top: AppTheme.STATUS_SAFE_CONTENT_GAP, bottom: 22 })
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
  private field(label: string, placeholder: string, password: boolean) {
    Column({ space: 7 }) {
      Text(label)
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.COLOR_TEXT_MUTED)
        .lineHeight(16)
        .width('100%')
      Stack({ alignContent: Alignment.End }) {
        TextInput({ placeholder, text: password ? this.password : this.username })
          .height(AppTheme.INPUT_HEIGHT)
          .width('100%')
          .type(password && !this.passwordVisible ? InputType.Password : InputType.Normal)
          .fontSize(15)
          .fontColor(AppTheme.COLOR_TEXT)
          .backgroundColor(AppTheme.COLOR_SURFACE_ELEVATED)
          .border({ width: AppTheme.HAIRLINE, color: AppTheme.COLOR_LINE_SOFT })
          .borderRadius(AppTheme.RADIUS_CONTROL)
          .padding({ left: 12, right: password ? 58 : 12 })
          .onChange((value: string) => {
            // 中文说明：输入仅进入页面内存状态，提交前不写日志、不持久化。
            if (password) {
              this.password = value;
            } else {
              this.username = value;
            }
          })
        if (password) {
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
