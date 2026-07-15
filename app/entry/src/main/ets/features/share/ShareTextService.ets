import { common, Want } from '@kit.AbilityKit';

/**
 * ShareTextService 封装 V1.1 文本分享能力，属于 share 功能模块。
 * 维护说明：服务只拉起系统分享意图，由用户选择目标；不会自动发送第三方，也不会记录 OCR 全文。
 */
export class ShareTextService {
  /**
   * 拉起系统文本分享。
   * 参数 title 仅作为分享面板标题摘要，text 为用户当前可见文本；系统无匹配目标时向页面抛出脱敏错误。
   */
  static async sharePlainText(
    context: common.UIAbilityContext,
    title: string,
    text: string
  ): Promise<void> {
    const normalized = text.trim();
    if (normalized.length === 0) {
      throw new Error('EMPTY_SHARE_TEXT');
    }
    const want: Want = {
      action: 'ohos.want.action.sendData',
      type: 'text/plain',
      parameters: {
        'ohos.extra.param.key.contentTitle': title,
        'ohos.extra.param.key.shareAbstract': ShareTextService.safeWantText(normalized)
      }
    };
    await context.startAbility(want);
  }

  private static safeWantText(text: string): string {
    return text.length > 180000 ? text.substring(0, 180000) : text;
  }
}
