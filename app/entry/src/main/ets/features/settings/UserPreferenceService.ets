import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

export type RecognitionLanguage = 'auto' | 'zh' | 'en' | 'zh_en';

/**
 * UserPreferences 保存非敏感的本地体验偏好。
 * 维护说明：该模型不保存 OCR 全文、图片 URI、账号凭据、Token 或 AI Provider 配置。
 */
export interface UserPreferences {
  recognitionLanguage: RecognitionLanguage;
  autoCleanFormat: boolean;
}

/**
 * UserPreferenceService 管理 V1.1 本地体验设置，属于 settings 功能模块。
 * 维护说明：设置只保存非敏感偏好，不与 TokenStorage 混用，不保存 OCR 全文、图片 URI 或账号凭据。
 */
export class UserPreferenceService {
  private static readonly STORE_NAME: string = 'harmony_ocr_user_preferences';
  private static readonly KEY_LANGUAGE: string = 'recognition_language';
  private static readonly KEY_AUTO_CLEAN: string = 'auto_clean_format';

  /**
   * 返回默认体验设置。
   * 默认开启格式清理仅影响展示文本初始化，不改变后端保存的 rawText 语义。
   */
  static defaultPreferences(): UserPreferences {
    return {
      recognitionLanguage: 'auto',
      autoCleanFormat: true
    };
  }

  /**
   * 读取用户体验设置。
   * 参数 context 为当前 UIAbilityContext；读取失败时返回安全默认值，避免影响 V1.0 OCR 主链路。
   */
  static async load(context: common.UIAbilityContext): Promise<UserPreferences> {
    const defaults = UserPreferenceService.defaultPreferences();
    try {
      const store = await UserPreferenceService.store(context);
      const languageValue = store.getSync(UserPreferenceService.KEY_LANGUAGE, defaults.recognitionLanguage);
      const cleanValue = store.getSync(UserPreferenceService.KEY_AUTO_CLEAN, defaults.autoCleanFormat);
      return {
        recognitionLanguage: UserPreferenceService.normalizeLanguage(String(languageValue)),
        autoCleanFormat: cleanValue === true
      };
    } catch (_) {
      return defaults;
    }
  }

  /**
   * 保存默认识别语言。
   * 参数 language 只是 OCR 语言提示，不代表新增中文 OCR 能力；后端 Provider 会按当前能力兼容处理。
   */
  static async saveRecognitionLanguage(
    context: common.UIAbilityContext,
    language: RecognitionLanguage
  ): Promise<UserPreferences> {
    const store = await UserPreferenceService.store(context);
    store.putSync(UserPreferenceService.KEY_LANGUAGE, UserPreferenceService.normalizeLanguage(language));
    await store.flush();
    return UserPreferenceService.load(context);
  }

  /**
   * 保存自动清理格式开关。
   * 参数 enabled 仅影响 OCR 完成后的 editedText 初始值；rawText 会继续保留真实识别原文。
   */
  static async saveAutoCleanFormat(
    context: common.UIAbilityContext,
    enabled: boolean
  ): Promise<UserPreferences> {
    const store = await UserPreferenceService.store(context);
    store.putSync(UserPreferenceService.KEY_AUTO_CLEAN, enabled);
    await store.flush();
    return UserPreferenceService.load(context);
  }

  /**
   * 返回识别语言的用户可读标签。
   * 参数 language 仅用于 UI 文案，不代表后端一定启用对应 OCR Provider。
   */
  static languageLabel(language: RecognitionLanguage): string {
    if (language === 'zh') {
      return '中文';
    }
    if (language === 'en') {
      return '英文';
    }
    if (language === 'zh_en') {
      return '中英混合';
    }
    return '自动';
  }

  /**
   * 将前端语言偏好映射为后端 OCR 语言提示。
   * 返回空字符串表示自动识别；中英混合使用逗号分隔语言计划，由后端 Provider 按能力执行。
   */
  static toBackendLanguageHint(language: RecognitionLanguage): string {
    if (language === 'zh') {
      return 'zh-Hans';
    }
    if (language === 'en') {
      return 'en';
    }
    if (language === 'zh_en') {
      return 'zh-Hans,en';
    }
    return '';
  }

  private static async store(context: common.UIAbilityContext): Promise<preferences.Preferences> {
    return preferences.getPreferences(context, UserPreferenceService.STORE_NAME);
  }

  private static normalizeLanguage(value: string): RecognitionLanguage {
    if (value === 'zh' || value === 'en' || value === 'zh_en') {
      return value;
    }
    return 'auto';
  }
}
