/**
 * AppTheme 负责 Harmony OCR 前端的统一视觉 token。
 * 维护边界：这里只保存颜色、字号、间距、圆角和尺寸常量，不读取账号、Token、图片 URI、OCR 全文或对象存储信息。
 * 设计方向：对齐 HTML motion prototype 的 warm Document Workspace：纸张底色、clay brand、olive 辅助色，避免通用蓝色 SaaS、玻璃拟态和发光装饰。
 */
export class AppTheme {
  static readonly COLOR_PAGE: string = '#F3F0E8';
  static readonly COLOR_PAGE_DEEP: string = '#E7DECE';
  static readonly COLOR_SURFACE: string = '#FFFAF2';
  static readonly COLOR_SURFACE_DOCUMENT: string = '#FFFAF2';
  static readonly COLOR_SURFACE_ELEVATED: string = '#FFFDF8';
  static readonly COLOR_SURFACE_SOFT: string = '#FBF3E7';
  static readonly COLOR_SURFACE_WARM: string = '#EDD4C5';
  static readonly COLOR_ACCENT_SOFT: string = '#EED6CB';
  static readonly COLOR_BRAND_SOFT: string = '#F1DFD3';
  static readonly COLOR_PREVIEW_TEXT_LINE: string = '#D7CDBC';
  static readonly COLOR_PREVIEW_ACCENT_LINE: string = '#D6A996';
  static readonly COLOR_PREVIEW_TABLE_BG: string = '#F3ECDF';
  static readonly COLOR_SCAN_BG: string = '#24211D';
  static readonly COLOR_SCAN_LINE: string = '#B86443';
  static readonly COLOR_SCAN_TEXT_MUTED: string = '#D8CBBB';
  static readonly COLOR_SCAN_OVERLAY: string = 'rgba(255, 250, 242, 0.16)';
  static readonly COLOR_SCAN_BORDER: string = 'rgba(255, 250, 242, 0.08)';
  static readonly COLOR_BRAND_OVERLAY: string = 'rgba(184, 100, 67, 0.14)';
  static readonly COLOR_TRANSPARENT: string = 'rgba(0, 0, 0, 0.00)';

  static readonly COLOR_TEXT: string = '#171411';
  static readonly COLOR_DARK: string = '#24211D';
  static readonly COLOR_TEXT_MUTED: string = '#645C51';
  static readonly COLOR_TEXT_SUBTLE: string = '#8A8173';
  static readonly COLOR_TEXT_INVERSE: string = '#FFFAF2';

  static readonly COLOR_BRAND: string = '#B86443';
  static readonly COLOR_BRAND_DARK: string = '#8F482F';
  static readonly COLOR_ACTION: string = '#66735C';
  static readonly COLOR_ACCENT: string = '#B86443';
  static readonly COLOR_ACCENT_DARK: string = '#8F482F';
  static readonly COLOR_SUCCESS: string = '#66735C';
  static readonly COLOR_WARNING: string = '#9A6A22';
  static readonly COLOR_DANGER: string = '#A23D33';
  static readonly COLOR_INFO: string = '#52697B';

  static readonly COLOR_INFO_BG: string = '#E7ECE8';
  static readonly COLOR_SUCCESS_BG: string = '#E5EADF';
  static readonly COLOR_WARNING_BG: string = '#EFE5CE';
  static readonly COLOR_DANGER_BG: string = '#F1DCD7';
  static readonly COLOR_NEUTRAL_BG: string = '#F8F3EA';

  static readonly COLOR_LINE: string = '#D9CFBD';
  static readonly COLOR_LINE_SOFT: string = '#E6DDCF';
  static readonly COLOR_LINE_STRONG: string = '#BCA992';
  static readonly COLOR_DANGER_LINE: string = '#D9A097';
  static readonly COLOR_WARNING_LINE: string = '#D9BD7A';

  static readonly PAGE_PADDING: number = 16;
  static readonly STATUS_SAFE_HEIGHT: number = 34;
  static readonly STATUS_SAFE_CONTENT_GAP: number = 4;
  static readonly CARD_PADDING: number = 16;
  static readonly ITEM_PADDING: number = 13;
  static readonly SECTION_GAP: number = 12;
  static readonly STACK_GAP: number = 12;
  static readonly INLINE_GAP: number = 8;
  static readonly RADIUS_CARD: number = 18;
  static readonly RADIUS_CONTROL: number = 15;
  static readonly RADIUS_BADGE: number = 999;
  static readonly RADIUS_PANEL: number = 20;
  static readonly RADIUS_DOCUMENT: number = 10;

  static readonly FONT_PAGE_TITLE: number = 22;
  static readonly FONT_HERO_TITLE: number = 24;
  static readonly FONT_SECTION_TITLE: number = 16;
  static readonly FONT_CARD_TITLE: number = 16;
  static readonly FONT_BODY: number = 15;
  static readonly FONT_META: number = 13;
  static readonly FONT_CAPTION: number = 12;
  static readonly FONT_BUTTON: number = 14;

  static readonly LINE_HERO_TITLE: number = 28;
  static readonly LINE_PAGE_TITLE: number = 25;
  static readonly LINE_SECTION_TITLE: number = 22;
  static readonly LINE_BODY: number = 24;
  static readonly LINE_META: number = 18;
  static readonly LINE_CAPTION: number = 18;

  static readonly BUTTON_HEIGHT: number = 48;
  static readonly BUTTON_SECONDARY_HEIGHT: number = 48;
  static readonly INPUT_HEIGHT: number = 48;
  static readonly OCR_FRAME_HEIGHT: number = 318;
  static readonly PREVIEW_FRAME_HEIGHT: number = 250;
  static readonly TOOL_BUTTON_HEIGHT: number = 38;
  static readonly ILLUSTRATION_EMPTY_SIZE: number = 124;
  static readonly ILLUSTRATION_HERO_SIZE: number = 128;
  static readonly HAIRLINE: number = 1;
}
