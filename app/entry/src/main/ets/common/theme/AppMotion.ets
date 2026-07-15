/**
 * AppMotion 统一管理 Harmony OCR 的原生 ArkUI 微动效参数。
 * 维护边界：这里只定义动效节奏和幅度，仅使用 ArkUI 原生动效，也不读取业务数据或敏感信息。
 */
export class AppMotion {
  static readonly DURATION_FAST: number = 160;
  static readonly DURATION_NORMAL: number = 220;
  static readonly DURATION_SLOW: number = 280;
  static readonly DURATION_APPBAR_ENTER: number = 200;
  static readonly DURATION_SWITCH: number = 180;
  static readonly DURATION_TOAST: number = 220;
  static readonly DURATION_PROGRESS_TWEEN: number = 300;
  static readonly STAGGER_CARD_MS: number = 40;
  static readonly STAGGER_ROW_MS: number = 25;
  static readonly TYPING_INTERVAL_MS: number = 28;
  static readonly ENTER_OFFSET_Y: number = 8;
  static readonly SUBTLE_OFFSET_Y: number = 4;
  static readonly ENTER_SCALE: number = 0.96;
  static readonly PRESS_SCALE: number = 0.97;
}
