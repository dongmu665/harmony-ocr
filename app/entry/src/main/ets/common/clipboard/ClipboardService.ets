import pasteboard from '@ohos.pasteboard';

/**
 * ClipboardService 封装系统剪贴板写入能力，属于前端通用基础设施。
 * 维护说明：本服务只接收调用方已经确认可复制的文本，不记录、不持久化、不上传 OCR 全文。
 */
export class ClipboardService {
  /**
   * 将文本写入系统剪贴板。
   * 参数 text 为用户当前可见的编辑文本；空白文本由调用方拦截，本方法再次防御。
   * 返回 Promise<void>；系统剪贴板不可用或权限异常时向上抛出，由页面展示脱敏错误。
   */
  static async copyPlainText(text: string): Promise<void> {
    const normalized = text.trim();
    if (normalized.length === 0) {
      throw new Error('EMPTY_CLIPBOARD_TEXT');
    }
    const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    await pasteboard.getSystemPasteboard().setData(data);
  }
}
