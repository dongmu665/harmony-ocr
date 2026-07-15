/**
 * TextCleaner 提供 OCR 文本基础格式清理能力，属于 common/utils 模块。
 * 维护说明：工具函数不记录 OCR 全文，不发送网络请求，只做本地字符串规范化。
 */
export class TextCleaner {
  /**
   * 统一换行符。
   * 参数 text 为待处理文本；返回值保留原有段落结构，只把 Windows/macOS 旧式换行转换为 \n。
   */
  static normalizeLineBreaks(text: string): string {
    return text.replace(/\r\n/g, '\n').replace(/\r/g, '\n');
  }

  /**
   * 清理 OCR 文本中的多余空白。
   * 参数 text 为当前识别或编辑文本；返回值会去除首尾空白、压缩行内空格并保留基本换行结构。
   */
  static cleanOcrText(text: string): string {
    const normalized = TextCleaner.normalizeLineBreaks(text);
    const lines = normalized.split('\n').map((line: string) => {
      return line.replace(/[ \t]+/g, ' ').trim();
    });
    return lines.join('\n').replace(/\n{3,}/g, '\n\n').trim();
  }

  /**
   * 判断文本是否有实际内容。
   * 参数 text 为用户当前文本；返回 true 表示至少包含字母、数字或中文字符，可继续清理、复制或保存占位。
   */
  static isMeaningfulText(text: string): boolean {
    const compact = TextCleaner.normalizeLineBreaks(text).replace(/\s/g, '');
    return /[A-Za-z0-9\u4E00-\u9FFF]/.test(compact);
  }
}
