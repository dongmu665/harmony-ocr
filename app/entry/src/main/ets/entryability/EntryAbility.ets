import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { TokenStorage } from '../common/storage/TokenStorage';
import { HistoryState } from '../features/history/HistoryState';

export default class EntryAbility extends UIAbility {
  private v2AcceptanceWant: Want | undefined = undefined;

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    this.v2AcceptanceWant = want;
    const parameters = want.parameters ?? {};
    AppStorage.setOrCreate('v12AccessToken', String(parameters['v12AccessToken'] ?? ''));
    AppStorage.setOrCreate('v12RefreshToken', String(parameters['v12RefreshToken'] ?? ''));
    launchParam;
    hilog.info(0x0000, 'HarmonyOCR', 'EntryAbility created');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    this.configurePrototypeWindow(windowStage);
    TokenStorage.initialize(this.context)
      .then(() => {
        this.seedV2UiSession()
          .then(() => this.loadStartupPage(windowStage))
          .catch(() => this.loadStartupPage(windowStage));
      })
      .catch(() => {
        TokenStorage.clearMemoryOnly();
        hilog.warn(0x0000, 'HarmonyOCR', 'TokenStorage initialization failed');
        this.seedV2UiSession()
          .then(() => this.loadStartupPage(windowStage))
          .catch(() => this.loadStartupPage(windowStage));
      });
  }

  /**
   * 本地验收测试入口：仅接收命令行传入的一次性测试 Token 并写入正式 TokenStorage。
   * 安全边界：不打印、不持久化到日志；生产启动不会传入 v2UiEntry，因此不改变正常启动路径。
   */
  private async seedV2UiSession(): Promise<void> {
    const parameters = this.v2AcceptanceWant?.parameters ?? {};
    if (String(parameters['v2UiEntry'] ?? '') !== 'true') {
      // 非验收入口必须清空短期 page-stage，避免 C3 验证状态残留到正常启动路径。
      HistoryState.setVerifierStage('');
      HistoryState.setVerifierTagId(0);
      HistoryState.clearSelection();
      return;
    }
    const verifierStage = String(parameters['v33C3Stage'] ?? '');
    HistoryState.setVerifierStage(verifierStage);
    const verifierTagId = Number(parameters['v33C3TagId'] ?? '0');
    HistoryState.setVerifierTagId(Number.isNaN(verifierTagId) ? 0 : verifierTagId);
    const verifierRecordId = String(parameters['v33C3RecordId'] ?? '');
    if (verifierRecordId.length > 0) {
      HistoryState.selectRecord(verifierRecordId);
    } else {
      HistoryState.clearSelection();
    }
    const accessToken = String(parameters['v2UiAccessToken'] ?? '');
    const refreshToken = String(parameters['v2UiRefreshToken'] ?? '');
    await TokenStorage.clearTokens();
    if (accessToken.length > 0 && refreshToken.length > 0) {
      await TokenStorage.saveTokens(accessToken, refreshToken);
    }
  }

  private loadStartupPage(windowStage: window.WindowStage): void {
    const parameters = this.v2AcceptanceWant?.parameters ?? {};
    if (String(parameters['v2UiEntry'] ?? '') === 'true') {
      const page = String(parameters['v2UiPage'] ?? '');
      this.loadContent(windowStage, page.length > 0 ? page : 'pages/HomePage');
      return;
    }
    this.loadSplash(windowStage);
  }

  /**
   * 配置接近 HTML 原型画布的系统栏。
   * 说明：系统状态栏和导航栏保持隐藏；应用内顶部只保留前摄安全区占位，不再自绘时间、电量或网络图标。
   */
  private configurePrototypeWindow(windowStage: window.WindowStage): void {
    windowStage.getMainWindow()
      .then((mainWindow: window.Window) => {
        mainWindow.setWindowLayoutFullScreen(true)
          .catch((error: Error) => {
            hilog.warn(0x0000, 'HarmonyOCR', 'Set layout full screen failed: %{public}s', JSON.stringify(error));
          });
        mainWindow.setWindowSystemBarProperties({
          statusBarColor: '#F3F0E8',
          statusBarContentColor: '#171411',
          navigationBarColor: '#FFFAF2',
          navigationBarContentColor: '#171411'
        })
          .catch((error: Error) => {
            hilog.warn(0x0000, 'HarmonyOCR', 'Set system bar style failed: %{public}s', JSON.stringify(error));
          });
        mainWindow.setWindowSystemBarEnable([])
          .catch((error: Error) => {
            hilog.warn(0x0000, 'HarmonyOCR', 'Hide system bars failed: %{public}s', JSON.stringify(error));
          });
        mainWindow.setSpecificSystemBarEnabled('navigationIndicator', false, false)
          .catch((error: Error) => {
            hilog.warn(0x0000, 'HarmonyOCR', 'Hide navigation indicator failed: %{public}s', JSON.stringify(error));
          });
      })
      .catch((error: Error) => {
        hilog.warn(0x0000, 'HarmonyOCR', 'Get main window failed: %{public}s', JSON.stringify(error));
      });
  }

  private loadSplash(windowStage: window.WindowStage): void {
    this.loadContent(windowStage, 'pages/SplashPage');
  }

  private loadContent(windowStage: window.WindowStage, page: string): void {
    windowStage.loadContent(page, (err) => {
      if (err.code) {
        hilog.error(0x0000, 'HarmonyOCR', 'Load content failed: %{public}s', JSON.stringify(err));
      }
    });
  }
}
