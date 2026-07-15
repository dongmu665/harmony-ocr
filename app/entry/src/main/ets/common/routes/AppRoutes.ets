/**
 * AppRoutes 集中维护 ArkUI 页面路由常量，属于 common/routes 模块。
 *
 * 维护说明：路由值只能来自已注册页面路径，调用方不得把用户输入、文件路径、Token 或对象存储 key 拼接进路由。
 */
export class AppRoutes {
  static readonly SPLASH: string = 'pages/SplashPage';
  static readonly WELCOME: string = 'pages/WelcomePage';
  static readonly LOGIN: string = 'pages/LoginPage';
  static readonly REGISTER: string = 'pages/RegisterPage';
  static readonly RESET_PASSWORD: string = 'pages/ResetPasswordPage';
  static readonly CONSENT_DIALOG: string = 'pages/ConsentDialogPage';
  static readonly LOGIN_SUCCESS: string = 'pages/LoginSuccessPage';
  static readonly HOME: string = 'pages/HomePage';
  static readonly CAPTURE: string = 'pages/CapturePage';
  static readonly ALBUM: string = 'pages/AlbumPage';
  static readonly IMAGE_PREVIEW: string = 'pages/ImagePreviewPage';
  static readonly IMAGE_CROP: string = 'pages/ImageCropPage';
  static readonly OCR_PROCESSING: string = 'pages/OcrProcessingPage';
  static readonly OCR_RESULT: string = 'pages/OcrResultPage';
  static readonly HISTORY: string = 'pages/HistoryPage';
  static readonly RECORD_DETAIL: string = 'pages/RecordDetailPage';
  static readonly PROFILE: string = 'pages/ProfilePage';
  static readonly SETTINGS: string = 'pages/SettingsPage';
  static readonly AGREEMENT: string = 'pages/AgreementPage';
  static readonly PRIVACY: string = 'pages/PrivacyPage';
  static readonly ACCOUNT_DELETION: string = 'pages/AccountDeletionPage';
  static readonly DATA_DELETION: string = 'pages/DataDeletionPage';
  static readonly FEEDBACK: string = 'pages/FeedbackPage';
  static readonly BATCH_OCR: string = 'pages/BatchOcrPage';
  static readonly EXPORT_CENTER: string = 'pages/ExportCenterPage';
  static readonly AI_WORKSPACE: string = 'pages/AiWorkspacePage';
  static readonly BYOK_PROVIDER: string = 'pages/ByokProviderPage';
  static readonly QUOTA_CENTER: string = 'pages/QuotaCenterPage';
  static readonly ADMIN_DASHBOARD: string = 'pages/AdminDashboardPage';
}
